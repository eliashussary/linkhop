import AppKit
import SwiftUI

final class PickerModel: ObservableObject {
    let url: URL
    let targets: [AppTarget]
    @Published var selected = 0

    init(url: URL, targets: [AppTarget]) {
        self.url = url
        self.targets = targets
    }

    static let perRow = 9
}

struct PickerView: View {
    @ObservedObject var model: PickerModel
    let choose: (Int, Bool) -> Void

    private static let cell: CGFloat = 40
    private static let gap: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: Self.gap) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: Self.gap) {
                        ForEach(row, id: \.self) { i in cell(i) }
                    }
                }
            }

            HStack(spacing: 4) {
                Text(model.url.host ?? model.url.absoluteString)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("→").foregroundStyle(.tertiary)
                Text(model.targets[model.selected].name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .font(.caption)
            .padding(.horizontal, 4)
            .frame(width: footerWidth, alignment: .leading)
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var footerWidth: CGFloat {
        let cols = CGFloat(min(model.targets.count, PickerModel.perRow))
        return max(cols * Self.cell + (cols - 1) * Self.gap, 180)
    }

    private var rows: [[Int]] {
        stride(from: 0, to: model.targets.count, by: PickerModel.perRow).map {
            Array($0..<min($0 + PickerModel.perRow, model.targets.count))
        }
    }

    private func cell(_ i: Int) -> some View {
        let t = model.targets[i]
        return Button {
            choose(i, NSEvent.modifierFlags.contains(.command))
        } label: {
            Image(nsImage: t.icon)
                .resizable()
                .frame(width: 32, height: 32)
                .frame(width: Self.cell, height: Self.cell)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(i == model.selected ? Color.accentColor.opacity(0.28) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(i < 9 ? "\(i + 1)  \(t.name)" : t.name)
        .onHover { if $0 { model.selected = i } }
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A floating chooser shown at the mouse. Calls `onChoose` at most once, then `onDone` exactly once.
@MainActor
final class LinkPicker: NSObject, NSWindowDelegate {
    private var panel: KeyPanel?
    private var monitor: Any?
    private var model: PickerModel?
    private var onChoose: ((AppTarget, Bool) -> Void)?
    private var onDone: (() -> Void)?

    func show(url: URL, targets: [AppTarget],
              onChoose: @escaping (AppTarget, Bool) -> Void,
              onDone: @escaping () -> Void) {
        let model = PickerModel(url: url, targets: targets)
        self.model = model
        self.onChoose = onChoose
        self.onDone = onDone

        let host = NSHostingView(rootView: PickerView(model: model) { [weak self] i, remember in
            self?.finish(i, remember: remember)
        })
        let size = host.fittingSize
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.setFrameOrigin(Self.origin(for: size))
        self.panel = panel

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Centered horizontally on the cursor, with the icon row just under it.
    private static func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        var p = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height + 12)
        if let f = screen?.visibleFrame {
            p.x = min(max(p.x, f.minX + 8), f.maxX - size.width - 8)
            p.y = min(max(p.y, f.minY + 8), f.maxY - size.height - 8)
        }
        return p
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let model else { return false }
        let remember = event.modifierFlags.contains(.command)
        let count = model.targets.count
        switch event.keyCode {
        case 53: close() // esc
        case 36, 76: finish(model.selected, remember: remember) // return, enter
        case 123: model.selected = (model.selected - 1 + count) % count // ←
        case 124, 48: model.selected = (model.selected + 1) % count // →, tab
        case 126: model.selected = max(model.selected - PickerModel.perRow, 0) // ↑
        case 125: model.selected = min(model.selected + PickerModel.perRow, count - 1) // ↓
        default:
            guard let c = event.charactersIgnoringModifiers, let n = Int(c), (1...9).contains(n), n <= count else {
                return false
            }
            finish(n - 1, remember: remember)
        }
        return true
    }

    private func finish(_ index: Int, remember: Bool) {
        guard let model, model.targets.indices.contains(index) else { return }
        let choose = onChoose
        close()
        choose?(model.targets[index], remember)
    }

    func windowDidResignKey(_ notification: Notification) {
        Log.write("picker dismissed (lost focus)")
        close()
    }

    private func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        model = nil
        onChoose = nil
        let done = onDone
        onDone = nil
        done?()
    }
}
