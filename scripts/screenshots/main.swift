// Renders the README images. The picker and settings tabs are the app's real SwiftUI views;
// the scenes around them (wallpaper, menu bar, chat app, window frames) are mock-ups.
// Run via `make screenshots`. Output: .github/assets/{hero,picker,settings}-{light,dark}.jpg
import AppKit
import SwiftUI

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".github/assets")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// MARK: - Offscreen rendering

/// Lays out `view` in an offscreen window with the given appearance and snapshots it at `scale`×.
@MainActor
func snapshot<V: View>(_ view: V, dark: Bool, scale: CGFloat = 2) -> NSImage {
    let host = NSHostingView(rootView: view)
    let size = host.fittingSize
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.contentView = host
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    host.layoutSubtreeIfNeeded()

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    window.orderOut(nil)
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    return image
}

/// A canvas in points with a top-left origin, rendered at 2×.
final class Canvas {
    let size: NSSize
    let rep: NSBitmapImageRep

    init(_ w: CGFloat, _ h: CGFloat) {
        size = NSSize(width: w, height: h)
        rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * 2), pixelsHigh: Int(h * 2), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
    }

    func draw(_ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Converts a top-left rect to AppKit's bottom-left coordinates.
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x, y: size.height - y - h, width: w, height: h)
    }

    func place(_ image: NSImage, x: CGFloat, y: CGFloat, width: CGFloat? = nil, shadow: CGFloat = 0, dark: Bool = false) {
        let w = width ?? image.size.width
        let h = image.size.height * w / image.size.width
        NSGraphicsContext.saveGraphicsState()
        if shadow > 0 {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.28)
            s.shadowBlurRadius = shadow
            s.shadowOffset = NSSize(width: 0, height: -shadow * 0.4)
            s.set()
        }
        image.draw(in: rect(x, y, w, h))
        NSGraphicsContext.restoreGraphicsState()
    }

    func save(_ name: String) {
        let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
        try! data.write(to: outDir.appending(path: "\(name).jpg"))
        print("wrote \(name).jpg (\(rep.pixelsWide)×\(rep.pixelsHigh), \(data.count / 1024) KB)")
    }
}

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

// MARK: - Scene pieces

func wallpaper(_ c: Canvas, dark: Bool) {
    let full = NSRect(origin: .zero, size: c.size)
    let base = dark ? [hex(0x0E0B26), hex(0x241B5C), hex(0x1A1438)] : [hex(0xE9EBFF), hex(0xF4EDFF), hex(0xFDEFF6)]
    NSGradient(colors: base)!.draw(in: full, angle: -35)
    let blobs: [(UInt32, CGFloat, CGFloat, CGFloat, CGFloat)] = dark
        ? [(0x6D5CFF, 0.55, 0.22, 0.30, 0.55), (0xFF5FA2, 0.30, 0.88, 0.85, 0.50), (0x2DD4BF, 0.18, 0.85, 0.10, 0.40)]
        : [(0xA5B4FC, 0.60, 0.20, 0.30, 0.55), (0xF9A8D4, 0.50, 0.90, 0.85, 0.50), (0x7DD3FC, 0.35, 0.85, 0.08, 0.40)]
    for (color, alpha, fx, fy, fr) in blobs {
        let center = NSPoint(x: c.size.width * fx, y: c.size.height * (1 - fy))
        NSGradient(colors: [hex(color, alpha), hex(color, 0)])!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: c.size.width * fr, options: [])
    }
}

func menuBar(_ c: Canvas, dark: Bool, app: String) {
    let h: CGFloat = 26
    (dark ? NSColor.black.withAlphaComponent(0.28) : NSColor.white.withAlphaComponent(0.5)).setFill()
    c.rect(0, 0, c.size.width, h).fill()
    let ink = dark ? NSColor.white : NSColor.black
    let bold: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: ink]
    let regular: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: ink.withAlphaComponent(0.9)]
    var x: CGFloat = 18
    for (i, word) in ([app] + ["File", "Edit", "View", "Window", "Help"]).enumerated() {
        let s = NSAttributedString(string: word, attributes: i == 0 ? bold : regular)
        s.draw(at: NSPoint(x: x, y: c.size.height - h + 5))
        x += s.size().width + 20
    }
    let clock = NSAttributedString(string: "Thu Nov 12  9:41 AM", attributes: regular)
    let clockX = c.size.width - clock.size().width - 18
    clock.draw(at: NSPoint(x: clockX, y: c.size.height - h + 5))

    // Linkhop's menu bar icon, highlighted, plus a couple of neutral status items.
    let iconX = clockX - 46
    NSColor(white: dark ? 1 : 0, alpha: dark ? 0.18 : 0.10).setFill()
    NSBezierPath(roundedRect: c.rect(iconX - 6, 3, 30, 20), xRadius: 6, yRadius: 6).fill()
    tintedTemplate(at: NSPoint(x: iconX, y: c.size.height - h + 4), color: ink)
    for (i, symbol) in ["wifi", "battery.75percent"].enumerated() {
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) {
            let tinted = NSImage(size: img.size, flipped: false) { r in
                img.draw(in: r)
                ink.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(at: NSPoint(x: iconX - 70 + CGFloat(i) * 32, y: c.size.height - h + (h - img.size.height) / 2),
                        from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
}

func tintedTemplate(at origin: NSPoint, color: NSColor) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    MenuBarIcon.draw()
    ctx.setBlendMode(.sourceIn)
    color.setFill()
    NSRect(x: 0, y: 0, width: 18, height: 18).fill()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

/// The classic macOS arrow pointer with its tip at `tip` (top-left coordinates).
func cursor(_ c: Canvas, tip: NSPoint, scale k: CGFloat = 1) {
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4.1, 13.1), (6.9, 19.4), (9.6, 18.2), (6.9, 12.1), (12.4, 12.1)]
    let path = NSBezierPath()
    for (i, p) in pts.enumerated() {
        let pt = NSPoint(x: tip.x + p.0 * k, y: c.size.height - tip.y - p.1 * k)
        i == 0 ? path.move(to: pt) : path.line(to: pt)
    }
    path.close()
    path.lineJoinStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(0.35)
    s.shadowBlurRadius = 3 * k
    s.shadowOffset = NSSize(width: 0, height: -1.5 * k)
    s.set()
    NSColor.white.setFill()
    path.lineWidth = 2.6 * k
    NSColor.white.setStroke()
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.black.setFill()
    path.fill()
}

// MARK: - Mock windows (SwiftUI)

struct MockWindow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { c in
                        Circle().fill(Color(nsColor: hex(UInt32(c)))).frame(width: 12, height: 12)
                    }
                    Spacer()
                }
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

/// Reports the link's frame so the cursor and picker can be placed on it.
@MainActor var linkFrame = CGRect.zero

struct ChatMock: View {
    struct Message: Identifiable {
        let id = UUID()
        let name, initials, time: String
        let color: Color
        let text: String
        var link: String? = nil
    }

    let messages: [Message] = [
        .init(name: "Ari Patel", initials: "AP", time: "9:30 AM", color: .indigo,
              text: "Standup in 10 ☕️"),
        .init(name: "Maya Chen", initials: "MC", time: "9:32 AM", color: .pink,
              text: "Roadmap doc is ready for review before standup 📋"),
        .init(name: "Sam Rivera", initials: "SR", time: "9:35 AM", color: .orange,
              text: "Looks great. Left a couple of comments on the Q1 section."),
        .init(name: "Jordan Lee", initials: "JL", time: "9:41 AM", color: .teal,
              text: "Shipped the new link router 🚀", link: "github.com/eliashussary/linkhop/releases/latest"),
    ]

    var body: some View {
        MockWindow(title: "") {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Acme").font(.system(size: 15, weight: .bold)).padding(.bottom, 10).padding(.horizontal, 8)
                    ForEach(["general", "design", "releases", "random"], id: \.self) { ch in
                        Text("# \(ch)")
                            .font(.system(size: 13, weight: ch == "releases" ? .semibold : .regular))
                            .foregroundStyle(ch == "releases" ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(ch == "releases" ? Color.accentColor.opacity(0.22) : .clear))
                    }
                    Spacer()
                }
                .padding(10)
                .frame(width: 170)
                .background(Color.primary.opacity(0.04))

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    Text("# releases").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 18).padding(.vertical, 12)
                    Divider()
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(messages) { m in message(m) }
                    }
                    .padding(18)
                    Spacer()
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.15))
                        .frame(height: 38)
                        .overlay(alignment: .leading) {
                            Text("Message #releases").foregroundStyle(.tertiary).padding(.leading, 12)
                        }
                        .padding(14)
                }
            }
        }
        .frame(width: 680, height: 470)
    }

    func message(_ m: Message) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(m.color.gradient).frame(width: 34, height: 34)
                .overlay(Text(m.initials).font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(m.name).font(.system(size: 13, weight: .bold))
                    Text(m.time).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(m.text).font(.system(size: 13))
                if let link = m.link {
                    Text(link)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
                        .underline()
                        .background(GeometryReader { g in
                            Color.clear.onAppear { linkFrame = g.frame(in: .global) }
                        })
                }
            }
        }
    }
}

struct SettingsMock: View {
    @ObservedObject var model: SettingsModel
    let tab: String

    var body: some View {
        MockWindow(title: "Linkhop Settings") {
            ZStack(alignment: .top) {
                Group {
                    switch tab {
                    case "rules": RulesTab(model: model)
                    case "browsers": BrowsersTab(model: model)
                    default: GeneralTab(model: model)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 24)
                .padding(.bottom, 14)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.035)))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.09)))
                .padding(.top, 12)

                HStack(spacing: 0) {
                    ForEach(["General", "Browsers", "Rules"], id: \.self) { item in
                        let on = item.lowercased() == tab
                        Text(item)
                            .font(.system(size: 13, weight: on ? .medium : .regular))
                            .padding(.horizontal, 14).padding(.vertical, 3)
                            .background {
                                if on {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(nsColor: .controlColor))
                                        .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
                                }
                            }
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
            }
            .padding(16)
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Scenes

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.prohibited)

    let browserIDs = ["com.brave.Browser", "com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox",
                      "com.microsoft.edgemac", "net.imput.helium", "com.openai.atlas"]
    let targets = browserIDs.compactMap(Browsers.target(for:))
    let url = URL(string: "https://github.com/eliashussary/linkhop")!

    @MainActor func pickerImage(selected: Int, dark: Bool, scale: CGFloat = 2) -> NSImage {
        let model = PickerModel(url: url, targets: targets)
        model.selected = selected
        return snapshot(PickerView(model: model) { _, _ in }, dark: dark, scale: scale)
    }

    @MainActor func settingsModel() -> SettingsModel {
        let m = SettingsModel()
        // Only real browsers (plus one unchecked) so the list reads cleanly.
        m.installed = (browserIDs + ["com.google.chrome.for.testing"]).compactMap(Browsers.target(for:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        m.isDefault = true
        m.config = Config(browsers: browserIDs, rules: [
            Rule(host: "github.com", open: "com.google.Chrome"),
            Rule(host: "linear.app", open: "com.linear"),
            Rule(host: "notion.so", open: "notion.id"),
            Rule(host: "open.spotify.com", open: "com.spotify.client"),
            Rule(host: "docs.google.com", from: "com.tinyspeck.slackmacgap", open: "com.google.Chrome"),
            Rule(from: "com.apple.mail", open: "com.apple.Safari"),
            Rule(host: "localhost", pattern: ":3000", open: "net.imput.helium"),
        ], fallback: nil)
        return m
    }

    for dark in [false, true] {
        let mode = dark ? "dark" : "light"

        // Hero: a link clicked in a chat app, with the picker at the cursor exactly where Linkhop puts it.
        do {
            let c = Canvas(1100, 680)
            let chat = snapshot(ChatMock(), dark: dark)
            let chatOrigin = NSPoint(x: 140, y: 92)
            let click = NSPoint(x: chatOrigin.x + linkFrame.maxX - 26, y: chatOrigin.y + linkFrame.midY)
            let probe = pickerImage(selected: 0, dark: dark)
            // Hovering selects the app under the cursor, so pick the cell the cursor lands on.
            let hovered = Int((probe.size.width / 2 - 6) / 42)
            let picker = pickerImage(selected: hovered, dark: dark)
            c.draw {
                wallpaper(c, dark: dark)
                menuBar(c, dark: dark, app: "Team Chat")
                c.place(chat, x: chatOrigin.x, y: chatOrigin.y, shadow: 40, dark: dark)
                c.place(picker, x: click.x - picker.size.width / 2, y: click.y - 12, shadow: 26, dark: dark)
                cursor(c, tip: NSPoint(x: click.x, y: click.y))
            }
            c.save("hero-\(mode)")
        }

        // Picker close-up, rendered at high resolution so the number keycaps read clearly.
        do {
            let c = Canvas(820, 260)
            let picker = pickerImage(selected: 0, dark: dark, scale: 5)
            let w = picker.size.width * 2.1
            let h = picker.size.height * 2.1
            let x = (c.size.width - w) / 2, y = (c.size.height - h) / 2
            c.draw {
                wallpaper(c, dark: dark)
                c.place(picker, x: x, y: y, width: w, shadow: 30, dark: dark)
                cursor(c, tip: NSPoint(x: x + 30 * 2.1, y: y + 30 * 2.1), scale: 1.8)
            }
            c.save("picker-\(mode)")
        }

        // Settings: Browsers tab behind, Rules tab in front.
        do {
            let c = Canvas(1100, 700)
            let browsers = snapshot(SettingsMock(model: settingsModel(), tab: "browsers"), dark: dark)
            let rules = snapshot(SettingsMock(model: settingsModel(), tab: "rules"), dark: dark)
            c.draw {
                wallpaper(c, dark: dark)
                c.place(browsers, x: 90, y: 60, shadow: 34, dark: dark)
                c.place(rules, x: 420, y: 150, shadow: 44, dark: dark)
            }
            c.save("settings-\(mode)")
        }
    }
}
