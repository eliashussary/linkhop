// Renders Resources/AppIcon.icns. Run via `make icon`.
import AppKit

let canvas: CGFloat = 1024

func draw() {
    // macOS icon grid: 824pt tile centered on a 1024 canvas.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(srgbRed: 0.47, green: 0.40, blue: 1.00, alpha: 1),
               ending: NSColor(srgbRed: 0.20, green: 0.14, blue: 0.74, alpha: 1))!
        .draw(in: tile, angle: -90)

    // Take-off and landing pads.
    NSColor.white.withAlphaComponent(0.5).setFill()
    NSBezierPath(roundedRect: NSRect(x: 220, y: 300, width: 190, height: 40), xRadius: 20, yRadius: 20).fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 612, y: 300, width: 190, height: 40), xRadius: 20, yRadius: 20).fill()

    // Dotted hop arc.
    let p0 = NSPoint(x: 315, y: 400), c1 = NSPoint(x: 335, y: 820)
    let c2 = NSPoint(x: 690, y: 820), p3 = NSPoint(x: 706, y: 460)
    let arc = NSBezierPath()
    arc.move(to: p0)
    arc.curve(to: p3, controlPoint1: c1, controlPoint2: c2)
    arc.lineWidth = 52
    arc.lineCapStyle = .round
    arc.setLineDash([0, 96], count: 2, phase: 0)
    NSColor.white.setStroke()
    arc.stroke()

    // Arrowhead landing on the right pad, aligned with the arc's end tangent.
    let dx = p3.x - c2.x, dy = p3.y - c2.y, len = (dx * dx + dy * dy).squareRoot()
    let d = NSPoint(x: dx / len, y: dy / len), n = NSPoint(x: -d.y, y: d.x)
    let tip = NSPoint(x: p3.x + d.x * 72, y: p3.y + d.y * 72)
    let base = NSPoint(x: p3.x - d.x * 32, y: p3.y - d.y * 32) // covers the arc's last dot
    let head = NSBezierPath()
    head.move(to: tip)
    head.line(to: NSPoint(x: base.x + n.x * 66, y: base.y + n.y * 66))
    head.line(to: NSPoint(x: base.x - n.x * 66, y: base.y - n.y * 66))
    head.close()
    head.lineJoinStyle = .round
    head.lineWidth = 24
    head.fill()
    head.stroke()
}

func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(px) / canvas, y: CGFloat(px) / canvas)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: out)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! png(size).write(to: out.appending(path: "icon_\(size)x\(size).png"))
    try! png(size * 2).write(to: out.appending(path: "icon_\(size)x\(size)@2x.png"))
}
