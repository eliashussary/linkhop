import AppKit

/// The app icon's hop (dotted arc from a faded pad, landing as an arrow on a solid pad),
/// redrawn as an 18pt template image so it follows the menu bar's light/dark appearance.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Linkhop"
        return image
    }()

    static func draw() {
        // Take-off (faded) and landing pads.
        NSColor.black.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.5, width: 5.5, height: 1.7), xRadius: 0.85, yRadius: 0.85).fill()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 11, y: 2.5, width: 5.5, height: 1.7), xRadius: 0.85, yRadius: 0.85).fill()

        // Dotted arc.
        let p0 = NSPoint(x: 4.25, y: 6.4), c1 = NSPoint(x: 4.6, y: 16.6)
        let c2 = NSPoint(x: 13.4, y: 16.6), p3 = NSPoint(x: 13.75, y: 8.4)
        let arc = NSBezierPath()
        arc.move(to: p0)
        arc.curve(to: p3, controlPoint1: c1, controlPoint2: c2)
        arc.lineWidth = 2
        arc.lineCapStyle = .round
        arc.setLineDash([0, 3.4], count: 2, phase: 0)
        NSColor.black.setStroke()
        arc.stroke()

        // Arrowhead along the arc's end tangent, covering its last dot.
        let dx = p3.x - c2.x, dy = p3.y - c2.y, len = (dx * dx + dy * dy).squareRoot()
        let d = NSPoint(x: dx / len, y: dy / len), n = NSPoint(x: -d.y, y: d.x)
        let tip = NSPoint(x: p3.x + d.x * 2.5, y: p3.y + d.y * 2.5)
        let base = NSPoint(x: p3.x - d.x * 2.0, y: p3.y - d.y * 2.0)
        let head = NSBezierPath()
        head.move(to: tip)
        head.line(to: NSPoint(x: base.x + n.x * 2.7, y: base.y + n.y * 2.7))
        head.line(to: NSPoint(x: base.x - n.x * 2.7, y: base.y - n.y * 2.7))
        head.close()
        head.lineJoinStyle = .round
        head.lineWidth = 0.8
        head.fill()
        head.stroke()
    }
}
