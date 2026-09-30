// Workspaces: save the windows on the screen under a name, and put them back later.
// Terminal windows remember their folder, browser windows their page; missing ones are reopened.
import AppKit

struct Item: Codable { let bundle: String; let frame: [Double]; var dir: String?; var url: String? }

let ghostty = "com.mitchellh.ghostty", chrome = "com.google.Chrome", safari = "com.apple.Safari"

final class Workspaces {
    var all: [String: [Item]] {
        get { (UserDefaults.standard.data(forKey: "workspaces")).flatMap { try? JSONDecoder().decode([String: [Item]].self, from: $0) } ?? [:] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "workspaces") }
    }
    var names: [String] { all.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }

    func save(_ name: String) -> Bool {
        guard trusted(), let screen = targetScreen() else { return false }
        let dirs = terminalDirs(), urls = browserURLs()
        let items: [Item] = visibleWindows(on: screen).reversed().compactMap { w in
            guard let f = axFrame(w.ax) else { return nil }
            var item = Item(bundle: w.bundle, frame: [f.minX, f.minY, f.width, f.height])
            if w.bundle == ghostty { item.dir = dirs[stripped(title(w.ax))] }
            if w.bundle == chrome || w.bundle == safari { item.url = urls.first { $0.bundle == w.bundle && $0.frame.equalTo(f.integral) }?.url }
            return item
        }
        guard !items.isEmpty else { return false }
        all[name] = items
        return true
    }

    func delete(_ name: String) { all[name] = nil }

    // Back to front, so the window that was in front ends up in front again.
    func open(_ name: String) -> Bool {
        guard trusted(), let items = all[name] else { return false }
        let dirs = terminalDirs(), urls = browserURLs()
        var used: Set<CGWindowID> = []
        for item in items {
            let target = CGRect(x: item.frame[0], y: item.frame[1], width: item.frame[2], height: item.frame[3])
            let existing = windows(of: item.bundle).filter { !used.contains($0.id) }
            // Reuse a matching window: same folder, same page, or any window of an app without either.
            var match = existing.first { w in
                if let dir = item.dir { return dirs[stripped(title(w.ax))] == dir }
                if let url = item.url, let f = axFrame(w.ax) { return urls.contains { $0.url == url && $0.frame.equalTo(f.integral) } }
                return true
            }
            if match == nil { match = reopen(item, besides: Set(existing.map { $0.id })) }
            guard let w = match else { continue }
            used.insert(w.id)
            if let now = axFrame(w.ax) { glide([(w.ax, now, target)]) } else { place(w.ax, target) }
            AXUIElementPerformAction(w.ax, kAXRaiseAction as CFString)
        }
        return !used.isEmpty
    }

    // Opens a new window for the item and waits up to two seconds for it to appear.
    func reopen(_ item: Item, besides old: Set<CGWindowID>) -> Win? {
        switch item.bundle {
        case ghostty:
            let dir = item.dir.map { " with configuration {initial working directory:\(quoted($0))}" } ?? ""
            script("tell application \"Ghostty\" to new window\(dir)")
        case chrome:
            script("tell application \"Google Chrome\"\nmake new window\n\(item.url.map { "set URL of active tab of front window to \(quoted($0))" } ?? "")\nend tell")
        case safari:
            script("tell application \"Safari\" to make new document\(item.url.map { " with properties {URL:\(quoted($0))}" } ?? "")")
        default:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundle) else { return nil }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
        for _ in 0..<20 {
            if let w = windows(of: item.bundle).first(where: { !old.contains($0.id) }) { return w }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return nil
    }

    func windows(of bundle: String) -> [Win] {
        NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundle }.flatMap { app -> [Win] in
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute as CFString, &value)
            return ((value as? [AXUIElement]) ?? []).compactMap { w in
                var id: CGWindowID = 0
                return isNormal(w) && _AXUIElementGetWindow(w, &id) == .success ? Win(ax: w, id: id, bundle: bundle) : nil
            }
        }
    }

    func title(_ w: AXUIElement) -> String {
        var t: CFTypeRef?
        AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
        return t as? String ?? ""
    }

    // Claude's working symbol at the start of a title changes all the time; compare without it.
    func stripped(_ title: String) -> String {
        guard let first = title.first, "◐◓◑◒✳".contains(first) else { return title }
        return String(title.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    // Window title → folder, for Ghostty.
    func terminalDirs() -> [String: String] {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == ghostty }),
              let r = script("tell application \"Ghostty\" to get {name, working directory of focused terminal of selected tab} of every window"),
              let names = r.atIndex(1), let dirs = r.atIndex(2) else { return [:] }
        var out: [String: String] = [:]
        for i in stride(from: 1, through: names.numberOfItems, by: 1) {
            if let n = names.atIndex(i)?.stringValue, let d = dirs.atIndex(i)?.stringValue { out[stripped(n)] = d }
        }
        return out
    }

    // Front page and frame of every Chrome and Safari window.
    func browserURLs() -> [(bundle: String, frame: CGRect, url: String)] {
        var out: [(String, CGRect, String)] = []
        for (bundle, app, tab) in [(chrome, "Google Chrome", "active tab"), (safari, "Safari", "current tab")]
        where NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundle }) {
            guard let r = script("tell application \"\(app)\" to get {bounds, URL of \(tab)} of every window"),
                  let bounds = r.atIndex(1), let links = r.atIndex(2) else { continue }
            for i in stride(from: 1, through: bounds.numberOfItems, by: 1) {
                guard let b = bounds.atIndex(i), b.numberOfItems == 4, let u = links.atIndex(i)?.stringValue else { continue }
                let v = (1...4).map { CGFloat(b.atIndex($0)?.int32Value ?? 0) }
                out.append((bundle, CGRect(x: v[0], y: v[1], width: v[2] - v[0], height: v[3] - v[1]), u))
            }
        }
        return out
    }
}
