// New versions: once a day Grid asks GitHub for the number of the newest release. Nothing about you
// or your Mac is sent; the answer is a version number and the link to its download. When a newer
// one exists, the menu says so, and a click opens the download in the browser.
import AppKit

final class Update {
    static let latest = URL(string: "https://api.github.com/repos/manuelesposito/grid/releases/latest")!
    static let day: TimeInterval = 24 * 60 * 60
    // The newer version, once one is known.
    private(set) var newer: (version: String, download: URL)?
    var changed: () -> Void = {}
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "updates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "updates"); if newValue { check() } else { newer = nil; changed() } }
    }
    static let mine = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    func start() {
        // A moment after launch, then once an hour: the check itself asks only once a day.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.check() }
        Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in self.check() }
    }

    func check(force: Bool = false) {
        guard enabled else { return }
        let last = UserDefaults.standard.double(forKey: "updateChecked")
        guard force || Date().timeIntervalSince1970 - last > Self.day else { return }
        URLSession.shared.dataTask(with: Self.latest) { data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]],
                  let link = assets.compactMap({ $0["browser_download_url"] as? String }).first(where: { $0.hasSuffix(".zip") }),
                  let url = URL(string: link) else { return }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            DispatchQueue.main.async {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "updateChecked")
                let isNewer = version.compare(Self.mine, options: .numeric) == .orderedDescending
                self.newer = isNewer ? (version, url) : nil
                self.changed()
            }
        }.resume()
    }

    func download() {
        guard let newer else { return }
        NSWorkspace.shared.open(newer.download)
    }
}
