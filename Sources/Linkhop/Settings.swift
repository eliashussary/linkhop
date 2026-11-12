import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: Model

@MainActor
final class SettingsModel: ObservableObject {
    @Published var config = Config()
    @Published var loadError: String?
    @Published var isDefault = false
    @Published var installed: [AppTarget] = []
    @Published var running: [AppTarget] = []
    @Published var ruleSelection: Int?
    @Published var editor: RuleEditorModel?
    private var targetCache: [String: AppTarget?] = [:]

    func reload() {
        installed = Browsers.installed()
        let me = Bundle.main.bundleIdentifier
        running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != me }
            .compactMap { $0.bundleURL.flatMap(Browsers.target(at:)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        isDefault = DefaultBrowser.isLinkhop
        do {
            config = try ConfigStore.loadStrict()
            loadError = nil
        } catch {
            loadError = Self.describe(error)
        }
    }

    /// Re-reads the file before applying a change, so edits made elsewhere (⌘-pick, a text editor) survive.
    func update(_ change: (inout Config) -> Void) {
        do {
            var fresh = try ConfigStore.loadStrict()
            change(&fresh)
            ConfigStore.save(fresh)
            config = fresh
            loadError = nil
        } catch {
            loadError = Self.describe(error)
        }
    }

    func target(_ id: String) -> AppTarget? {
        if let hit = installed.first(where: { $0.id == id }) { return hit }
        if let cached = targetCache[id] { return cached }
        let found = Browsers.target(for: id)
        targetCache[id] = found
        return found
    }

    // Browsers tab

    struct BrowserRow: Identifiable {
        let target: AppTarget
        let enabled: Bool
        var id: String { target.id }
    }

    var browserRows: [BrowserRow] {
        let on = config.browsers.flatMap { $0.isEmpty ? nil : $0 } ?? installed.map(\.id)
        return on.compactMap(target).map { BrowserRow(target: $0, enabled: true) }
            + installed.filter { !on.contains($0.id) }.map { BrowserRow(target: $0, enabled: false) }
    }

    func setBrowser(_ id: String, enabled: Bool) {
        let rows = browserRows
        var on = Set(rows.filter(\.enabled).map(\.id))
        if enabled { on.insert(id) } else if on.count > 1 { on.remove(id) } else { return }
        update { $0.browsers = rows.map(\.id).filter(on.contains) }
    }

    func moveBrowsers(from source: IndexSet, to destination: Int) {
        var rows = browserRows
        rows.move(fromOffsets: source, toOffset: destination)
        update { $0.browsers = rows.filter(\.enabled).map(\.id) }
    }

    // Rules tab

    func editRule(_ i: Int?) {
        let rules = config.rules ?? []
        if let i {
            guard rules.indices.contains(i) else { return }
            editor = RuleEditorModel(index: i, draft: RuleDraft(rules[i]))
        } else {
            editor = RuleEditorModel(index: nil, draft: RuleDraft())
        }
    }

    func saveEditor() {
        guard let editor else { return }
        let rule = editor.draft.rule
        update { config in
            var rules = config.rules ?? []
            if let i = editor.index, rules.indices.contains(i) { rules[i] = rule } else { rules.append(rule) }
            config.rules = rules
        }
        self.editor = nil
    }

    func deleteRule(_ i: Int) {
        update { config in
            if config.rules?.indices.contains(i) == true { config.rules?.remove(at: i) }
        }
        ruleSelection = nil
    }

    func moveRules(from source: IndexSet, to destination: Int) {
        update { $0.rules?.move(fromOffsets: source, toOffset: destination) }
        ruleSelection = nil
    }

    private static func describe(_ error: Error) -> String {
        if case let DecodingError.dataCorrupted(ctx) = error,
           let detail = (ctx.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String {
            return detail
        }
        if let decoding = error as? DecodingError { return String(describing: decoding) }
        return error.localizedDescription
    }
}

// MARK: Window

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private let model = SettingsModel()
    private var window: NSWindow?

    func show() {
        model.reload()
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "Linkhop Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        // Show in the Dock and ⌘-Tab while the window is open.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        // The policy change settles asynchronously; activating in the same turn is often ignored.
        DispatchQueue.main.async { [weak self] in
            NSApp.activate()
            self?.window?.makeKeyAndOrderFront(nil)
            self?.window?.orderFrontRegardless()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.reload()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: Views

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.loadError {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("config.json has an error, so editing is paused.").fontWeight(.medium)
                        Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Button("Open File") { openConfigFile() }
                    Button("Retry") { model.reload() }
                }
                .padding(12)
                .background(.yellow.opacity(0.12))
            }
            TabView {
                GeneralTab(model: model).tabItem { Label("General", systemImage: "gearshape") }
                BrowsersTab(model: model).tabItem { Label("Browsers", systemImage: "square.grid.2x2") }
                RulesTab(model: model).tabItem { Label("Rules", systemImage: "arrow.triangle.branch") }
            }
            .padding(16)
            .disabled(model.loadError != nil)
        }
        .frame(width: 580, height: 460)
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Default browser") { defaultBrowserStatus }
                fallbackPicker
            }
            Section("Picker shortcuts") {
                LabeledContent("1–9, ↩, click", value: "Open in that app")
                LabeledContent("⌘ + pick", value: "Always use that app for the site")
                LabeledContent("⌥ + click a link", value: "Always show the picker")
            }
            Section("Files") {
                LabeledContent("Rules") {
                    Button("Open config.json") { openConfigFile() }
                }
                LabeledContent("Activity") {
                    Button("Show Log") { NSWorkspace.shared.open(Log.url) }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var defaultBrowserStatus: some View {
        if model.isDefault {
            Label("Linkhop", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Button("Make Linkhop Default") {
                let model = model
                DefaultBrowser.request { model.reload() }
            }
        }
    }

    private var fallbackPicker: some View {
        Picker("When no rule matches", selection: fallback) {
            Text("Show the picker").tag("")
            Divider()
            ForEach(fallbackOptions) { t in
                Label { Text(t.name) } icon: { Image(nsImage: t.icon16) }.tag(t.id)
            }
        }
    }

    private var fallback: Binding<String> {
        Binding(get: { model.config.fallback ?? "" },
                set: { id in model.update { $0.fallback = id.isEmpty ? nil : id } })
    }

    private var fallbackOptions: [AppTarget] {
        let enabled = model.browserRows.filter(\.enabled).map(\.target)
        if let id = model.config.fallback, !enabled.contains(where: { $0.id == id }), let t = model.target(id) {
            return enabled + [t]
        }
        return enabled
    }
}

private struct BrowsersTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Checked apps appear in the picker. Drag to reorder; keys 1–9 follow this order.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List {
                ForEach(model.browserRows) { row in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(get: { row.enabled },
                                                 set: { model.setBrowser(row.id, enabled: $0) }))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        Image(nsImage: row.target.icon).resizable().frame(width: 20, height: 20)
                        Text(row.target.name)
                        Spacer()
                        Text(row.id).font(.caption).foregroundStyle(.tertiary)
                    }
                    .opacity(row.enabled ? 1 : 0.6)
                }
                .onMove { model.moveBrowsers(from: $0, to: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
        }
    }
}

private struct RulesTab: View {
    @ObservedObject var model: SettingsModel

    private var rules: [Rule] { model.config.rules ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The first matching rule wins. Links that match no rule go to the picker.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List(selection: $model.ruleSelection) {
                ForEach(Array(rules.enumerated()), id: \.offset) { i, rule in
                    RuleRow(rule: rule, model: model).tag(i)
                }
                .onMove { model.moveRules(from: $0, to: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: Int.self) { items in
                if let i = items.first {
                    Button("Edit…") { model.editRule(i) }
                    Button("Delete") { model.deleteRule(i) }
                }
            } primaryAction: { items in
                if let i = items.first { model.editRule(i) }
            }
            .overlay {
                if rules.isEmpty {
                    Text("No rules yet. Add one here, or hold ⌘ when picking a browser.")
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                Button { model.editRule(nil) } label: { Image(systemName: "plus") }
                Button { model.ruleSelection.map(model.deleteRule) } label: { Image(systemName: "minus") }
                    .disabled(model.ruleSelection == nil)
                Spacer()
                Button("Edit…") { model.editRule(model.ruleSelection) }
                    .disabled(model.ruleSelection == nil)
            }
        }
        .sheet(item: $model.editor) { editor in
            RuleEditor(model: model, editor: editor)
        }
    }
}

private struct RuleRow: View {
    let rule: Rule
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.host ?? "Any site").fontWeight(.medium)
                if !details.isEmpty {
                    Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            AppLabel(id: rule.open, model: model)
        }
        .padding(.vertical, 2)
    }

    private var details: String {
        [rule.from.map { "clicked in \(model.target($0)?.name ?? $0)" },
         rule.pattern.map { "URL matches \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

struct RuleDraft {
    var host = "", from = "", pattern = "", open = ""

    init() {}
    init(_ rule: Rule) {
        host = rule.host ?? ""
        from = rule.from ?? ""
        pattern = rule.pattern ?? ""
        open = rule.open
    }

    private static func clean(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    var rule: Rule {
        Rule(host: Self.clean(host), from: Self.clean(from), pattern: Self.clean(pattern), open: open)
    }

    var patternValid: Bool {
        Self.clean(pattern).map { (try? NSRegularExpression(pattern: $0)) != nil } ?? true
    }

    var canSave: Bool {
        !open.isEmpty && patternValid && (rule.host != nil || rule.from != nil || rule.pattern != nil)
    }
}

final class RuleEditorModel: ObservableObject, Identifiable {
    let id = UUID()
    let index: Int? // nil = new rule
    @Published var draft: RuleDraft

    init(index: Int?, draft: RuleDraft) {
        self.index = index
        self.draft = draft
    }
}

private struct RuleEditor: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var editor: RuleEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editor.index == nil ? "New Rule" : "Edit Rule").font(.headline)
            Form {
                TextField("Site", text: $editor.draft.host, prompt: Text("github.com or *.zoom.us"))
                LabeledContent("Clicked in") {
                    AppMenu(selection: $editor.draft.from, options: model.running, anyLabel: "Any app", model: model)
                }
                TextField("URL matches", text: $editor.draft.pattern, prompt: Text("optional regex, e.g. /j/\\d+"))
                    .foregroundStyle(editor.draft.patternValid ? Color.primary : Color.red)
                LabeledContent("Open with") {
                    AppMenu(selection: $editor.draft.open, options: model.installed, anyLabel: nil, model: model)
                }
            }
            Text("Fill in at least one of Site, Clicked in, or URL matches. Every field you fill in must match. A site also matches its subdomains.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { model.editor = nil }.keyboardShortcut(.cancelAction)
                Button("Save") { model.saveEditor() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!editor.draft.canSave)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private struct AppMenu: View {
    @Binding var selection: String
    let options: [AppTarget]
    let anyLabel: String?
    @ObservedObject var model: SettingsModel

    var body: some View {
        Menu {
            if let anyLabel {
                Button(anyLabel) { selection = "" }
                Divider()
            }
            ForEach(options) { t in
                Button { selection = t.id } label: {
                    Label { Text(t.name) } icon: { Image(nsImage: t.icon16) }
                }
            }
            Divider()
            Button("Other App…") { if let id = chooseApp() { selection = id } }
        } label: {
            if selection.isEmpty {
                Text(anyLabel ?? "Choose an app")
            } else {
                AppLabel(id: selection, model: model)
            }
        }
        .fixedSize()
    }

    private func chooseApp() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}

private struct AppLabel: View {
    let id: String
    @ObservedObject var model: SettingsModel

    var body: some View {
        let t = model.target(id)
        Label {
            Text(t?.name ?? id)
        } icon: {
            Image(nsImage: t?.icon16 ?? Self.missingIcon)
        }
    }

    private static let missingIcon: NSImage = {
        let i = NSWorkspace.shared.icon(for: .application)
        i.size = NSSize(width: 16, height: 16)
        return i
    }()
}

@MainActor
func openConfigFile() {
    ConfigStore.ensureExists()
    NSWorkspace.shared.open([ConfigStore.url],
                            withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                            configuration: NSWorkspace.OpenConfiguration())
}
