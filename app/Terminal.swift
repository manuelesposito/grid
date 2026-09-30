// Rows and columns of Ghostty's terminals, read from their ttys. Focus uses them to make a zoomed
// window hold exactly the same lines as before: text sizes don't scale the character cells exactly.
import AppKit

struct Cells: Equatable { let rows: Int, cols: Int }

// Every tty of Ghostty's terminals with its current size.
func ghosttyCells() -> [String: Cells] {
    guard let pid = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == ghostty })?.processIdentifier else { return [:] }
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-Ao", "ppid=,tty="]; p.standardOutput = pipe
    guard (try? p.run()) != nil else { return [:] }
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    var result: [String: Cells] = [:]
    for line in out.split(separator: "\n") {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2, Int32(parts[0]) == pid, parts[1] != "??" else { continue }
        let path = "/dev/" + parts[1]
        let fd = open(path, O_RDONLY | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { continue }
        var ws = winsize()
        if ioctl(fd, TIOCGWINSZ, &ws) == 0 { result[path] = Cells(rows: Int(ws.ws_row), cols: Int(ws.ws_col)) }
        close(fd)
    }
    return result
}

func pause(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

// After the text size changed, nudges the window until its terminal has its old columns again (and rows,
// unless the height was cut to fit the screen). Returns the final frame.
func matchCells(_ w: AXUIElement, frame: CGRect, before: [String: Cells], keepRows: Bool, centre: CGPoint) -> CGRect {
    var frame = frame
    var tty: String?
    var same = 0
    for _ in 0..<6 {
        pause(0.03)
        let now = ghosttyCells()
        if tty == nil { tty = now.first { before[$0.key] != nil && before[$0.key] != $0.value }?.key }
        // No terminal differs from before: this one holds its old lines already. Seen twice, so a change
        // still on its way is not missed.
        if tty == nil { same += 1; if same == 2 { break } }
        // The wanted size is the one this terminal had before.
        guard let tty, let cells = now[tty], let want = before[tty] else { continue }
        let dc = want.cols - cells.cols, dr = keepRows ? want.rows - cells.rows : 0
        if dc == 0 && dr == 0 { break }
        // One cell is roughly the text area divided by its cells.
        let cw = (frame.width - 24) / CGFloat(cells.cols), ch = (frame.height - 56) / CGFloat(cells.rows)
        let size = CGSize(width: (frame.width + CGFloat(dc) * cw).rounded(), height: (frame.height + CGFloat(dr) * ch).rounded())
        frame = CGRect(x: (centre.x - size.width / 2).rounded(), y: (centre.y - size.height / 2).rounded(), width: size.width, height: size.height)
        place(w, frame)
    }
    return frame
}
