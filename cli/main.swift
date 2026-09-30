// grid: arrange the windows on the screen of the front window in rows.
// Usage: grid               automatic: the layout follows the number of windows
//        grid 5 5           two rows, five windows each
//        grid 3 2           three on top, two below
//        grid 5 5 --gap 16  a different space (default: the menu bar app's)
import AppKit

var rows: [Int] = []
// Same space as the menu bar app unless --gap is given.
var gap = CGFloat(UserDefaults(suiteName: "dev.manuel.grid")?.object(forKey: "gap") as? Double ?? 8)
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    if a == "--gap", let v = args.first, let g = Double(v) { gap = CGFloat(g); args.removeFirst() }
    else if let n = Int(a), n > 0 { rows.append(n) }
    else { print("Usage: grid [5 5] [--gap 8]   (each number = windows in that row; none = automatic)"); exit(1) }
}
if !AXIsProcessTrusted() {
    print("Allow this app in System Settings > Privacy & Security > Accessibility, then run again.")
}
let result = arrange(rows, gap: gap)
// Let the glide finish before the command ends.
RunLoop.current.run(until: Date().addingTimeInterval(glideTime + 0.1))
print("Placed \(result.placed) of \(result.found) windows.")
