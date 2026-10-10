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

// Four rows, each split into its windows; a row without windows is only hinted at. The rows fill
// the frame's share of the diagram, in its middle; the rest of the screen is a faint ground.
final class RowsDiagram: NSView {
    var rows: [Int] = [] { didSet { needsDisplay = true } }
    var frame_: Frame = .full { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ r: NSRect) {
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).addClip()
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        bounds.fill()
        let box = frame_.box(in: bounds)
        let cut = 2, rowH = Int(((box.height - CGFloat(cut) * 3) / 4).rounded(.down))
        for (i, count) in rows.enumerated() {
            let y = box.minY + CGFloat(i * (rowH + cut))
            guard count > 0 else {
                NSColor.labelColor.withAlphaComponent(0.1).setFill()
                NSBezierPath(roundedRect: NSRect(x: box.minX, y: y, width: box.width, height: CGFloat(rowH)), xRadius: 1, yRadius: 1).fill()
                continue
            }
            NSColor.labelColor.withAlphaComponent(0.9).setFill()
            let room = Int(box.width) - cut * (count - 1)
            var x = Int(box.minX)
            for c in 0..<count {
                let w = room / count + (c < room % count ? 1 : 0)
                NSBezierPath(roundedRect: NSRect(x: CGFloat(x), y: y, width: CGFloat(w), height: CGFloat(rowH)), xRadius: 1, yRadius: 1).fill()
                x += w + cut
            }
        }
    }
}

// Diagram on the left, one number per row on the right; under them the width and height of the
// box the rows fill, in quarters of the screen.
final class RowsInput: NSView {
    let diagram = RowsDiagram(frame: NSRect(x: 16, y: 36, width: 120, height: 118))
    var wells: [NumberWell] = []
    let widthPop = NSPopUpButton(frame: NSRect(x: 16, y: 0, width: 100, height: 24), pullsDown: false)
    let heightPop = NSPopUpButton(frame: NSRect(x: 128, y: 0, width: 100, height: 24), pullsDown: false)
    static let shares: [(String, Double)] = [("Full", 1), ("¾", 0.75), ("½", 0.5)]
    var changed: () -> Void = {}
    // The rows that hold windows, top to bottom.
    var rows: [Int] { wells.map(\.value).filter { $0 > 0 } }
    var box: Frame { Frame(width: Self.shares[widthPop.indexOfSelectedItem].1, height: Self.shares[heightPop.indexOfSelectedItem].1) }

    init(rows: [Int], frame: Frame) {
        super.init(frame: NSRect(x: 0, y: 0, width: 228, height: 154))
        addSubview(diagram)
        for (pop, share, word) in [(widthPop, frame.width, "wide"), (heightPop, frame.height, "high")] {
            pop.controlSize = .small; pop.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            for (name, _) in Self.shares { pop.addItem(withTitle: "\(name) \(word)") }
            pop.selectItem(at: Self.shares.firstIndex { abs($0.1 - share) < 0.01 } ?? 0)
            pop.target = self; pop.action = #selector(update)
            addSubview(pop)
        }
        for i in 0..<4 {
            // AppKit counts from the bottom: the first row is the highest.
            let well = NumberWell(origin: NSPoint(x: 150, y: CGFloat(36 + 118 - 28 - i * 30 + 2)), value: i < rows.count ? min(16, rows[i]) : 0)
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
