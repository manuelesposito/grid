// Marks Claude windows that finished and wait for you, with a coloured edge.
// Claude Code puts ◐ ◓ ◑ ◒ in the window title while it works and ✳ when it is done.
import AppKit

// Until then Grid is animating and the waiting check holds off.
var quietUntil = Date.distantPast

final class Waiting {
    var busy: Set<CGWindowID> = []
    var waiting: Set<CGWindowID> = []
    var edges: [CGWindowID: NSWindow] = [:]
    var timer: Timer?

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "waiting") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "waiting"); newValue ? start() : stop() }
    }

    func start() {
        guard enabled, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        busy = []; waiting = []
        edges.values.forEach { $0.orderOut(nil) }; edges = [:]
    }

    func tick() {
        // Reading titles takes a moment on the main thread; not while a window is zooming.
        guard AXIsProcessTrusted(), Date() > quietUntil else { return }
        let focused = focusedWindow()
        var seen: [CGWindowID: AXUIElement] = [:]
        for app in NSWorkspace.shared.runningApplications where codingApps.contains(app.bundleIdentifier ?? "") {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute as CFString, &value)
            for w in (value as? [AXUIElement]) ?? [] {
                var id: CGWindowID = 0, t: CFTypeRef?
                guard _AXUIElementGetWindow(w, &id) == .success else { continue }
                AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
                let first = (t as? String)?.first
                seen[id] = w
                if let first, "◐◓◑◒".contains(first) { busy.insert(id); waiting.remove(id) }
                else if first == "✳", busy.remove(id) != nil, id != focused { waiting.insert(id) }
                if id == focused { waiting.remove(id) }
            }
        }
        // Edges only for windows on this desktop; closed windows drop out.
        for id in Array(edges.keys) where !waiting.contains(id) || seen[id] == nil {
            edges[id]?.orderOut(nil); edges[id] = nil
        }
        for id in waiting {
            guard let w = seen[id], let f = axFrame(w) else { continue }
            show(id, frame: f)
        }
    }

    // Bring the next waiting window to the front; the edge clears on the next tick.
    func jump() -> Bool {
        tick()
        for app in NSWorkspace.shared.runningApplications where codingApps.contains(app.bundleIdentifier ?? "") {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute as CFString, &value)
            for w in (value as? [AXUIElement]) ?? [] {
                var id: CGWindowID = 0
                guard _AXUIElementGetWindow(w, &id) == .success, waiting.contains(id) else { continue }
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                app.activate()
                return true
            }
        }
        return false
    }

    func focusedWindow() -> CGWindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute as CFString, &value)
        guard let value else { return nil }
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(value as! AXUIElement, &id) == .success ? id : nil
    }

    // A see-through window just above the waiting one, drawing only its edge.
    func show(_ id: CGWindowID, frame: CGRect) {
        let h = NSScreen.screens.first?.frame.height ?? 0
        let rect = NSRect(x: frame.minX, y: h - frame.maxY, width: frame.width, height: frame.height)
        let win = edges[id] ?? {
            let w = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
            w.ignoresMouseEvents = true
            w.contentView = Edge()
            edges[id] = w
            return w
        }()
        if win.frame != rect { win.setFrame(rect, display: true) }
        win.order(.above, relativeTo: Int(id))
    }
}

final class Edge: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 12, yRadius: 12)
        path.lineWidth = 3
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
