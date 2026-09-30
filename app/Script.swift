import Foundation

// Runs AppleScript and returns its result, or nil on error.
@discardableResult
func script(_ source: String) -> NSAppleEventDescriptor? {
    var error: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
    return error == nil ? result : nil
}

// Quotes text for use inside AppleScript.
func quoted(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}
