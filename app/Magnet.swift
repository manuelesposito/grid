// The magnet: after an arrangement, a window dropped on another window's tile swaps places with it.
// Only a drop does anything: a window moved a little, or set down off the grid, stays where it was
// left. Resizing is not a drag. Windows that were not arranged are free until the next arrangement.
import AppKit

final class Magnet {
    private var slots: [(ax: AXUIElement, tile: CGRect)] = []
    private var monitor: Any?

    func set(_ after: [(AXUIElement, CGRect)]) {
        slots = after.map { (ax: $0.0, tile: $0.1) }
        guard slots.count > 1 else { clear(); return }
        if monitor == nil {
            // The window's new frame is read a moment after the mouse goes up, when the app has set it.
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self?.dropped() }
            }
        }
    }

    func clear() {
        slots = []
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func dropped() {
        guard slots.count > 1, !gliding else { return }
        let h = NSScreen.screens.first?.frame.height ?? 0
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: h - mouse.y)
        // The dragged window: under the mouse, away from its tile, still at its tile's size.
        guard let i = slots.indices.first(where: { i in
            guard let f = axFrame(slots[i].ax) else { return false }
            let t = slots[i].tile
            return f.contains(point) && abs(f.width - t.width) < 4 && abs(f.height - t.height) < 4
                && (abs(f.minX - t.minX) > 4 || abs(f.minY - t.minY) > 4)
        }), let f = axFrame(slots[i].ax) else { return }
        let centre = CGPoint(x: f.midX, y: f.midY)
        guard let j = slots.indices.first(where: { $0 != i && slots[$0].tile.contains(centre) }) else { return }
        var moves = [(slots[i].ax, from: f, to: slots[j].tile)]
        // The other window comes over into the freed tile; a closed one leaves the tile empty.
        if let g = axFrame(slots[j].ax) { moves.append((slots[j].ax, from: g, to: slots[i].tile)) }
        let t = slots[i].tile
        slots[i].tile = slots[j].tile
        slots[j].tile = t
        glide(moves) { for (w, _, tile) in moves { settle(w, in: tile) } }
    }
}
