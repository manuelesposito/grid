// Focus: the front window moves to the middle and everything behind it blurs.
// A Ghostty window grows with its text by the same factor, so every line keeps its length;
// when it would be too tall, only the height gives way. The same key, a click on the blur, or switching apps ends it.
//
// A terminal slides to the middle at its size, then grows there in one soft fade: Grid covers it with its picture,
// changes size and text once, unseen, and fades to a picture of the result, which is exactly the real window.
// Changing a terminal's size or text during an animation re-wraps its lines on every frame, which flickers.
import AppKit
import ScreenCaptureKit

final class Focus {
    var window: AXUIElement?
    var windowID: CGWindowID = 0
    var app: NSRunningApplication?
    var before = CGRect.zero
    var target = CGRect.zero
    var blur: NSWindow?
    var zooming = false
    var terminal = ""
    var observer: NSObjectProtocol?

    // Setting from the menu: how many times bigger the terminal gets.
    var zoom: Double {
        get { UserDefaults.standard.object(forKey: "focusZoom") as? Double ?? 2 }
        set { UserDefaults.standard.set(newValue, forKey: "focusZoom") }
    }
    var textStep = 0.0
    var cellsBefore: [String: Cells] = [:], keepRows = true
    let zoomTime = 0.26, fadeTime = 0.12

    var active: Bool { window != nil }

    // Presses while the window is still moving are ignored, so its old place stays exact.
    var movingUntil = Date.distantPast
    func toggle() -> Bool {
        guard Date() > movingUntil else { return true }
        movingUntil = Date().addingTimeInterval(0.8)
        quietUntil = Date().addingTimeInterval(1.5)
        return active ? end() : start()
    }

    func start() -> Bool {
        guard trusted(), let front = NSWorkspace.shared.frontmostApplication else { return false }
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(front.processIdentifier), kAXFocusedWindowAttribute as CFString, &value)
        guard let value else { return false }
        let w = value as! AXUIElement
        var id: CGWindowID = 0
        guard isNormal(w), _AXUIElementGetWindow(w, &id) == .success, let frame = axFrame(w),
              let screen = NSScreen.screens.max(by: { topLeft($0.frame).intersection(frame).area < topLeft($1.frame).intersection(frame).area }) else { return false }
        window = w; windowID = id; app = front; before = frame
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
                cellsBefore = ghosttyCells()
                // The text change must reach this terminal, even if another window is in front by then.
                terminal = script("tell application \"Ghostty\" to get id of focused terminal of selected tab of front window")?.stringValue ?? ""
                keepRows = size.height < vf.height
            }
        }
        size.height = min(size.height, vf.height)
        target = centred(size, on: CGPoint(x: vf.midX, y: vf.midY))

        // The blur covers the whole screen.
        let b = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        b.isOpaque = false; b.backgroundColor = .clear; b.hasShadow = false; b.animationBehavior = .none
        let view = BlurView()
        view.material = .fullScreenUI; view.blendingMode = .behindWindow; view.state = .active
        view.onClick = { [weak self] in _ = self?.toggle() }
        // Much darker than the blur alone, but not black: what lies behind stays just visible.
        let shade = NSView(frame: view.bounds)
        shade.autoresizingMask = [.width, .height]; shade.wantsLayer = true
        shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        view.addSubview(shade)
        b.contentView = view
        b.alphaValue = 0
        blur = b

        // Switching to another app ends focus.
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let other = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let self, other?.processIdentifier != self.app?.processIdentifier, other?.processIdentifier != ProcessInfo.processInfo.processIdentifier { _ = self.end() }
        }

        if textStep == 0 {
            // Nothing re-wraps: the real window can glide.
            b.order(.below, relativeTo: Int(id))
            fade(b, to: 1)
            glide([(w, frame, target)])
            return true
        }
        // Slide to the middle at the same size, then grow there in one soft fade.
        let middle = centred(frame.size, on: CGPoint(x: target.midX, y: target.midY))
        zooming = true
        b.order(.below, relativeTo: Int(id))
        fade(b, to: 1)
        glide([(w, frame, middle)]) {
            self.swap(w, to: self.target, font: "increase_font_size:\(self.textStep)", opening: true, cover: b) {}
        }
        return true
    }

    func end() -> Bool {
        // A switch of app or a click while the window is still zooming ends focus once it has landed.
        if zooming {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { _ = self.end() }
            return true
        }
        guard let w = window, let b = blur else { return false }
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        let from = axFrame(w) ?? target
        let step = textStep
        window = nil; blur = nil; textStep = 0
        app?.activate()
        if step == 0 {
            glide([(w, from, before)])
            fade(b, to: 0) { b.orderOut(nil) }
            return true
        }
        // Shrink in the middle in one soft fade, then slide back home while the blur clears.
        let small = centred(before.size, on: CGPoint(x: from.midX, y: from.midY))
        swap(w, to: small, font: "decrease_font_size:\(step)", opening: false, cover: b) {
            self.zooming = true
            glide([(w, small, self.before)]) { self.zooming = false }
            self.fade(b, to: 0) { b.orderOut(nil) }
        }
        return true
    }

    // The window changes size and text in place. Grid covers it with its picture and a still of the screen
    // without it, changes it unseen, takes a new picture and fades from the old to the new.
    func swap(_ w: AXUIElement, to b: CGRect, font: String, opening: Bool, cover: NSWindow, done: @escaping () -> Void) {
        let id = windowID
        zooming = true
        Task { @MainActor in
            async let first = shot(id)
            async let screen = screenshot(cover.frame, without: id)
            let (old, still) = await (first, screen)
            let changeReal = {
                if !self.terminal.isEmpty {
                    script("tell application \"Ghostty\" to perform action \"\(font)\" on terminal id \(quoted(self.terminal))")
                }
                place(w, b)
                if opening, !self.cellsBefore.isEmpty {
                    self.target = matchCells(w, frame: b, before: self.cellsBefore, keepRows: self.keepRows, centre: CGPoint(x: b.midX, y: b.midY))
                }
            }
            let finish = { self.zooming = false; done() }
            guard let old, let still else { changeReal(); finish(); return }

            // A hair see-through, so macOS never counts the window behind as hidden: a hidden terminal stops
            // drawing and shows up blank for a moment when uncovered.
            let backdrop = self.overlay(cover.frame)
            let v = NSView(); v.wantsLayer = true; v.layer?.contents = still; v.layer?.contentsGravity = .resize
            backdrop.contentView = v
            backdrop.order(.above, relativeTo: Int(id))
            let from = self.picture(old)
            from.order(.above, relativeTo: backdrop.windowNumber)

            changeReal()
            try? await Task.sleep(for: .milliseconds(60))
            guard let new = await shot(id) else {
                backdrop.orderOut(nil); from.orderOut(nil); finish(); return
            }
            // The bigger picture lies on top and fades: in when growing, out when shrinking.
            let to = self.picture(new)
            if opening {
                to.alphaValue = 0
                to.order(.above, relativeTo: from.windowNumber)
            } else {
                to.order(.below, relativeTo: from.windowNumber)
            }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = self.fadeTime + 0.06
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                if opening { to.animator().alphaValue = 0.99 } else { from.animator().alphaValue = 0 }
            }) {
                backdrop.orderOut(nil); from.orderOut(nil); to.orderOut(nil)
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
        return o
    }

    // The window with its shadow, at its real size.
    func shot(_ id: CGWindowID) async -> Shot? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let win = content.windows.first(where: { $0.windowID == id }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.ignoreShadowsSingleWindow = false; config.showsCursor = false
        // A canvas bigger than window and shadow keeps the picture at its real size.
        config.width = Int((win.frame.width + 240) * scale); config.height = Int((win.frame.height + 240) * scale)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
              let box = solidBox(image), abs(box.width - win.frame.width * scale) <= 1 else { return nil }
        return Shot(image: image, box: box, frame: win.frame, scale: scale)
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

    func fade(_ w: NSWindow, to alpha: CGFloat, done: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ $0.duration = alpha == 0 && w !== blur ? fadeTime : zoomTime; w.animator().alphaValue = alpha }) { done?() }
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

final class BlurView: NSVisualEffectView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}

// A window macOS may place partly off screen (the shadow room of the picture reaches past the edges).
final class FreeWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
