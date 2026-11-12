import AppKit

private struct Pending {
    let url: URL
    let source: String?
    let forcePicker: Bool
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let picker = LinkPicker()
    private var queue: [Pending] = []
    private var picking = false
    private let defaultItem = NSMenuItem(title: "Make Default Browser", action: #selector(makeDefault), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        ConfigStore.ensureExists()
        setupMainMenu()
        setupStatusItem()
        let args = CommandLine.arguments
        if args.contains("--make-default") { makeDefault() }
        // Opened from Finder/Launchpad/Spotlight (not to handle a link): show settings.
        let launchedByUser = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? false
        if launchedByUser && !args.contains("--background") && !args.contains("--make-default") {
            SettingsWindow.shared.show()
        }
    }

    /// Opening Linkhop again while it's running shows settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return false
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

    // MARK: Menus

    /// Needed for ⌘Q/⌘W/⌘, and copy/paste in text fields while the settings window is open.
    private func setupMainMenu() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About Linkhop", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Linkhop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Linkhop", action: nil, keyEquivalent: "").submenu = app

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window

        NSApp.mainMenu = main
    }

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
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Linkhop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let isDefault = DefaultBrowser.isLinkhop
        defaultItem.state = isDefault ? .on : .off
        defaultItem.title = isDefault ? "Default Browser" : "Make Default Browser"
    }

    @objc private func makeDefault() {
        DefaultBrowser.request()
    }

    @objc private func showSettings() {
        SettingsWindow.shared.show()
    }
}
