// snuggrid: arrange the windows on the screen of the front window in rows.
// Usage: snuggrid               automatic: the layout follows the number of windows
//        snuggrid 5 5           two rows, five windows each
//        snuggrid 3 2           three on top, two below
//        snuggrid 5 5 --gap 16  a different space (default: the menu bar app's)
//        snuggrid left           one big window on the left, two small ones stacked on the right (right: mirrored)
//        snuggrid 3 --height 50 three windows in a band across the middle, half the screen's height
//        snuggrid 1 --width 70 --height 70   one window in a box in the middle
import AppKit

var rows: [Int] = []
var frame = Frame()
// Same space as the menu bar app unless --gap is given.
var gap = CGFloat(UserDefaults(suiteName: "dev.manuel.snuggrid")?.object(forKey: "gap") as? Double ?? 8)
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    if a == "--gap", let v = args.first, let g = Double(v) { gap = CGFloat(g); args.removeFirst() }
    else if a == "--width", let v = args.first, let p = Double(v), p > 0, p <= 100 { frame.width = p / 100; args.removeFirst() }
    else if a == "--height", let v = args.first, let p = Double(v), p > 0, p <= 100 { frame.height = p / 100; args.removeFirst() }
    else if a == "left" { rows = bigLeft } else if a == "right" { rows = bigRight }
    else if let n = Int(a), n > 0 { rows.append(n) }
    else { print("Usage: snuggrid [5 5] [--gap 8] [--width 70] [--height 50]   (each number = windows in that row; left/right = one big window and two small; none = automatic; width and height in percent of the screen)"); exit(1) }
}
if !AXIsProcessTrusted() {
    print("Allow this app in System Settings > Privacy & Security > Accessibility, then run again.")
}
let result = arrange(rows, gap: gap, frame: frame)
// Let the glide finish before the command ends.
RunLoop.current.run(until: Date().addingTimeInterval(glideTime + 0.1))
print("Placed \(result.placed) of \(result.found) windows.")
