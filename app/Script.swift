import Foundation

// Runs AppleScript and returns its result, or nil on error.
@discardableResult
func script(_ source: String) -> NSAppleEventDescriptor? {
    var error: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
    return error == nil ? result : nil
}

// The same through osascript, without holding the main thread: for the moments when something is fading.
// Returns what the script answered, as text.
@discardableResult
func scriptAside(_ source: String) async -> String {
    await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", source]
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        p.terminationHandler = { _ in
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            c.resume(returning: out.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if (try? p.run()) == nil { c.resume(returning: "") }
    }
}

// Quotes text for use inside AppleScript.
func quoted(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}
