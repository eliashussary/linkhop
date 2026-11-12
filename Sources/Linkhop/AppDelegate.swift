import AppKit

private struct Pending {
    let url: URL
    let source: String?
    let forcePicker: Bool
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let picker = Picker()
    private var queue: [Pending] = []
    private var picking = false
    private let defaultItem = NSMenuItem(title: "Make Default Browser", action: #selector(makeDefault), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        ConfigStore.ensureExists()
        setupStatusItem()
        if CommandLine.arguments.contains("--make-default") { makeDefault() }
    }

    // MARK: Links

    func application(_ application: NSApplication, open urls: [URL]) {
        let source = Self.sourceBundleID()
        let forcePicker = NSEvent.modifierFlags.contains(.option)
        queue += urls.map { Pending(url: $0, source: source, forcePicker: forcePicker) }
        drain()
    }

    private func drain() {
        while !picking, !queue.isEmpty {
            route(queue.removeFirst())
        }
    }

    private func route(_ p: Pending) {
        let config = ConfigStore.load()
        let from = p.source ?? "unknown"
        let host = p.url.host ?? p.url.scheme ?? "?"

        if !p.forcePicker {
            if let rule = config.rules?.first(where: { $0.matches(p.url, source: p.source) }),
               let target = Browsers.target(for: rule.open) {
                Log.write("\(from) → \(host) → \(target.id) (rule)")
                open(p.url, with: target)
                return
            }
            if let id = config.fallback, let target = Browsers.target(for: id) {
                Log.write("\(from) → \(host) → \(target.id) (fallback)")
                open(p.url, with: target)
                return
            }
        }

        let targets = Browsers.pickerTargets(config)
        guard !targets.isEmpty else {
            Log.write("\(from) → \(host): no browsers found")
            return
        }
        picking = true
        Log.write("\(from) → \(host): picker (\(targets.count) apps)")
        picker.show(url: p.url, targets: targets, onChoose: { [weak self] target, remember in
            Log.write("\(from) → \(host) → \(target.id) (picked\(remember ? ", saved" : ""))")
            if remember, let h = p.url.host { ConfigStore.remember(host: h, app: target.id) }
            self?.open(p.url, with: target)
        }, onDone: { [weak self] in
            self?.picking = false
            DispatchQueue.main.async { self?.drain() }
        })
    }

    private func open(_ url: URL, with target: AppTarget) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: target.url, configuration: config) { _, error in
            if let error { Log.write("open failed (\(target.id)): \(error.localizedDescription)") }
        }
    }

    /// Bundle id of the app that sent the open-URL Apple Event, i.e. where the link was clicked.
    private static func sourceBundleID() -> String? {
        let keySenderPID: AEKeyword = 0x7370_6964 // 'spid'
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let pid = event.attributeDescriptor(forKeyword: keySenderPID)?.int32Value,
              pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Linkhop")

        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "Linkhop", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        defaultItem.target = self
        menu.addItem(defaultItem)
        menu.addItem(withTitle: "Edit Rules…", action: #selector(editConfig), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Show Log", action: #selector(showLog), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Linkhop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let isDefault = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)?
            .standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
        defaultItem.state = isDefault ? .on : .off
        defaultItem.title = isDefault ? "Default Browser" : "Make Default Browser"
    }

    @objc private func makeDefault() {
        let me = Bundle.main.bundleURL
        // macOS shows its own confirmation dialog for this.
        NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "http") { error in
            Log.write("set default http: \(error?.localizedDescription ?? "ok")")
            NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "https") { error in
                Log.write("set default https: \(error?.localizedDescription ?? "ok")")
            }
        }
    }

    @objc private func editConfig() {
        ConfigStore.ensureExists()
        NSWorkspace.shared.open([ConfigStore.url],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func showLog() {
        NSWorkspace.shared.open(Log.url)
    }
}
