// Focus: the front window moves to the middle and everything behind it blurs.
// A Ghostty window grows with its text by the same factor, so every line keeps its length;
// when it would be too tall, only the height gives way. Focus is a mode: on, the window that is clicked takes
// the middle; a click on the blur sends it home and shows all windows again; the key turns the mode off.
//
// A terminal slides to the middle at its size, then grows there in one soft fade: Grid covers it with its picture,
// changes size and text once, unseen, and fades to a picture of the result, which is exactly the real window.
// Changing a terminal's size or text during an animation re-wraps its lines on every frame, which flickers.
import AppKit
import ScreenCaptureKit
import os

// What Focus does, for `log show --predicate 'subsystem == "grid"' --last 5m`.
let note = Logger(subsystem: "grid", category: "focus")

final class Focus {
    var window: AXUIElement?
    var windowID: CGWindowID = 0
    var app: NSRunningApplication?
    var before = CGRect.zero
    var target = CGRect.zero
    var blur: NSWindow?
    // The same cover on every other screen.
    var others: [NSWindow] = []
    var zooming = false
    var terminal = ""
    // Reads what the terminal is and how many lines it holds, beside the main thread, while the window slides.
    var prepared: Task<Void, Never>?
    var observer: NSObjectProtocol?
    // Tells when the app's front window changes, and whether focus is on its way to another window.
    var watcher: AXObserver?
    var handing = false
    // The window as ScreenCaptureKit knows it; looking it up again for every picture takes a moment.
    var known: SCWindow?
    var screen: NSScreen?
    // Waits for the mouse to let go of an edge before the window is evened out.
    var evening: DispatchWorkItem?
    // Every cover and picture Grid has put on screen, and when Focus last ended: a cover still standing
    // long after the window has gone home is cleared away.
    var made: [NSWindow] = []
    var ended = Date.distantPast
    // Tells the app that a cover is up, so it starts to look for leftovers.
    var onCover: (() -> Void)?

    // Setting from the menu: how many times bigger the terminal gets.
    var zoom: Double {
        get { UserDefaults.standard.object(forKey: "focusZoom") as? Double ?? 2 }
        set { UserDefaults.standard.set(newValue, forKey: "focusZoom") }
    }
    // How dark the background gets on top of the blur: almost black, what lies behind stays just visible.
    let shade = 0.55
    var textStep = 0.0
    var cellsBefore: [String: Cells] = [:], keepRows = true
    // One duration and one curve for everything Focus moves or fades.
    let time = 0.2, power = 3.0

    var active: Bool { window != nil }

    // Presses while the window is still moving are ignored, so its old place stays exact.
    var movingUntil = Date.distantPast
    // Focus is a mode. On, it waits: the window that is clicked next takes the middle. A click on the
    // desktop sends it home and the mode stays on, so the next click can pick another window.
    var armed = false
    var clicks: Any?
    func toggle() -> Bool {
        guard Date() > movingUntil else { return true }
        note.log("toggle armed=\(self.armed) active=\(self.active)")
        if armed {
            armed = false
            if let clicks { NSEvent.removeMonitor(clicks) }; clicks = nil
            movingUntil = Date().addingTimeInterval(0.8)
            return active ? end() : true
        }
        armed = true
        clicks = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            // A moment later the clicked window is the front one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self?.clicked(NSEvent.mouseLocation) }
        }
        return true
    }

    // Control-Option-Left and -Right: the window before or after this one, in reading order of their
    // places on the screen, takes the middle. Without a window in the middle, the front one does.
    func step(_ by: Int) {
        note.log("step \(by) armed=\(self.armed) active=\(self.active) blocked=\(Date() <= self.movingUntil)")
        guard armed else { NSSound.beep(); return }
        guard Date() > movingUntil else { return }
        guard active, let screen else { _ = start(); return }
        let wins = visibleWindows(on: screen)
        func home(_ w: Win) -> CGRect { w.id == windowID ? before : (axFrame(w.ax) ?? .zero) }
        let sorted = wins.sorted { a, b in
            let fa = home(a), fb = home(b)
            return abs(fa.minY - fb.minY) > 40 ? fa.minY < fb.minY : fa.minX < fb.minX
        }
        guard sorted.count > 1, let i = sorted.firstIndex(where: { $0.id == windowID }) else { return }
        let n = sorted[(i + by + sorted.count) % sorted.count]
        var pid: pid_t = 0
        AXUIElementGetPid(n.ax, &pid)
        AXUIElementPerformAction(n.ax, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    // The window goes home and the covers clear; the mode stays on for the next click.
    func home() {
        note.log("home active=\(self.active) zooming=\(self.zooming) blocked=\(Date() <= self.movingUntil)")
        guard active, !zooming, Date() > movingUntil else { return }
        movingUntil = Date().addingTimeInterval(0.3)
        _ = end()
    }

    // The click landed in the front window: that one goes to the middle. Clicks elsewhere (menu bar, desktop,
    // Dock) do nothing. Once a window is in the middle, the hand-over takes care of the next clicks.
    func clicked(_ mouse: NSPoint) {
        guard armed, !active, Date() > movingUntil, let front = frontWindow(), let f = axFrame(front.window) else { return }
        let h = NSScreen.screens.first?.frame.height ?? 0
        guard f.contains(CGPoint(x: mouse.x, y: h - mouse.y)) else { return }
        note.log("clicked window \(front.id)")
        movingUntil = Date().addingTimeInterval(0.3)
        _ = start()
    }

    // The front window of the front app, when it is a real document window.
    func frontWindow() -> (app: NSRunningApplication, window: AXUIElement, id: CGWindowID)? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(front.processIdentifier), kAXFocusedWindowAttribute as CFString, &value)
        guard let value else { return nil }
        let w = value as! AXUIElement
        var id: CGWindowID = 0
        guard isNormal(w), _AXUIElementGetWindow(w, &id) == .success else { return nil }
        return (front, w, id)
    }

    // Covers handed in are still on screen from the window focus comes from.
    func start(reusing covers: [NSWindow] = []) -> Bool {
        guard trusted(), let (front, w, id) = frontWindow(), let frame = axFrame(w),
              let screen = NSScreen.screens.max(by: { topLeft($0.frame).intersection(frame).area < topLeft($1.frame).intersection(frame).area }) else { return false }
        window = w; windowID = id; app = front; before = frame; self.screen = screen
        note.log("start \(id) \(front.localizedName ?? "") reusing=\(covers.count)")
        cellsBefore = [:]

        let vf = topLeft(screen.visibleFrame).insetBy(dx: 16, dy: 16)
        var size = frame.size
        textStep = 0
        if front.bundleIdentifier == "com.mitchellh.ghostty" {
            // Only the text area grows; padding and title bar stay as they are.
            let padX = 2 * ghosttySetting("window-padding-x", 2), padY = 2 * ghosttySetting("window-padding-y", 2) + 32
            let z = min(zoom, Double((vf.width - padX) / (frame.width - padX)))
            if z > 1.05 {
                size = CGSize(width: ((frame.width - padX) * z + padX).rounded(), height: min(((frame.height - padY) * z + padY).rounded(), vf.height))
                // Text grows by the same factor as the window, in steps of half a point.
                textStep = (ghosttySetting("font-size", 13) * (z - 1) * 2).rounded() / 2
                // The terminal of this window is the one whose size changes; remember all sizes now.
                // The text change must reach this terminal, even if another window is in front by then.
                // Both take a moment, so they are read aside: the window starts to move at once.
                terminal = ""
                prepared = Task { @MainActor in
                    async let cells = Task.detached { ghosttyCells() }.value
                    async let id = scriptAside("tell application \"Ghostty\" to get id of focused terminal of selected tab of front window")
                    (self.cellsBefore, self.terminal) = await (cells, id)
                }
                keepRows = size.height < vf.height
            }
        } else if zoom > 1 {
            // Other apps: the window itself grows, when it can; what it shows stays the app's business.
            var settable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(w, kAXSizeAttribute as CFString, &settable)
            if settable.boolValue { size = CGSize(width: min((frame.width * zoom).rounded(), vf.width), height: (frame.height * zoom).rounded()) }
        }
        size.height = min(size.height, vf.height)
        target = centred(size, on: CGPoint(x: vf.midX, y: vf.midY))

        // The blur covers every screen.
        let b: NSWindow
        if covers.isEmpty {
            b = cover(screen)
            others = NSScreen.screens.filter { $0 != screen }.map(cover)
        } else {
            b = covers.first { $0.frame == screen.frame } ?? covers[0]
            others = covers.filter { $0 !== b }
        }
        blur = b

        // Switching to another app, or to another window of this one, takes focus along.
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let other = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let self, other?.processIdentifier != self.app?.processIdentifier, other?.processIdentifier != ProcessInfo.processInfo.processIdentifier { self.handOver() }
        }
        watch(front.processIdentifier, w)

        if textStep == 0 {
            // Nothing re-wraps: the real window can glide.
            for c in [b] + others { c.order(.below, relativeTo: Int(id)); fade(c, to: 1) }
            slide(w, frame, target) {
                // A window that did not take the whole size still sits in the middle.
                guard self.window != nil, self.windowID == id, let f = axFrame(w),
                      abs(f.width - self.target.width) > 2 || abs(f.height - self.target.height) > 2 else { return }
                self.target = self.centred(f.size, on: CGPoint(x: self.target.midX, y: self.target.midY))
                place(w, self.target)
            }
            return true
        }
        // Slide to the middle at the same size, then grow there in one soft fade.
        // The pictures for that fade are taken on the way, so the growing starts as the window lands:
        // the window's own at once, the still of the screen as soon as the blur is fully there.
        let middle = centred(frame.size, on: CGPoint(x: target.midX, y: target.midY))
        zooming = true
        let first = Task { @MainActor in await self.shot(id, w) }
        var still: Task<CGImage?, Never>?
        for c in others { c.order(.below, relativeTo: Int(id)); fade(c, to: 1) }
        b.order(.below, relativeTo: Int(id))
        fade(b, to: 1) { still = Task { @MainActor in await self.screenshot(b.frame, without: id) } }
        slide(w, frame, middle) {
            self.swap(w, to: self.target, font: "increase_font_size:\(self.textStep)", opening: true, cover: b, early: still.map { (first, $0) }) {}
        }
        return true
    }

    // Blur and a dark layer over one whole screen; a click on it sends the window home.
    func cover(_ screen: NSScreen) -> NSWindow {
        let b = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        b.isOpaque = false; b.backgroundColor = .clear; b.hasShadow = false; b.animationBehavior = .none
        b.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = BlurView()
        view.material = .fullScreenUI; view.blendingMode = .behindWindow; view.state = .active
        view.onClick = { [weak self] in
            guard let self else { return }
            note.log("click on the dark active=\(self.active)")
            if self.active { self.home() } else { self.sweep(now: true) }
        }
        let dark = FirstClickView(frame: view.bounds)
        dark.autoresizingMask = [.width, .height]; dark.wantsLayer = true
        dark.layer?.backgroundColor = NSColor.black.withAlphaComponent(shade).cgColor
        view.addSubview(dark)
        b.contentView = view
        b.alphaValue = 0
        made.append(b); onCover?()
        return b
    }

    // Once a second, and on a click on a dark that has nothing in the middle: with Focus idle,
    // whatever Grid still shows comes off the screen.
    func sweep(now: Bool = false) {
        made.removeAll { !$0.isVisible }
        guard !active, !zooming, !handing, now || Date().timeIntervalSince(ended) > 1.5 else { return }
        if !made.isEmpty { note.log("sweep now=\(now) clears \(self.made.count)") }
        for w in made { fade(w, to: 0) { w.orderOut(nil) } }
    }

    // Focus moves on to the window that has just come to the front: the covers stay, the old window
    // goes home behind them, then the new one comes to the middle. Without a real window in front, focus ends.
    func handOver() {
        note.log("handOver active=\(self.active) handing=\(self.handing) zooming=\(self.zooming) front=\(self.frontWindow()?.id ?? 0) mine=\(self.windowID)")
        guard active, !handing else { return }
        if zooming {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.handOver() }
            return
        }
        guard let next = frontWindow(), next.id != windowID, let b = blur else {
            // Nothing real in front for the moment: a click on the Dock, a dialog, an app still waking up.
            // A moment later it is either our window again, another one, or truly nothing: then Focus ends.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard self.active, !self.handing else { return }
                if let n = self.frontWindow() { if n.id != self.windowID { self.handOver() } }
                else { _ = self.end(keeping: false, staying: true) }
            }
            return
        }
        handing = true
        movingUntil = Date().addingTimeInterval(0.5)
        let covers = [b] + others
        let old = windowID, grown = textStep != 0
        // Both windows lie above the blur: the old one is seen sliding home while the next comes to the middle.
        // A grown terminal goes home in one step and does that behind the blur.
        for c in covers { c.order(.below, relativeTo: Int(next.id)); if !grown { c.order(.below, relativeTo: Int(old)) } }
        _ = end(keeping: true) {
            self.handing = false
            if !self.start(reusing: covers) {
                for c in covers { self.fade(c, to: 0) { c.orderOut(nil) } }
            } else if !grown {
                // Home again, the old window goes back under the blur.
                DispatchQueue.main.asyncAfter(deadline: .now() + self.time + 0.05) {
                    guard self.active else { return }
                    for c in covers.reversed() { c.order(.above, relativeTo: Int(old)) }
                }
            }
        }
    }

    // Calls back when another window of the focused app comes to the front.
    func watch(_ pid: pid_t, _ w: AXUIElement) {
        var o: AXObserver?
        AXObserverCreate(pid, { _, _, name, me in
            let focus = Unmanaged<Focus>.fromOpaque(me!).takeUnretainedValue()
            if name as String == kAXResizedNotification { DispatchQueue.main.async { focus.resized() }; return }
            // Sheets and dialogs are no new place for focus; a real window is.
            DispatchQueue.main.async { if let next = focus.frontWindow(), next.id != focus.windowID { focus.handOver() } }
        }, &o)
        guard let o else { return }
        AXObserverAddNotification(o, AXUIElementCreateApplication(pid), kAXFocusedWindowChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        AXObserverAddNotification(o, w, kAXResizedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .commonModes)
        watcher = o
    }

    // A pull on a side edge changes the width on both sides, a pull on the top or bottom the height both
    // ways: the window stays in the middle. Applied the moment the mouse lets go; while it drags, macOS
    // sets the frame itself.
    func resized() {
        guard active, !zooming, !gliding else { return }
        evening?.cancel()
        let item = DispatchWorkItem { [self] in
            if NSEvent.pressedMouseButtons != 0 { resized(); return }
            guard let w = window, let f = axFrame(w) else { return }
            let dw = abs(f.width - target.width) > 2, dh = abs(f.height - target.height) > 2
            guard dw || dh else { return }
            var size = CGSize(width: dw ? f.width : target.width, height: dh ? f.height : target.height)
            if let screen {
                let vf = topLeft(screen.visibleFrame).insetBy(dx: 16, dy: 16)
                size = CGSize(width: min(size.width, vf.width), height: min(size.height, vf.height))
            }
            let new = centred(size, on: CGPoint(x: target.midX, y: target.midY))
            target = new
            slide(w, f, new)
        }
        evening = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    // Keeping = the covers stay for the next window. Staying = the app in front stays in front,
    // for when the person has just switched to it.
    func end(keeping: Bool = false, staying: Bool = false, done: (() -> Void)? = nil) -> Bool {
        // A switch of app while the window is still zooming ends focus once it has landed.
        if zooming {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { _ = self.end(keeping: keeping, staying: staying, done: done) }
            return true
        }
        note.log("end keeping=\(keeping) staying=\(staying) active=\(self.active) step=\(self.textStep)")
        guard let w = window, let b = blur else { return false }
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        if let watcher { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(watcher), .commonModes) }
        watcher = nil
        let from = axFrame(w) ?? target
        let step = textStep
        ended = Date()
        let covers = keeping ? [] : [b] + others
        window = nil; blur = nil; others = []; textStep = 0
        if !keeping && !staying {
            // Bringing an app forward that is in front already makes it busy for a moment, and the slide home waits.
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != app?.processIdentifier { app?.activate() }
        }
        if keeping {
            // Behind the covers nobody watches: the window goes home while the next one is already on its way,
            // a grown terminal in one step.
            if step == 0 { slide(w, from, before) } else {
                if !terminal.isEmpty { script("tell application \"Ghostty\" to perform action \"decrease_font_size:\(step)\" on terminal id \(quoted(terminal))") }
                place(w, before)
            }
            done?()
            return true
        }
        if step == 0 {
            slide(w, from, before) { done?() }
            for c in covers { fade(c, to: 0) { c.orderOut(nil) } }
            return true
        }
        // The blur starts to clear at once, so the key feels answered. Meanwhile the window shrinks
        // in the middle in one soft fade, then slides back home.
        for c in covers { fade(c, to: 0) { c.orderOut(nil) } }
        let small = centred(before.size, on: CGPoint(x: from.midX, y: from.midY))
        swap(w, to: small, font: "decrease_font_size:\(step)", opening: false, cover: nil) {
            self.zooming = true
            self.slide(w, small, self.before) { self.zooming = false; done?() }
        }
        return true
    }

    // The window changes size and text in place. Grid covers it with its picture and a still of the screen
    // without it, changes it unseen, takes a new picture and fades from the old to the new.
    // A shrinking window stays under its old, bigger picture all the time: no still needed, and no cover given.
    func swap(_ w: AXUIElement, to b: CGRect, font: String, opening: Bool, cover: NSWindow?,
              early: (Task<Shot?, Never>, Task<CGImage?, Never>)? = nil, done: @escaping () -> Void) {
        let id = windowID
        zooming = true
        Task { @MainActor in
            var old: Shot?, still: CGImage?
            if let early {
                (old, still) = await (early.0.value, early.1.value)
                // Taken on the way: the picture belongs where the window has come to rest.
                if let o = old, let f = axFrame(w) { old = Shot(image: o.image, box: o.box, frame: f, scale: o.scale) }
            } else if let cover {
                async let first = shot(id, w)
                async let screen = screenshot(cover.frame, without: id)
                (old, still) = await (first, screen)
            } else {
                old = await shot(id, w)
            }
            await self.prepared?.value
            func changeReal() async {
                if !self.terminal.isEmpty {
                    let source = "tell application \"Ghostty\" to perform action \"\(font)\" on terminal id \(quoted(self.terminal))"
                    // On the way out the blur is clearing meanwhile; a wait on the main thread would stop it for a moment.
                    if opening { script(source) } else { await scriptAside(source) }
                }
                place(w, b)
                if opening, !self.cellsBefore.isEmpty {
                    self.target = matchCells(w, frame: b, before: self.cellsBefore, keepRows: self.keepRows, centre: CGPoint(x: b.midX, y: b.midY))
                }
            }
            let finish = { note.log("swap done opening=\(opening)"); self.zooming = false; done() }
            guard let old, cover == nil || still != nil else { await changeReal(); finish(); return }

            // A hair see-through, so macOS never counts the window behind as hidden: a hidden terminal stops
            // drawing and shows up blank for a moment when uncovered.
            var backdrop: NSWindow?
            if let cover {
                let back = self.overlay(cover.frame)
                let v = NSView(); v.wantsLayer = true; v.layer?.contents = still; v.layer?.contentsGravity = .resize
                back.contentView = v
                back.order(.above, relativeTo: Int(id))
                backdrop = back
            }
            let from = self.picture(old)
            from.order(.above, relativeTo: backdrop?.windowNumber ?? Int(id))

            await changeReal()
            guard opening else {
                // Shrunk, the real window lies whole under its old, bigger picture: the picture just fades away.
                try? await Task.sleep(for: .milliseconds(25))
                self.fade(from, to: 0) { from.orderOut(nil); finish() }
                return
            }
            // Matching the lines has waited for the window already, unless it had to nudge it once more.
            if self.cellsBefore.isEmpty || self.target != b { try? await Task.sleep(for: .milliseconds(60)) }
            guard let new = await shot(id, w) else {
                backdrop?.orderOut(nil); from.orderOut(nil); finish(); return
            }
            // The bigger picture lies on top and fades in.
            let to = self.picture(new)
            to.alphaValue = 0
            to.order(.above, relativeTo: from.windowNumber)
            self.fade(to, to: 0.99) {
                backdrop?.orderOut(nil); from.orderOut(nil); to.orderOut(nil)
                finish()
            }
        }
    }

    // A window picture at its place on screen, shadow included.
    func picture(_ shot: Shot) -> NSWindow {
        let s = shot.scale
        let rect = CGRect(x: shot.frame.minX - shot.box.minX / s, y: shot.frame.minY - shot.box.minY / s,
                          width: CGFloat(shot.image.width) / s, height: CGFloat(shot.image.height) / s)
        let pic = overlay(toNS(rect))
        pic.contentView = Card(shot, titleBar: 32)
        return pic
    }

    // A borderless window for pictures: never pushed on screen, never animated by macOS, clicks go through.
    func overlay(_ frame: NSRect) -> NSWindow {
        let o = FreeWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        o.isOpaque = false; o.backgroundColor = .clear; o.hasShadow = false; o.ignoresMouseEvents = true
        o.animationBehavior = .none; o.alphaValue = 0.99
        o.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]
        made.append(o); onCover?()
        return o
    }

    // The window with its shadow, at its real size.
    func shot(_ id: CGWindowID, _ w: AXUIElement) async -> Shot? {
        var win = known
        if win?.windowID != id {
            win = (try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true))?.windows.first { $0.windowID == id }
            known = win
        }
        // The size comes from the window itself: what ScreenCaptureKit remembers is from the first look.
        guard let win, let frame = axFrame(w) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.ignoreShadowsSingleWindow = false; config.showsCursor = false
        // A canvas bigger than window and shadow keeps the picture at its real size.
        config.width = Int((frame.width + 240) * scale); config.height = Int((frame.height + 240) * scale)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
              let box = solidBox(image), abs(box.width - frame.width * scale) <= 1 else { known = nil; return nil }
        return Shot(image: image, box: box, frame: frame, scale: scale)
    }

    // The whole screen with this frame, without one window.
    func screenshot(_ frame: CGRect, without id: CGWindowID) async -> CGImage? {
        guard let screen = NSScreen.screens.first(where: { $0.frame == frame }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == number }) else { return nil }
        let config = SCStreamConfiguration()
        config.width = Int(frame.width * screen.backingScaleFactor); config.height = Int(frame.height * screen.backingScaleFactor)
        config.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { $0.windowID == id })
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    // Grid steps the fade itself, in time with the slide. Left to macOS, a fade that starts on a window
    // just put on screen shows its first third in one jump.
    func fade(_ w: NSWindow, to alpha: CGFloat, done: (() -> Void)? = nil) {
        let duration = time, power = power
        let from = w.alphaValue
        var start: Date?
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
            // The clock starts with the first tick, when the window is really there.
            let s = start ?? Date(); start = s
            let t = min(1, Date().timeIntervalSince(s) / duration), e = 1 - pow(1 - t, power)
            w.alphaValue = from + (alpha - from) * e
            if t >= 1 { timer.invalidate(); done?() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // A slide in Focus's own time and curve. With Reduce Motion on in System Settings the window does not
    // travel: it is simply there, and only the background fades.
    func slide(_ w: AXUIElement, _ from: CGRect, _ to: CGRect, done: (() -> Void)? = nil) {
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        glide([(w, still ? to : from, to)], duration: time, power: power, done: done)
    }

    func centred(_ size: CGSize, on c: CGPoint) -> CGRect {
        CGRect(x: (c.x - size.width / 2).rounded(), y: (c.y - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    // A number from Ghostty's config, or a fallback when it is not set.
    func ghosttySetting(_ key: String, _ fallback: Double) -> Double {
        let path = NSHomeDirectory() + "/.config/ghostty/config"
        let lines = (try? String(contentsOfFile: path, encoding: .utf8))?.split(separator: "\n") ?? []
        for line in lines.reversed() where line.replacingOccurrences(of: " ", with: "").hasPrefix(key + "=") {
            if let v = Double(line.split(separator: "=").last?.trimmingCharacters(in: .whitespaces) ?? "") { return v }
        }
        return fallback
    }
}

// A window frame in top-left coordinates, turned into AppKit's bottom-left ones.
func toNS(_ r: CGRect) -> NSRect {
    let h = NSScreen.screens.first?.frame.height ?? 0
    return NSRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
}


// The first click counts, even though Grid is not the active app: otherwise macOS keeps that click
// to wake Grid, and waking Grid lifts the dark above the window. The click lands on the dark layer,
// which lies over the blur, and passes up to the blur view.
final class BlurView: NSVisualEffectView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

final class FirstClickView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// A window macOS may place partly off screen (the shadow room of the picture reaches past the edges).
final class FreeWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
