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

// Four rows, each split into its windows; a row without windows is only hinted at.
final class RowsDiagram: NSView {
    var rows: [Int] = [] { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ r: NSRect) {
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).addClip()
        let cut = 2
        for (i, count) in rows.enumerated() {
            let y = CGFloat(i * 30)
            guard count > 0 else {
                NSColor.labelColor.withAlphaComponent(0.1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: bounds.width, height: 28), xRadius: 1, yRadius: 1).fill()
                continue
            }
            NSColor.labelColor.withAlphaComponent(0.9).setFill()
            let room = Int(bounds.width) - cut * (count - 1)
            var x = 0
            for c in 0..<count {
                let w = room / count + (c < room % count ? 1 : 0)
                NSBezierPath(roundedRect: NSRect(x: CGFloat(x), y: y, width: CGFloat(w), height: 28), xRadius: 1, yRadius: 1).fill()
                x += w + cut
            }
        }
    }
}

// Diagram on the left, one number per row on the right.
final class RowsInput: NSView {
    let diagram = RowsDiagram(frame: NSRect(x: 16, y: 0, width: 120, height: 118))
    var wells: [NumberWell] = []
    var changed: () -> Void = {}
    // The rows that hold windows, top to bottom.
    var rows: [Int] { wells.map(\.value).filter { $0 > 0 } }

    init(rows: [Int]) {
        super.init(frame: NSRect(x: 0, y: 0, width: 228, height: 118))
        addSubview(diagram)
        for i in 0..<4 {
            // AppKit counts from the bottom: the first row is the highest.
            let well = NumberWell(origin: NSPoint(x: 150, y: CGFloat(118 - 28 - i * 30 + 2)), value: i < rows.count ? min(16, rows[i]) : 0)
            well.changed = { [weak self] in self?.update() }
            addSubview(well)
            wells.append(well)
        }
        for (a, b) in zip(wells, wells.dropFirst()) { a.field.nextKeyView = b.field }
        wells.last?.field.nextKeyView = wells.first?.field
        update()
    }
    required init?(coder: NSCoder) { nil }

    func update() { diagram.rows = wells.map(\.value); changed() }
}
