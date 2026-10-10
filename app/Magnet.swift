// The magnet: after an arrangement, a window dropped on another window's tile swaps places with it.
// Only a drop does anything: a window moved a little, or set down off the grid, stays where it was
// left. Resizing is not a drag. Windows that were not arranged are free until the next arrangement.
import AppKit

final class Magnet {
    // tile = the place given; size = the size the window really took (a window with a minimum size
    // may sit in its tile's corner, bigger than the tile), read once the glide has settled.
    private var slots: [(ax: AXUIElement, tile: CGRect, size: CGSize)] = []
    private var monitor: Any?

    func set(_ after: [(AXUIElement, CGRect)]) {
        slots = after.map { (ax: $0.0, tile: $0.1, size: $0.1.size) }
        guard slots.count > 1 else { clear(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + glideTime + 0.15) { [weak self] in
            guard let self else { return }
            for i in self.slots.indices { if let f = axFrame(self.slots[i].ax) { self.slots[i].size = f.size } }
        }
        if monitor == nil {
            // The window's new frame is read a moment after the mouse goes up, when the app has set it,
            // and once more a little later for an app that is slow to tell.
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self?.dropped() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.dropped() }
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
        // The dragged window: under the mouse, away from its tile, still at the size it had there.
        guard let i = slots.indices.first(where: { i in
            guard let f = axFrame(slots[i].ax) else { return false }
            let t = slots[i].tile, s = slots[i].size
            return f.contains(point) && abs(f.width - s.width) < 4 && abs(f.height - s.height) < 4
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
        glide(moves) { [weak self] in
            for (w, _, tile) in moves { settle(w, in: tile) }
            guard let self else { return }
            for k in [i, j] { if let f = axFrame(self.slots[k].ax) { self.slots[k].size = f.size } }
        }
    }
}
