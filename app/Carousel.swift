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

struct Peek { let pic: NSWindow; let id: CGWindowID; let shot: Shot }

extension Focus {
    // How much of a neighbour shows at the edge, and how much smaller it is than in the middle.
    var edge: CGFloat { 56 }
    var peekScale: CGFloat { 0.92 }
    var peekAlpha: CGFloat { 0.5 }
    // A peek the mouse has come near: further out, brighter, a touch bigger, on a quicker spring.
    var outEdge: CGFloat { 150 }
    var outScale: CGFloat { 0.95 }
    var outAlpha: CGFloat { 0.8 }
    var outTime: Double { 0.25 }
    // How near the edge the mouse has to come.
    var near: CGFloat { 120 }
    var sideways: Bool { zoom <= 1 }

    // The windows on this screen in reading order of their home places, the one in the middle at its home.
    func ring(_ screen: NSScreen) -> [Win] {
        func home(_ w: Win) -> CGRect { w.id == windowID ? before : (axFrame(w.ax) ?? .zero) }
        return visibleWindows(on: screen).sorted { a, b in
            let fa = home(a), fb = home(b)
            return abs(fa.minY - fb.minY) > 40 ? fa.minY < fb.minY : fa.minX < fb.minX
        }
    }

    // Where a picture lies: 0 in the middle, 1 and -1 peeking at the right and left edge, 2 and -2 just past them.
    // Out = the mouse is near that peek.
    func spot(_ s: Shot, _ side: Int, out: Bool = false) -> CGRect {
        guard let screen else { return s.frame }
        let k = side == 0 ? 1 : out ? outScale : peekScale
        let show = out ? outEdge : edge
        let vf = topLeft(screen.visibleFrame).insetBy(dx: 16, dy: 16), sf = topLeft(screen.frame)
        let w = (s.frame.width * k).rounded(), h = (min(s.frame.height, vf.height) * k).rounded()
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

    // A picture that can be clicked: a click on a peek slides the row towards it.
    func peekWindow(_ s: Shot, side: Int) -> NSWindow {
        let p = QuietPanel(contentRect: toNS(spot(s, side)), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.hidesOnDeactivate = false
        p.animationBehavior = .none; p.alphaValue = 0
        p.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]
        let tap = Tap(frame: NSRect(origin: .zero, size: p.frame.size))
        let card = Card(s, titleBar: 32)
        card.frame = tap.bounds; card.autoresizingMask = [.width, .height]
        tap.addSubview(card)
        tap.onClick = { [weak self, weak p] in
            guard let self, let p, let side = self.peeks.first(where: { $0.value.pic === p })?.key else { return }
            self.step(side < 0 ? -1 : 1)
        }
        p.contentView = tap
        made.append(p); onCover?()
        return p
    }

    // A picture glides to a place and an alpha on the way home's clock and curve.
    func move(_ o: NSWindow, to r: CGRect, alpha: CGFloat, duration: Double? = nil, done: (() -> Void)? = nil) {
        let duration = duration ?? homeTime
        let from = o.frame, to = toNS(r), a0 = o.alphaValue
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var start: Date?
        _ = Ticker { t in
            let s = start ?? Date(); start = s
            let p = still ? 1 : min(1, Date().timeIntervalSince(s) / duration), e = spring(p)
            o.setFrame(NSRect(x: from.minX + (to.minX - from.minX) * e, y: from.minY + (to.minY - from.minY) * e,
                              width: from.width + (to.width - from.width) * e, height: from.height + (to.height - from.height) * e), display: true)
            o.alphaValue = a0 + (alpha - a0) * e
            if p >= 1 { t.invalidate(); done?() }
        }
    }

    // The neighbours come in from past the edges once the window has landed in the middle.
    func showPeeks() {
        guard active, sideways, !handing, let screen, let b = blur else { return }
        // The blur has just been put under the window in the middle; the peeks lie above it again.
        for p in peeks.values { p.pic.order(.above, relativeTo: b.windowNumber) }
        watch()
        let r = ring(screen), mine = windowID
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
        let p = peekWindow(s, side: side * 2)
        p.order(.above, relativeTo: b.windowNumber)
        peeks[side] = Peek(pic: p, id: id, shot: s)
        move(p, to: spot(s, side, out: out == side), alpha: out == side ? outAlpha : peekAlpha)
    }

    func clearPeeks() {
        for (_, p) in peeks { fade(p.pic, to: 0) { p.pic.orderOut(nil) } }
        peeks = [:]
    }

    // The row slides by one. False when it cannot, and the step goes the old way.
    func slideStep(_ by: Int) -> Bool {
        guard sideways, active, !handing, textStep == 0, let screen, let w = window, let b = blur else { return false }
        let r = ring(screen)
        guard r.count > 1, let i = r.firstIndex(where: { $0.id == windowID }) else { return false }
        let next = r[(i + by + r.count) % r.count]
        guard let incoming = peeks.values.first(where: { $0.id == next.id }), let nextHome = axFrame(next.ax) else { return false }
        note.log("slide \(by) from \(self.windowID) to \(next.id)")
        handing = true
        movingUntil = Date().addingTimeInterval(homeTime + 0.6)
        let covers = [b] + others, oldID = windowID, oldHome = before
        let after = r.count > 2 ? r[(i + 2 * by + 2 * r.count) % r.count] : nil
        // The picture of the window after next is taken meanwhile.
        out = 0
        let coming = after.map { a in Task { @MainActor in await self.shot(a.id, a.ax, remember: false) } }
        Task { @MainActor in
            guard let cur = await self.shot(oldID, w) else { self.handing = false; return }
            // Its picture covers the real window, which then goes home under the blur.
            let curPic = self.peekWindow(cur, side: 0)
            let sc = cur.scale
            curPic.setFrame(toNS(CGRect(x: cur.frame.minX - cur.box.minX / sc, y: cur.frame.minY - cur.box.minY / sc,
                                        width: CGFloat(cur.image.width) / sc, height: CGFloat(cur.image.height) / sc)), display: true)
            curPic.alphaValue = 1
            curPic.order(.above, relativeTo: Int(oldID))
            for c in covers.reversed() { c.order(.above, relativeTo: Int(oldID)) }
            curPic.order(.above, relativeTo: b.windowNumber)
            for p in self.peeks.values { p.pic.order(.above, relativeTo: b.windowNumber) }
            self.unwatch()
            self.window = nil; self.blur = nil; self.others = []
            place(w, oldHome)
            // The next one waits in the middle, under the blur, for its picture to land on it.
            let size = CGSize(width: nextHome.width, height: min(nextHome.height, topLeft(screen.visibleFrame).insetBy(dx: 16, dy: 16).height))
            let vf = topLeft(screen.visibleFrame).insetBy(dx: 16, dy: 16)
            place(next.ax, self.centred(size, on: CGPoint(x: vf.midX, y: vf.midY)))

            var row: [Int: Peek] = [:]
            // The peek on the far side leaves past the edge; the window in the middle takes its place.
            if let gone = self.peeks[-by], gone.id != next.id {
                self.move(gone.pic, to: self.spot(gone.shot, -2 * by), alpha: 0) { gone.pic.orderOut(nil) }
            }
            if let left = self.peeks[by], left.id != next.id {
                self.move(left.pic, to: self.spot(left.shot, 2 * by), alpha: 0) { left.pic.orderOut(nil) }
            }
            row[-by] = Peek(pic: curPic, id: oldID, shot: cur)
            self.move(curPic, to: self.spot(cur, -by), alpha: self.peekAlpha)
            self.peeks = row
            self.move(incoming.pic, to: self.spot(incoming.shot, 0), alpha: 1) {
                self.arrive(next, home: nextHome, covers: covers, picture: incoming.pic)
            }
            if let coming, let a = after, a.id != oldID, let s = await coming.value, self.peeks[by]?.id != a.id {
                let p = self.peekWindow(s, side: 2 * by)
                p.order(.above, relativeTo: b.windowNumber)
                self.peeks[by] = Peek(pic: p, id: a.id, shot: s)
                self.move(p, to: self.spot(s, by), alpha: self.peekAlpha)
                }
        }
        return true
    }

    // The picture has landed: the real window comes up in its place and Focus goes on with it.
    func arrive(_ next: Win, home: CGRect, covers: [NSWindow], picture: NSWindow) {
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
            if !start(reusing: covers, home: home) {
                for c in covers { fade(c, to: 0) { c.orderOut(nil) } }
                clearPeeks(); unwatchMouse()
            }
            // One frame for the real window to be drawn over its picture.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { picture.orderOut(nil) }
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
        let m = NSEvent.mouseLocation, sf = screen.frame
        // A peek that is out keeps its zone a little wider, so it does not flicker at the border.
        func zone(_ side: Int) -> CGFloat { out == side ? max(near, outEdge + 24) : near }
        func level(_ side: Int) -> Bool { peeks[side].map { $0.pic.frame.insetBy(dx: 0, dy: -40).contains(NSPoint(x: $0.pic.frame.midX, y: m.y)) } ?? false }
        let side = !sf.contains(m) ? 0
            : m.x < sf.minX + zone(-1) && level(-1) ? -1
            : m.x > sf.maxX - zone(1) && level(1) ? 1 : 0
        guard side != out else { return }
        for (s, p) in peeks where s == out || s == side {
            let o = s == side
            move(p.pic, to: spot(p.shot, s, out: o), alpha: o ? outAlpha : peekAlpha, duration: outTime)
        }
        out = side
    }
}

// A panel that never wakes Grid: a click on it leaves the window in front where it is.
final class QuietPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class Tap: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
}
