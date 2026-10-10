// Shared by the menu bar app and the grid command.
import AppKit
import ApplicationServices
import QuartzCore

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

// Tiles for rows of windows inside an area, the outer gap included. Every edge lies on a whole point,
// so neighbours meet exactly and no window sits on a half pixel.
func tiles(_ rows: [Int], in r: CGRect, gap: CGFloat) -> [CGRect] {
    // The edges of n parts between two bounds, with gaps around and between them.
    func edges(_ lo: CGFloat, _ hi: CGFloat, _ n: Int) -> [(CGFloat, CGFloat)] {
        let part = (hi - lo - gap * CGFloat(n + 1)) / CGFloat(n)
        return (0..<n).map { i in
            let a = (lo + gap + CGFloat(i) * (part + gap)).rounded(), b = (lo + gap + CGFloat(i) * (part + gap) + part).rounded()
            return (a, b)
        }
    }
    var out: [CGRect] = []
    for ((top, bottom), count) in zip(edges(r.minY, r.maxY, rows.count), rows) {
        for (left, right) in edges(r.minX, r.maxX, count) {
            out.append(CGRect(x: left, y: top, width: right - left, height: bottom - top))
        }
    }
    return out
}

typealias Result = (placed: Int, found: Int, before: [(AXUIElement, CGRect)])

func move(_ pairs: [(Win, CGRect)], found: Int) -> Result {
    let moves = pairs.compactMap { w, tile in axFrame(w.ax).map { (w.ax, $0, tile) } }
    glide(moves) { for (w, _, tile) in moves { settle(w, in: tile) } }
    return (moves.count, found, moves.map { ($0.0, $0.1) })
}

// A window that would not take its tile's size (a minimum size, a fixed shape) sits in the tile's
// top left corner at the size it took, and is kept on the screen.
func settle(_ w: AXUIElement, in tile: CGRect) {
    guard let f = axFrame(w), abs(f.width - tile.width) > 2 || abs(f.height - tile.height) > 2 else { return }
    var frame = CGRect(origin: tile.origin, size: f.size)
    if let screen = NSScreen.screens.first(where: { topLeft($0.frame).intersects(tile) }) {
        let vf = topLeft(screen.visibleFrame)
        frame.origin.x = max(vf.minX, min(frame.minX, vf.maxX - frame.width))
        frame.origin.y = max(vf.minY, min(frame.minY, vf.maxY - frame.height))
    }
    var pos = frame.origin
    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &pos)!)
}

func trusted() -> Bool {
    AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
}

// The box the rows fill: a share of the screen's width and height, in the middle of the screen.
// 1 × 1 is the whole screen; 1 × ½ a band across the middle; 0.7 × 0.7 a box for one window.
struct Frame: Equatable {
    var width: Double = 1, height: Double = 1
    static let full = Frame()
    static let middle = Frame(width: 0.7, height: 0.7)
    // The same width at half the height.
    var halved: Frame { Frame(width: width, height: 0.5) }
    func box(in r: CGRect) -> CGRect {
        let w = (r.width * width).rounded(), h = (r.height * height).rounded()
        return CGRect(x: (r.minX + (r.width - w) / 2).rounded(), y: (r.minY + (r.height - h) / 2).rounded(), width: w, height: h)
    }
}

// Empty rows = automatic: coding when a browser and a terminal or Claude window are both open (and the
// frame is the whole screen), else the layout follows the number of windows.
@discardableResult
func arrange(_ layout: [Int], gap: CGFloat, frame: Frame = .full) -> Result {
    guard trusted(), let screen = targetScreen() else { return (0, 0, []) }
    let windows = visibleWindows(on: screen)
    if layout.isEmpty, frame == .full, windows.contains(where: { browsers.contains($0.bundle) }), windows.contains(where: { codingApps.contains($0.bundle) }) {
        return arrangeCoding(gap: gap)
    }
    let rows = layout.isEmpty ? autoRows(windows.count) : layout
    guard !rows.isEmpty else { return (0, 0, []) }
    // Biggest tiles first, so the front window gets the best place; equal tiles keep reading order.
    let sorted = tiles(rows, in: frame.box(in: topLeft(screen.visibleFrame)), gap: gap).enumerated().sorted { a, b in
        a.element.area.rounded() != b.element.area.rounded() ? a.element.area > b.element.area : a.offset < b.offset
    }.map { $0.element }
    return move(Array(zip(windows, sorted)), found: windows.count)
}

let browsers: Set<String> = ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "org.mozilla.firefox", "com.microsoft.edgemac"]
let codingApps: Set<String> = ["com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.anthropic.claudefordesktop"]

// Coding: the front browser window on the left (60 %), terminal and Claude windows stacked on the right.
// Without a browser on the screen nothing happens.
@discardableResult
func arrangeCoding(gap: CGFloat) -> Result {
    guard trusted(), let screen = targetScreen() else { return (0, 0, []) }
    let windows = visibleWindows(on: screen)
    let browser = windows.first { browsers.contains($0.bundle) }
    let coding = windows.filter { codingApps.contains($0.bundle) }
    // Without a browser on this screen there is nothing to put on the left: a beep, not a surprise layout.
    guard browser != nil else { return (0, coding.count, []) }
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
    let rows = n == 0 ? [] : n <= 3 ? Array(repeating: 1, count: n) : (0..<(n + 1) / 2).map { $0 < n / 2 ? 2 : 1 }
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

// A clock that ticks with the screen, so every step of a motion lands on a frame of its own. A plain
// 60-a-second timer drifts against the screen and now and then shows two steps in one frame and none
// in the next: the motion stutters. The app turns the screen's clock on; the command keeps the timer.
var screenClock = false
final class Ticker: NSObject {
    private var link: CADisplayLink?
    private var timer: Timer?
    private let tick: (Ticker) -> Void
    var isValid: Bool { link != nil || timer != nil }
    init(_ tick: @escaping (Ticker) -> Void) {
        self.tick = tick
        super.init()
        if screenClock, let screen = NSScreen.main {
            let l = screen.displayLink(target: self, selector: #selector(step))
            l.add(to: .main, forMode: .common)
            link = l
        } else {
            // The timer holds the ticker until it is stopped, as the screen's clock does.
            let t = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in self.step() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }
    @objc private func step() { tick(self) }
    func invalidate() { link?.invalidate(); link = nil; timer?.invalidate(); timer = nil }
}

// Fast start, soft landing: the curve for arranging.
func easeOut(_ power: Double) -> (Double) -> Double { { t in 1 - pow(1 - t, power) } }
// A soft start that picks up speed at once and settles without a bump, like a spring with no bounce.
func spring(_ t: Double) -> Double {
    let k = 9.0
    return (1 - (1 + k * t) * exp(-k * t)) / (1 - (1 + k) * exp(-k))
}

// Moves windows to their new frames, then calls done.
let glideTime = 0.18
// A window is in one glide at a time: a new glide stops an older one that moves the same window.
// Different windows glide side by side, one going home while the next comes in.
var glides: [(timer: Ticker, windows: [AXUIElement])] = []
var gliding: Bool { glides.contains { $0.timer.isValid } }
func glide(_ moves: [(AXUIElement, from: CGRect, to: CGRect)], duration: Double = glideTime, power: Double = 5,
           soft: Bool = false, done: (() -> Void)? = nil) {
    glides.removeAll { g in
        let same = g.windows.contains { a in moves.contains { CFEqual($0.0, a) } }
        if same { g.timer.invalidate() }
        return same || !g.timer.isValid
    }
    let ease = soft ? spring : easeOut(power)
    var start: Date?
    let timer = Ticker { timer in
        // The clock starts with the first frame, so the first step is not already a jump.
        let s = start ?? Date(); start = s
        let t = min(1, Date().timeIntervalSince(s) / duration)
        let e = ease(t)
        for (w, a, b) in moves {
            // A window that only moves is never resized on the way: every resize makes the app lay
            // itself out again, and that costs frames.
            let moving = a.size == b.size
            if t >= 1 {
                if moving { var pos = b.origin; AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &pos)!) }
                else { place(w, b) }
                continue
            }
            var pos = CGPoint(x: a.minX + (b.minX - a.minX) * e, y: a.minY + (b.minY - a.minY) * e)
            AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &pos)!)
            if !moving {
                var size = CGSize(width: a.width + (b.width - a.width) * e, height: a.height + (b.height - a.height) * e)
                AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
            }
        }
        if t >= 1 { timer.invalidate(); done?() }
    }
    glides.append((timer, moves.map { $0.0 }))
}
