// Focus as a row of windows that goes around: the window before and the one after peek in at the screen's
// edges, dimmed (Manuel, 2026-10-01, picked on lab/focus-arrows.html: "Sideways", "Peek in"). When the mouse
// comes near an edge, that peek comes out further, brighter and a touch bigger, as Stage Manager's windows
// answer the mouse (lab/focus-peeks.html: "Far", "Medium", no name, no arrows: the peeks are the buttons).
// A click on a peek, or Control-Option-Left and -Right, slides the row by one: the window in the middle
// moves aside as a peek, the next one comes in from where the peek was.
//
// Only pictures move. The real windows never travel sideways: the one leaving goes home at once, under the
// blur and under its own picture; the one coming is set in the middle under the blur, and once its picture
// has landed the real window is brought up in exactly its place. With Focus Zoom above 1 × a window changes
// size in the middle, so the pictures could not land on it: then Control-Option-Left and -Right step the way they did before.
import AppKit

struct Peek { let pic: CardPanel; let id: CGWindowID; let shot: Shot }

// The window in the middle while the row slides: its picture, and the home the real one goes back to.
struct Middle { let win: Win; let home: CGRect; let shot: Shot; let pic: CardPanel }

// Moving and sizing a real window waits for its app to answer. Done here, the pictures keep their pace.
let axQueue = DispatchQueue(label: "grid.ax", qos: .userInteractive)

extension Focus {
    // How much of a neighbour shows at the edge, and how much smaller it is than in the middle.
    var edge: CGFloat { 56 }
    var peekScale: CGFloat { 0.92 }
    var peekAlpha: CGFloat { 0.6 }
    // A peek the mouse has come near: further out, brighter, a touch bigger, on a quicker spring.
    var outEdge: CGFloat { 150 }
    var outScale: CGFloat { 0.95 }
    var outAlpha: CGFloat { 0.8 }
    var outTime: Double { 0.25 }
    // How near the edge the mouse has to come.
    var near: CGFloat { 120 }
    var sideways: Bool { zoom <= 1 }

    // The windows on this screen in reading order of their home places, the one in the middle at its home.
    // Each home is read once: reading them inside the sort asked every app again and again.
    func ring(_ screen: NSScreen) -> (wins: [Win], homes: [CGWindowID: CGRect]) {
        let wins = visibleWindows(on: screen)
        var homes: [CGWindowID: CGRect] = [:]
        for w in wins { homes[w.id] = w.id == windowID ? before : (axFrame(w.ax) ?? .zero) }
        let sorted = wins.sorted { a, b in
            let fa = homes[a.id]!, fb = homes[b.id]!
            return abs(fa.minY - fb.minY) > 40 ? fa.minY < fb.minY : fa.minX < fb.minX
        }
        return (sorted, homes)
    }

    // Where a picture lies: 0 in the middle, 1 and -1 peeking at the right and left edge, 2 and -2 just past them.
    // Out = the mouse is near that peek.
    // A window has the size it was last pulled to in the middle, if it was, at the edges too.
    func spot(_ s: Shot, _ side: Int, out: Bool = false, id: CGWindowID = 0) -> CGRect {
        guard let screen else { return s.frame }
        let k = side == 0 ? 1 : out ? outScale : peekScale
        let show = out ? outEdge : edge
        let vf = topLeft(screen.visibleFrame).insetBy(dx: 16, dy: 16), sf = topLeft(screen.frame)
        let size = middleSize(id, s.frame.size)
        let w = (min(size.width, vf.width) * k).rounded(), h = (min(size.height, vf.height) * k).rounded()
        let x: CGFloat
        switch side {
        case 0: x = (vf.midX - w / 2).rounded()
        case 1: x = sf.maxX - show
        case -1: x = sf.minX + show - w
        case 2...: x = sf.maxX + 40
        default: x = sf.minX - 40 - w
        }
        let y = (vf.midY - h / 2).rounded()
        // The shadow lies around the window; it keeps its size, only the window inside scales.
        let sc = s.scale
        let l = s.box.minX / sc, t = s.box.minY / sc
        let r = CGFloat(s.image.width) / sc - s.box.maxX / sc, b = CGFloat(s.image.height) / sc - s.box.maxY / sc
        return CGRect(x: x - l, y: y - t, width: w + l + r, height: h + t + b)
    }

    func middleSize(_ id: CGWindowID, _ home: CGSize) -> CGSize { sizes[id] ?? home }

    // A picture that can be clicked: a click on a peek slides the row towards it.
    // Its panel has the size of the biggest place the picture takes and never changes size: a window that is
    // resized on every frame of a motion makes the screen redraw its shadow each time, and the slide stutters
    // (Manuel, 2026-10-02: "it's the shadow"). Only the panel moves; the picture shrinks and grows inside it.
    func peekWindow(_ s: Shot, id: CGWindowID, side: Int, at exact: CGRect? = nil) -> CardPanel {
        let mid = spot(s, 0, id: id), first = exact ?? spot(s, side, id: id)
        // Room around for the bigger shadow of the window once it is in front (blendIn()).
        let size = CGSize(width: max(mid.width, first.width) + 80, height: max(mid.height, first.height) + 80)
        let p = CardPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.hidesOnDeactivate = false
        p.animationBehavior = .none; p.alphaValue = 0
        p.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.base = size
        let tap = Tap(frame: NSRect(origin: .zero, size: size))
        let card = Card(s, titleBar: 32)
        tap.addSubview(card); tap.card = card; tap.cards = [card]; tap.edges = card.edges
        tap.onClick = { [weak self, weak p] in
            guard let self, let p, let side = self.peeks.first(where: { $0.value.pic === p })?.key else { return }
            self.step(side < 0 ? -1 : 1)
        }
        p.contentView = tap
        show(p, toNS(first))
        made.append(p); onCover?()
        return p
    }

    // The picture shows at r (screen coordinates): the panel moves, the picture takes r's size inside it.
    func show(_ p: CardPanel, _ r: NSRect) {
        let x = ((p.base.width - r.width) / 2).rounded(), y = ((p.base.height - r.height) / 2).rounded()
        p.setFrameOrigin(NSPoint(x: r.minX - x, y: r.minY - y))
        p.visual = r
        guard let tap = p.contentView as? Tap else { return }
        // r holds the first picture's shadow; a later one with another shadow lies around the same window.
        let e0 = tap.edges
        for case let c as Card in tap.cards {
            let e = c.edges
            c.frame = NSRect(x: x + e0.left - e.left, y: y + e0.bottom - e.bottom,
                             width: r.width - e0.left - e0.right + e.left + e.right,
                             height: r.height - e0.top - e0.bottom + e.top + e.bottom)
        }
    }

    // A picture glides to a place and an alpha on the way home's clock and curve. A new glide of the same
    // picture takes over from the old one where it is.
    func move(_ o: CardPanel, to r: CGRect, alpha: CGFloat, duration: Double? = nil, done: (() -> Void)? = nil) {
        o.motion?.invalidate()
        let duration = duration ?? homeTime
        let from = o.visual, to = toNS(r), a0 = o.alphaValue
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var start: Date?
        o.motion = Ticker { [weak self] t in
            let s = start ?? Date(); start = s
            let p = still ? 1 : min(1, Date().timeIntervalSince(s) / duration), e = spring(p)
            self?.show(o, NSRect(x: from.minX + (to.minX - from.minX) * e, y: from.minY + (to.minY - from.minY) * e,
                                 width: from.width + (to.width - from.width) * e, height: from.height + (to.height - from.height) * e))
            o.alphaValue = a0 + (alpha - a0) * e
            if p >= 1 { t.invalidate(); o.motion = nil; done?() }
        }
    }

    // The neighbours come in from past the edges once the window has landed in the middle.
    func showPeeks() {
        guard active, sideways, !handing, let screen, let b = blur else { return }
        // The blur has just been put under the window in the middle; the peeks lie above it again.
        for p in peeks.values { p.pic.order(.above, relativeTo: b.windowNumber) }
        watch()
        let r = ring(screen).wins, mine = windowID
        guard r.count > 1, let i = r.firstIndex(where: { $0.id == mine }) else { return }
        var sides = [(1, r[(i + 1) % r.count])]
        if r.count > 2 { sides.append((-1, r[(i - 1 + r.count) % r.count])) }
        for (side, win) in sides where peeks[side]?.id != win.id {
            Task { @MainActor in
                guard let s = await self.shot(win.id, win.ax, remember: false),
                      self.active, self.windowID == mine, !self.handing, self.peeks[side]?.id != win.id else { return }
                self.addPeek(s, id: win.id, side: side, above: b)
            }
        }
    }

    func addPeek(_ s: Shot, id: CGWindowID, side: Int, above b: NSWindow) {
        if let old = peeks[side] { fade(old.pic, to: 0) { old.pic.orderOut(nil) } }
        let p = peekWindow(s, id: id, side: side * 2)
        p.order(.above, relativeTo: b.windowNumber)
        peeks[side] = Peek(pic: p, id: id, shot: s)
        move(p, to: spot(s, side, out: out == side, id: id), alpha: out == side ? outAlpha : peekAlpha)
        runQueued()
    }

    // A step pressed during the last slide goes once its peek is there.
    func runQueued() {
        guard let q = queued, active, !handing, peeks[q < 0 ? -1 : 1] != nil else { return }
        queued = nil
        note.log("queued step \(q)")
        step(q)
    }

    // The next window comes to the front under the blur, and once it is there its picture is taken again and
    // blends into the sliding picture: the title bar and the shadow of a window in front.
    func bringForward(_ next: Win, into pic: CardPanel) {
        var pid: pid_t = 0
        AXUIElementGetPid(next.ax, &pid)
        NSRunningApplication(processIdentifier: pid)?.activate()
        var tries = 0
        func shoot() {
            tries += 1
            guard handing, pic.motion != nil else { return }
            if frontWindow()?.id != next.id && tries < 12 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: shoot); return
            }
            Task { @MainActor in
                guard let s = await self.shot(next.id, next.ax, remember: false) else { return }
                self.blendIn(s, into: pic)
            }
        }
        shoot()
    }

    func blendIn(_ s: Shot, into p: CardPanel) {
        guard let tap = p.contentView as? Tap, tap.cards.count == 1, let old = tap.cards.first else { return }
        let card = Card(s, titleBar: 32)
        card.alphaValue = 0
        tap.addSubview(card)
        tap.cards.append(card)
        show(p, p.visual)
        var start: Date?
        p.blend = Ticker { t in
            let st = start ?? Date(); start = st
            let k = min(1, Date().timeIntervalSince(st) / 0.12)
            card.alphaValue = k
            if k >= 1 {
                t.invalidate(); p.blend = nil
                // tap.edges stays the first picture's: the panel's places are measured with it.
                old.removeFromSuperview(); tap.cards = [card]; tap.card = card
            }
        }
    }

    // A picture of the window in the middle is kept fresh while the mouse is off it, the only time a step
    // can come (a click on a peek, a plain arrow). Taken at the step, it held the slide back a tenth of a second.
    func refreshMiddle() {
        guard sideways, textStep == 0, !shooting, !handing, let w = window else { return }
        if let m = middleShot, m.id == windowID, Date().timeIntervalSince(m.at) < 0.5 { return }
        shooting = true
        let id = windowID
        Task { @MainActor in
            let s = await self.shot(id, w)
            self.shooting = false
            if let s, self.windowID == id, !self.handing { self.middleShot = (id, s, Date()) }
        }
    }

    func clearPeeks() {
        for (_, p) in peeks { fade(p.pic, to: 0) { p.pic.orderOut(nil) } }
        peeks = [:]
    }

    // The row slides by one. False when it cannot, and the step goes the old way.
    func slideStep(_ by: Int) -> Bool {
        guard sideways, active, !handing, textStep == 0, let screen, let w = window, let b = blur else { return false }
        let (r, homes) = ring(screen)
        guard r.count > 1, let i = r.firstIndex(where: { $0.id == windowID }) else { return false }
        let next = r[(i + by + r.count) % r.count]
        guard peeks.values.contains(where: { $0.id == next.id }) else {
            // Its picture is still on its way: the step waits for it, a moment at most, then goes the old way.
            queued = by
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if self.queued == by, self.active, !self.handing { self.queued = nil; self.raise(next) }
            }
            return true
        }
        // The row keeps this order and these homes until a window is brought forward again.
        lane = r; laneHomes = homes
        handing = true
        movingUntil = Date().addingTimeInterval(homeTime + 0.6)
        out = 0
        let covers = [b] + others, oldID = windowID, oldHome = before, me = r[i]
        // A picture of the window in the middle from the last second, if it still has that size.
        let ready = middleShot.flatMap { m in
            m.id == oldID && Date().timeIntervalSince(m.at) < 1 && axFrame(w) == m.shot.frame ? m.shot : nil
        }
        middleShot = nil

        func go(_ cur: Shot) {
            // Its picture covers the real window, which then goes home under the blur.
            let sc = cur.scale
            let exact = CGRect(x: cur.frame.minX - cur.box.minX / sc, y: cur.frame.minY - cur.box.minY / sc,
                               width: CGFloat(cur.image.width) / sc, height: CGFloat(cur.image.height) / sc)
            let pic = peekWindow(cur, id: oldID, side: 0, at: exact)
            pic.alphaValue = 1
            // While the row slides, blur and pictures lie above every window, so the next one can come to the
            // front under them before its picture lands (roll()).
            pic.level = .floating; pic.orderFront(nil)
            for c in covers { c.level = .floating; c.order(.below, relativeTo: pic.windowNumber) }
            for p in peeks.values { p.pic.level = .floating; p.pic.order(.above, relativeTo: b.windowNumber) }
            unwatch()
            window = nil; blur = nil; others = []
            roll(by, from: Middle(win: me, home: oldHome, shot: cur, pic: pic), covers: covers, blur: b, screen: screen)
        }
        if let ready { go(ready); return true }
        Task { @MainActor in
            guard let cur = await self.shot(oldID, w) else { self.handing = false; return }
            go(cur)
        }
        return true
    }

    // One slide of the row: the middle picture moves aside as a peek, the peek on the other side comes in.
    func roll(_ by: Int, from mid: Middle, covers: [NSWindow], blur b: NSWindow, screen: NSScreen) {
        let n = lane.count
        guard let i = lane.firstIndex(where: { $0.id == mid.win.id }) else { return arrive(mid, covers: covers) }
        let next = lane[(i + by + n) % n]
        guard let incoming = peeks.values.first(where: { $0.id == next.id }), let nextHome = laneHomes[next.id] else {
            return arrive(mid, covers: covers)
        }
        note.log("slide \(by) from \(mid.win.id) to \(next.id)")
        // The next one waits in the middle, under the blur, for its picture to land on it; the one leaving
        // goes home. Both once the pictures are on screen, beside the main thread.
        let vf = topLeft(screen.visibleFrame).insetBy(dx: 16, dy: 16)
        let m = middleSize(next.id, nextHome.size)
        let middle = centred(CGSize(width: min(m.width, vf.width), height: min(m.height, vf.height)), on: CGPoint(x: vf.midX, y: vf.midY))
        // Then the next one is brought to the front, unseen under the blur: in front its shadow is bigger, and
        // its picture takes that look on the way in, so nothing jumps when the real window comes up.
        DispatchQueue.main.async {
            axQueue.async {
                place(mid.win.ax, mid.home); place(next.ax, middle)
                AXUIElementPerformAction(next.ax, kAXRaiseAction as CFString)
                DispatchQueue.main.async { self.bringForward(next, into: incoming.pic) }
            }
        }
        let after = n > 2 ? lane[(i + 2 * by + 2 * n) % n] : nil
        // The picture of the window after next is taken meanwhile.
        let coming = after.map { a in Task { @MainActor in await self.shot(a.id, a.ax, remember: false) } }

        var row: [Int: Peek] = [:]
        // The peek on the far side leaves past the edge; the window in the middle takes its place.
        if let gone = peeks[-by], gone.id != next.id {
            move(gone.pic, to: spot(gone.shot, -2 * by, id: gone.id), alpha: 0) { gone.pic.orderOut(nil) }
        }
        if let left = peeks[by], left.id != next.id {
            move(left.pic, to: spot(left.shot, 2 * by, id: left.id), alpha: 0) { left.pic.orderOut(nil) }
        }
        row[-by] = Peek(pic: mid.pic, id: mid.win.id, shot: mid.shot)
        move(mid.pic, to: spot(mid.shot, -by, id: mid.win.id), alpha: peekAlpha)
        peeks = row
        move(incoming.pic, to: spot(incoming.shot, 0, id: next.id), alpha: 1) {
            self.landed(Middle(win: next, home: nextHome, shot: incoming.shot, pic: incoming.pic), covers: covers, blur: b, screen: screen)
        }
        guard let coming, let a = after, a.id != mid.win.id else { return }
        Task { @MainActor in
            // Only into this row: a later slide has a row of its own.
            guard let s = await coming.value, self.peeks[by]?.id != a.id, self.peeks[-by]?.id == mid.win.id else { return }
            let p = self.peekWindow(s, id: a.id, side: 2 * by)
            if self.handing { p.level = .floating }
            p.order(.above, relativeTo: b.windowNumber)
            self.peeks[by] = Peek(pic: p, id: a.id, shot: s)
            self.move(p, to: self.spot(s, by, id: a.id), alpha: self.peekAlpha)
            self.runQueued()
        }
    }

    // A picture has landed in the middle. Another press waiting: the row slides on from the picture, and no
    // window is brought forward on the way, so the keys can go as fast as the row. Else the real window comes up.
    func landed(_ mid: Middle, covers: [NSWindow], blur b: NSWindow, screen: NSScreen) {
        if let q = queued, peeks[q < 0 ? -1 : 1] != nil {
            queued = nil
            roll(q, from: mid, covers: covers, blur: b, screen: screen)
            return
        }
        arrive(mid, covers: covers)
    }

    // The real window comes up in its picture's place and Focus goes on with it.
    func arrive(_ mid: Middle, covers: [NSWindow]) {
        // Once the real windows have been moved (axQueue), the next one is brought forward.
        axQueue.async { DispatchQueue.main.async { self.raiseArrived(mid, covers: covers) } }
    }

    func raiseArrived(_ mid: Middle, covers: [NSWindow]) {
        let next = mid.win, picture = mid.pic
        var pid: pid_t = 0
        AXUIElementGetPid(next.ax, &pid)
        AXUIElementPerformAction(next.ax, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
        var tries = 0
        func ready() {
            tries += 1
            if frontWindow()?.id != next.id && tries < 25 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: ready); return
            }
            handing = false
            movingUntil = .distantPast
            // Blur and peeks go back among the windows; the picture, still above all, hides the change.
            for c in covers { c.level = .normal }
            for p in peeks.values { p.pic.level = .normal }
            if !start(reusing: covers, home: mid.home) {
                for c in covers { fade(c, to: 0) { c.orderOut(nil) } }
                clearPeeks(); unwatchMouse()
            } else { runQueued() }
            // The real window is drawn under its picture, then the picture fades: the window's own shadow,
            // a little bigger now that it is in front, comes in softly instead of in one frame.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.fade(picture, to: 0, duration: 0.12) { picture.orderOut(nil) }
            }
        }
        ready()
    }

    // MARK: The mouse near an edge

    // Looked at 30 times a second while Focus shows peeks: cheaper than a mouse monitor, and it sees the
    // mouse over Grid's own covers too, which a global monitor does not.
    func watch() {
        guard mouseWatch == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.watchMouse() }
        RunLoop.main.add(t, forMode: .common)
        mouseWatch = t
    }

    func unwatchMouse() {
        mouseWatch?.invalidate(); mouseWatch = nil; out = 0
    }

    func watchMouse() {
        guard !handing, let screen else { return }
        let mouse = NSEvent.mouseLocation
        if !mouseMoved, hypot(mouse.x - mouseAtArrival.x, mouse.y - mouseAtArrival.y) > 4 { mouseMoved = true }
        if !arrowsToWindow || !overMiddle() { refreshMiddle() }
        let m = NSEvent.mouseLocation, sf = screen.frame
        // A peek that is out keeps its zone a little wider, so it does not flicker at the border.
        func zone(_ side: Int) -> CGFloat { out == side ? max(near, outEdge + 24) : near }
        func level(_ side: Int) -> Bool { peeks[side].map { $0.pic.visual.insetBy(dx: 0, dy: -40).contains(NSPoint(x: $0.pic.visual.midX, y: m.y)) } ?? false }
        let side = !sf.contains(m) ? 0
            : m.x < sf.minX + zone(-1) && level(-1) ? -1
            : m.x > sf.maxX - zone(1) && level(1) ? 1 : 0
        guard side != out else { return }
        for (s, p) in peeks where s == out || s == side {
            let o = s == side
            move(p.pic, to: spot(p.shot, s, out: o, id: p.id), alpha: o ? outAlpha : peekAlpha, duration: outTime)
        }
        out = side
    }
}

// The plain left and right arrows step the row while the mouse is on the dark or on a peek; over the
// window in the middle they belong to that window, which is often a terminal that needs them
// (Manuel, 2026-10-01: "the mouse decides"). Control-Option-Left and -Right step wherever the mouse is.
extension Focus {
    func listenKeys() {
        guard keyTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, me in
            let focus = Unmanaged<Focus>.fromOpaque(me!).takeUnretainedValue()
            return focus.key(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { note.log("no key tap"); return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        keyTap = tap; keySource = source
        note.log("key tap on")
    }

    func unlistenKeys() {
        if let keySource { CFRunLoopRemoveSource(CFRunLoopGetMain(), keySource, .commonModes) }
        if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: false) }
        keyTap = nil; keySource = nil; swallowed = []
    }

    // Runs on the main thread, as the tap's source lives in the main run loop.
    func key(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            note.log("key tap was switched off by macOS (\(type.rawValue)); on again")
            if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown, code != 123, code != 124, active, !handing, !arrowsToWindow {
            note.log("typing: the arrows go to the window")
            arrowsToWindow = true
        }
        guard code == 123 || code == 124 else { return Unmanaged.passUnretained(event) }
        // The key coming up after a press that was ours is ours too.
        if type == .keyUp { return swallowed.remove(code) != nil ? nil : Unmanaged.passUnretained(event) }
        let mods: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        note.log("arrow \(code) active=\(self.active) handing=\(self.handing) toWindow=\(self.arrowsToWindow)")
        let toWindow = arrowsToWindow || (mouseMoved && overMiddle())
        guard event.flags.intersection(mods).isEmpty, handing || (active && !toWindow) else { return Unmanaged.passUnretained(event) }
        swallowed.insert(code)
        let by = code == 123 ? -1 : 1
        DispatchQueue.main.async { self.step(by) }
        return nil
    }

    // The mouse over the window in the middle.
    func overMiddle() -> Bool {
        guard !handing else { return false }
        let m = NSEvent.mouseLocation, h = NSScreen.screens.first?.frame.height ?? 0
        return target.contains(CGPoint(x: m.x, y: h - m.y))
    }
}

// A panel that never wakes Grid: a click on it leaves the window in front where it is.
class QuietPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// A picture's panel: it keeps one size, the picture moves and scales inside it (peekWindow()).
final class CardPanel: QuietPanel {
    var base = CGSize.zero
    // Where the picture shows, in screen coordinates.
    var visual = NSRect.zero
    var motion: Ticker?
    var blend: Ticker?
}

final class Tap: NSView {
    var onClick: (() -> Void)?
    // Only the picture takes clicks, not the clear rest of its panel.
    weak var card: NSView?
    // Every picture in the panel (two while one blends into the other) and the first one's shadow.
    var cards: [NSView] = []
    var edges = NSEdgeInsets()
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let card else { return frame.contains(point) ? self : nil }
        return card.frame.contains(convert(point, from: superview)) ? self : nil
    }
}
