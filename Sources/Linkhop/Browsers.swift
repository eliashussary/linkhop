import AppKit

struct AppTarget: Identifiable {
    let id: String // bundle id
    let name: String
    let url: URL
    let icon: NSImage
}

enum Browsers {
    static func target(for bundleID: String) -> AppTarget? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return target(at: url)
    }

    static func target(at url: URL) -> AppTarget? {
        guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return AppTarget(id: id, name: name, url: url, icon: NSWorkspace.shared.icon(forFile: url.path))
    }

    /// Apps offered in the picker: the config's `browsers` list, or every app that handles https.
    static func pickerTargets(_ config: Config) -> [AppTarget] {
        if let ids = config.browsers, !ids.isEmpty {
            return ids.compactMap(target(for:))
        }
        let me = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
            .compactMap(target(at:))
            .filter { $0.id != me && seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
