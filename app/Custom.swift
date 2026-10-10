// The Custom dialog: a diagram of up to four rows, and next to each row the number of windows in it.
import AppKit

// A text field that tells when the cursor enters or leaves it.
final class WellField: NSTextField {
    var focus: (Bool) -> Void = { _ in }
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { focus(true) }
        return ok
    }
    override func textDidEndEditing(_ n: Notification) { super.textDidEndEditing(n); focus(false) }
}

// One number with minus and plus beside it. The well is a plain neutral grey, whatever lies behind the
// dialog, and wears a ring while it is typed in.
final class NumberWell: NSView, NSTextFieldDelegate {
    let field = WellField(), stepper = NSStepper()
    var changed: () -> Void = {}
    var focused = false { didSet { needsDisplay = true } }
    var value: Int {
        get { min(16, Int(field.stringValue) ?? 0) }
        set { field.stringValue = newValue > 0 ? String(newValue) : ""; stepper.integerValue = newValue }
    }

    init(origin: NSPoint, value: Int) {
        super.init(frame: NSRect(x: origin.x, y: origin.y, width: 63, height: 24))
        field.frame = NSRect(x: 4, y: 3, width: 36, height: 17)
        field.isBezeled = false; field.drawsBackground = false; field.focusRingType = .none
        field.alignment = .center; field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.placeholderString = "0"
        field.delegate = self
        field.focus = { [weak self] in self?.focused = $0 }
        stepper.controlSize = .small
        stepper.minValue = 0; stepper.maxValue = 16; stepper.valueWraps = false
        stepper.target = self; stepper.action = #selector(stepped)
        stepper.sizeToFit()
        stepper.setFrameOrigin(NSPoint(x: 48, y: (24 - stepper.frame.height) / 2))
        addSubview(field); addSubview(stepper)
        self.value = value
    }
    required init?(coder: NSCoder) { nil }

    @objc func stepped() { value = stepper.integerValue; changed() }

    // Only digits, and no more than the diagram can hold.
    func controlTextDidChange(_ n: Notification) {
        let digits = field.stringValue.filter(\.isNumber)
        field.stringValue = digits.isEmpty ? "" : String(min(16, Int(digits) ?? 0))
        stepper.integerValue = value
        changed()
    }

    override func draw(_ r: NSRect) {
        let well = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 42, height: 22), xRadius: 6, yRadius: 6)
        NSColor.labelColor.withAlphaComponent(0.1).setFill(); well.fill()
        if focused { NSColor.controlAccentColor.setStroke(); well.lineWidth = 2; well.stroke() }
    }
}

// A screen-shaped diagram. The rows that hold windows fill the box, top to bottom; the room for
// more rows is only hinted at, faint and behind, never shaped like a tile.
final class RowsDiagram: NSView {
    var rows: [Int] = [] { didSet { needsDisplay = true } }
    var frame_: Frame = .full { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ r: NSRect) {
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).addClip()
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        bounds.fill()
        let cut: CGFloat = 2
        let filled = rows.filter { $0 > 0 }
        // Hints for the rows still free, at the pitch of the number wells beside the diagram.
        let pitch = bounds.height / 4
        NSColor.labelColor.withAlphaComponent(0.04).setFill()
        for i in filled.count..<4 {
            NSRect(x: 0, y: CGFloat(i) * pitch + cut / 2, width: bounds.width, height: pitch - cut).fill()
        }
        guard !filled.isEmpty else { return }
        let box = frame_.box(in: bounds)
        let rowH = ((box.height - cut * CGFloat(filled.count - 1)) / CGFloat(filled.count)).rounded(.down)
        NSColor.labelColor.withAlphaComponent(0.9).setFill()
        for (i, count) in filled.enumerated() {
            let y = box.minY + CGFloat(i) * (rowH + cut)
            let room = Int(box.width) - Int(cut) * (count - 1)
            var x = Int(box.minX)
            for c in 0..<count {
                let w = room / count + (c < room % count ? 1 : 0)
                NSBezierPath(roundedRect: NSRect(x: CGFloat(x), y: y, width: CGFloat(w), height: rowH), xRadius: 1, yRadius: 1).fill()
                x += w + Int(cut)
            }
        }
    }
}

// Diagram on the left, one number per row on the right; under them Width and Height of the box the
// rows fill, each Full, three quarters or half the screen.
final class RowsInput: NSView {
    static let diagramW: CGFloat = 160, diagramH: CGFloat = 100, top: CGFloat = 72
    let diagram = RowsDiagram(frame: NSRect(x: 16, y: top, width: diagramW, height: diagramH))
    var wells: [NumberWell] = []
    let widthSeg = NSSegmentedControl(), heightSeg = NSSegmentedControl()
    static let shares: [(String, Double)] = [("Full", 1), ("¾", 0.75), ("½", 0.5)]
    var changed: () -> Void = {}
    // The rows that hold windows, top to bottom.
    var rows: [Int] { wells.map(\.value).filter { $0 > 0 } }
    var box: Frame { Frame(width: Self.shares[widthSeg.selectedSegment].1, height: Self.shares[heightSeg.selectedSegment].1) }

    init(rows: [Int], frame: Frame) {
        super.init(frame: NSRect(x: 0, y: 0, width: 256, height: Self.top + Self.diagramH))
        addSubview(diagram)
        for (seg, share, word, y) in [(widthSeg, frame.width, "Width", 34), (heightSeg, frame.height, "Height", 4)] {
            let label = NSTextField(labelWithString: word)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize); label.alignment = .right
            label.frame = NSRect(x: 0, y: CGFloat(y) + 4, width: 60, height: 16)
            addSubview(label)
            seg.segmentCount = Self.shares.count
            for (i, (name, _)) in Self.shares.enumerated() { seg.setLabel(name, forSegment: i); seg.setWidth(50, forSegment: i) }
            seg.controlSize = .small; seg.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            seg.selectedSegment = Self.shares.firstIndex { abs($0.1 - share) < 0.01 } ?? 0
            seg.target = self; seg.action = #selector(update)
            seg.sizeToFit()
            seg.setFrameOrigin(NSPoint(x: 68, y: CGFloat(y)))
            addSubview(seg)
        }
        let pitch = Self.diagramH / 4
        for i in 0..<4 {
            // AppKit counts from the bottom: the first row is the highest.
            let well = NumberWell(origin: NSPoint(x: 190, y: Self.top + Self.diagramH - pitch * CGFloat(i + 1) + (pitch - 24) / 2), value: i < rows.count ? min(16, rows[i]) : 0)
            well.changed = { [weak self] in self?.update() }
            addSubview(well)
            wells.append(well)
        }
        for (a, b) in zip(wells, wells.dropFirst()) { a.field.nextKeyView = b.field }
        wells.last?.field.nextKeyView = wells.first?.field
        update()
    }
    required init?(coder: NSCoder) { nil }

    @objc func update() { diagram.rows = wells.map(\.value); diagram.frame_ = box; changed() }
}
