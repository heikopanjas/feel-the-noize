import AppKit

/// Draws the knob that stands for Feel the Noize in the menu bar and the overlay (docs/DESIGN.md §5.2), so it cannot be confused
/// with the speaker of the system Sound item. Images are vector template images: they stay sharp at any size and macOS
/// tints them for light and dark mode; the unlit parts use partial alpha.
nonisolated enum KnobIcon {
    enum Style: String, CaseIterable {
        /// Filled knob with a pointer inside an arc lit up to the level, like the app icon.
        case arc
        /// Outlined circle with a pointer line.
        case ring
        /// Filled knob with seven scale dots lit up to the level.
        case dots

        var title: String {
            switch self {
                case .arc: "Arc"
                case .ring: "Ring"
                case .dots: "Dots"
            }
        }
    }

    // The pointer sweeps 270 degrees clockwise, from lower left at 0 to lower right at 1, like the volume scale of the app icon.
    private static let startDegrees: CGFloat = 225
    private static let sweepDegrees: CGFloat = 270
    private static let unlitAlpha: CGFloat = 0.3
    private static let dotCount = 7

    /// Pointer angle in degrees, counter-clockwise from the positive x axis, for a level clamped to 0…1.
    static func pointerDegrees(for level: Float) -> CGFloat {
        startDegrees - sweepDegrees * CGFloat(min(max(level, 0), 1))
    }

    static func image(style: Style, level: Float, isMuted: Bool, size: CGFloat, accessibilityDescription: String?) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(style: style, level: level, isMuted: isMuted, in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    // MARK: - Drawing

    /// All measures are in units of an 18-unit square, the menu bar size, and scaled to the rect.
    private static func draw(style: Style, level: Float, isMuted: Bool, in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = rect.width / 18
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let pointer = pointerDegrees(for: level)
        let lit = !isMuted && level > 0

        // A transparency layer lets the knock-outs below cut only through the knob, not through the menu bar behind it.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        switch style {
            case .arc:
                stroke(arcFrom: startDegrees, to: startDegrees - sweepDegrees, radius: 7.6, width: 1.5, alpha: unlitAlpha, center, scale)
                if lit {
                    stroke(arcFrom: startDegrees, to: pointer, radius: 7.6, width: 1.5, alpha: 1, center, scale)
                }
                drawDisc(radius: 4.8, pointer: pointer, isMuted: isMuted, center, scale, context)
            case .ring:
                let ring = NSBezierPath(ovalIn: square(center, radius: 7 * scale))
                ring.lineWidth = 1.6 * scale
                NSColor.black.setStroke()
                ring.stroke()
                if !isMuted {
                    line(from: point(center, 1.5 * scale, pointer), to: point(center, 5.2 * scale, pointer), width: 2 * scale)
                }
            case .dots:
                for index in 0 ..< dotCount {
                    let fraction = Float(index) / Float(dotCount - 1)
                    let isOn = lit && fraction <= level + 0.001
                    NSColor.black.withAlphaComponent(isOn ? 1 : unlitAlpha).setFill()
                    NSBezierPath(ovalIn: square(point(center, 7.6 * scale, pointerDegrees(for: fraction)), radius: 1 * scale)).fill()
                }
                drawDisc(radius: 5, pointer: pointer, isMuted: isMuted, center, scale, context)
        }
        if isMuted {
            // A slash with a knock-out gap on both sides, so it stays readable at 18 points.
            let from = CGPoint(x: center.x - 7.5 * scale, y: center.y + 7.5 * scale)
            let to = CGPoint(x: center.x + 7.5 * scale, y: center.y - 7.5 * scale)
            knockOut(from: from, to: to, width: 3.6 * scale, context)
            line(from: from, to: to, width: 1.6 * scale)
        }
        context.endTransparencyLayer()
    }

    /// A filled knob with the pointer cut out of it; an outline only when muted.
    private static func drawDisc(radius: CGFloat, pointer: CGFloat, isMuted: Bool, _ center: CGPoint, _ scale: CGFloat, _ context: CGContext) {
        let disc = NSBezierPath(ovalIn: square(center, radius: radius * scale))
        if isMuted {
            disc.lineWidth = 1.4 * scale
            NSColor.black.setStroke()
            disc.stroke()
        }
        else {
            NSColor.black.setFill()
            disc.fill()
            knockOut(from: center, to: point(center, (radius - 1.1) * scale, pointer), width: 1.6 * scale, context)
        }
    }

    private static func stroke(
        arcFrom start: CGFloat, to end: CGFloat, radius: CGFloat, width: CGFloat, alpha: CGFloat, _ center: CGPoint, _ scale: CGFloat
    ) {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius * scale, startAngle: start, endAngle: end, clockwise: true)
        arc.lineWidth = width * scale
        arc.lineCapStyle = .round
        NSColor.black.withAlphaComponent(alpha).setStroke()
        arc.stroke()
    }

    private static func line(from start: CGPoint, to end: CGPoint, width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = width
        path.lineCapStyle = .round
        NSColor.black.setStroke()
        path.stroke()
    }

    private static func knockOut(from start: CGPoint, to end: CGPoint, width: CGFloat, _ context: CGContext) {
        context.saveGState()
        context.setBlendMode(.clear)
        line(from: start, to: end, width: width)
        context.restoreGState()
    }

    private static func point(_ center: CGPoint, _ radius: CGFloat, _ degrees: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
    }

    private static func square(_ center: CGPoint, radius: CGFloat) -> NSRect {
        NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
