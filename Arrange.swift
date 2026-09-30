// Shared by the menu bar app and the grid command.
import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ el: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

func axFrame(_ w: AXUIElement) -> CGRect? {
    var p: CFTypeRef?, s: CFTypeRef?
    var pos = CGPoint.zero, size = CGSize.zero
    guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p) == .success,
          AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s) == .success else { return nil }
    AXValueGetValue(p as! AXValue, .cgPoint, &pos)
    AXValueGetValue(s as! AXValue, .cgSize, &size)
    return CGRect(origin: pos, size: size)
}

// A screen's frame in top-left coordinates, the ones window positions use.
func topLeft(_ r: CGRect) -> CGRect {
    let h = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
}

// The screen holding the front window; else the one under the mouse.
func targetScreen() -> NSScreen? {
    if let app = NSWorkspace.shared.frontmostApplication {
        var value: CFTypeRef?
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        if AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let f = axFrame(value as! AXUIElement) {
            let best = NSScreen.screens.max { a, b in
                topLeft(a.frame).intersection(f).area < topLeft(b.frame).intersection(f).area
            }
            if let best, topLeft(best.frame).intersects(f) { return best }
        }
    }
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
}

// Real document windows only: no popups, panels or full screen windows.
func isNormal(_ w: AXUIElement) -> Bool {
    var sub: CFTypeRef?, full: CFTypeRef?
    AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &sub)
    AXUIElementCopyAttributeValue(w, "AXFullScreen" as CFString, &full)
    return (sub as? String) == kAXStandardWindowSubrole && (full as? Bool) != true
}

extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }

// Rows for a number of windows: one row up to 3, two rows up to 10, then rows of 5; fuller rows on top.
func autoRows(_ n: Int) -> [Int] {
    guard n > 0 else { return [] }
    let count = n <= 3 ? 1 : n <= 10 ? 2 : (n + 4) / 5
    return (0..<count).map { n / count + ($0 < n % count ? 1 : 0) }
}

struct Win { let ax: AXUIElement; let id: CGWindowID; let bundle: String }

// Visible normal windows on a screen, front to back.
func visibleWindows(on screen: NSScreen) -> [Win] {
    let area = topLeft(screen.frame)
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let me = ProcessInfo.processInfo.processIdentifier
    let order: [(CGWindowID, pid_t)] = info.compactMap {
        guard ($0[kCGWindowLayer as String] as? Int) == 0,
              let id = $0[kCGWindowNumber as String] as? CGWindowID,
              let pid = $0[kCGWindowOwnerPID as String] as? pid_t, pid != me,
              let b = $0[kCGWindowBounds as String] as? [String: CGFloat],
              let w = b["Width"], let h = b["Height"], w > 100, h > 100,
              area.contains(CGPoint(x: (b["X"] ?? 0) + w / 2, y: (b["Y"] ?? 0) + h / 2)) else { return nil }
        return (id, pid)
    }
    var byId: [CGWindowID: Win] = [:]
    for pid in Set(order.map { $0.1 }) {
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value)
        for w in (value as? [AXUIElement]) ?? [] {
            var id: CGWindowID = 0
            if isNormal(w), _AXUIElementGetWindow(w, &id) == .success { byId[id] = Win(ax: w, id: id, bundle: bundle) }
        }
    }
    return order.compactMap { byId[$0.0] }
}

// Tiles for rows of windows inside an area, the outer gap included.
func tiles(_ rows: [Int], in r: CGRect, gap: CGFloat) -> [CGRect] {
    let rowH = (r.height - gap * CGFloat(rows.count + 1)) / CGFloat(rows.count)
    var out: [CGRect] = []
    for (ri, count) in rows.enumerated() {
        let colW = (r.width - gap * CGFloat(count + 1)) / CGFloat(count)
        for c in 0..<count {
            out.append(CGRect(x: r.minX + gap + CGFloat(c) * (colW + gap), y: r.minY + gap + CGFloat(ri) * (rowH + gap), width: colW, height: rowH))
        }
    }
    return out
}

typealias Result = (placed: Int, found: Int, before: [(AXUIElement, CGRect)])

func move(_ pairs: [(Win, CGRect)], found: Int) -> Result {
    let moves = pairs.compactMap { w, tile in axFrame(w.ax).map { (w.ax, $0, tile) } }
    glide(moves)
    return (moves.count, found, moves.map { ($0.0, $0.1) })
}

func trusted() -> Bool {
    AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
}

// Empty rows = automatic: coding when a browser and a terminal or Claude window are both open,
// else the layout follows the number of windows.
@discardableResult
func arrange(_ layout: [Int], gap: CGFloat) -> Result {
    guard trusted(), let screen = targetScreen() else { return (0, 0, []) }
    let windows = visibleWindows(on: screen)
    if layout.isEmpty, windows.contains(where: { browsers.contains($0.bundle) }), windows.contains(where: { codingApps.contains($0.bundle) }) {
        return arrangeCoding(gap: gap)
    }
    let rows = layout.isEmpty ? autoRows(windows.count) : layout
    guard !rows.isEmpty else { return (0, 0, []) }
    // Biggest tiles first, so the front window gets the best place; equal tiles keep reading order.
    let sorted = tiles(rows, in: topLeft(screen.visibleFrame), gap: gap).enumerated().sorted { a, b in
        a.element.area.rounded() != b.element.area.rounded() ? a.element.area > b.element.area : a.offset < b.offset
    }.map { $0.element }
    return move(Array(zip(windows, sorted)), found: windows.count)
}

let browsers: Set<String> = ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "org.mozilla.firefox", "com.microsoft.edgemac"]
let codingApps: Set<String> = ["com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.anthropic.claudefordesktop"]

// Coding: the front browser window on the left (60 %), terminal and Claude windows stacked on the right.
@discardableResult
func arrangeCoding(gap: CGFloat) -> Result {
    guard trusted(), let screen = targetScreen() else { return (0, 0, []) }
    let windows = visibleWindows(on: screen)
    let browser = windows.first { browsers.contains($0.bundle) }
    let coding = windows.filter { codingApps.contains($0.bundle) }
    let vf = topLeft(screen.visibleFrame)
    var pairs: [(Win, CGRect)] = []
    var right = vf
    if let browser {
        if coding.isEmpty { return move([(browser, tiles([1], in: vf, gap: gap)[0])], found: 1) }
        // The browser keeps the outer gap on its left; the stack keeps it on its right.
        let split = (vf.width * 0.6).rounded()
        let left = CGRect(x: vf.minX, y: vf.minY, width: split + gap / 2, height: vf.height)
        pairs.append((browser, tiles([1], in: left, gap: gap)[0]))
        right = CGRect(x: vf.minX + split - gap / 2, y: vf.minY, width: vf.width - split + gap / 2, height: vf.height)
    }
    let n = coding.count
    guard n > 0 || !pairs.isEmpty else { return (0, 0, []) }
    // Up to 3 stacked, then two per row.
    let rows = n == 0 ? [] : browser == nil ? autoRows(n) : n <= 3 ? Array(repeating: 1, count: n) : (0..<(n + 1) / 2).map { $0 < n / 2 ? 2 : 1 }
    if !rows.isEmpty { pairs += zip(coding, tiles(rows, in: right, gap: gap)) }
    return move(pairs, found: pairs.count)
}

func place(_ w: AXUIElement, _ frame: CGRect) {
    var pos = frame.origin, size = frame.size
    // Size, move, size again: some apps clamp size to the old position.
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &pos)!)
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
}

// Moves windows to their new frames: fast start, soft landing, then calls done.
let glideTime = 0.18
func glide(_ moves: [(AXUIElement, from: CGRect, to: CGRect)], duration: Double = glideTime, power: Double = 5, done: (() -> Void)? = nil) {
    let start = Date()
    Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
        let t = min(1, Date().timeIntervalSince(start) / duration)
        let e = 1 - pow(1 - t, power)
        for (w, a, b) in moves {
            if t >= 1 { place(w, b); continue }
            var pos = CGPoint(x: a.minX + (b.minX - a.minX) * e, y: a.minY + (b.minY - a.minY) * e)
            var size = CGSize(width: a.width + (b.width - a.width) * e, height: a.height + (b.height - a.height) * e)
            AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &pos)!)
            AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
        }
        if t >= 1 { timer.invalidate(); done?() }
    }
}
