import AppKit

struct AppTarget: Identifiable {
    let id: String // bundle id
    let name: String
    let url: URL
    let icon: NSImage

    var icon16: NSImage {
        let small = icon.copy() as! NSImage
        small.size = NSSize(width: 16, height: 16)
        return small
    }
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

    /// Every app that can open https links, except Linkhop, sorted by name.
    static func installed() -> [AppTarget] {
        let me = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
            .compactMap(target(at:))
            .filter { $0.id != me && seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Apps offered in the picker: the config's `browsers` list, or every installed browser.
    static func pickerTargets(_ config: Config) -> [AppTarget] {
        if let ids = config.browsers, !ids.isEmpty {
            return ids.compactMap(target(for:))
        }
        return installed()
    }
}

enum DefaultBrowser {
    static var isLinkhop: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)?
            .standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// Asks macOS to make Linkhop the default browser; macOS shows its own confirmation dialog.
    static func request(then done: @escaping @MainActor () -> Void = {}) {
        let me = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "http") { error in
            Log.write("set default http: \(error?.localizedDescription ?? "ok")")
            NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "https") { error in
                Log.write("set default https: \(error?.localizedDescription ?? "ok")")
                Task { @MainActor in done() }
            }
        }
    }
}
