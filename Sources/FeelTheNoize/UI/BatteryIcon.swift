import AppKit

/// Battery symbol filled to the level, as in the battery indicators of the macOS menus (docs/DESIGN.md §5.3).
///
/// SF Symbols offers the battery only in quarter steps (`battery.25` and so on), and `battery.100percent` ignores a
/// variable value, so the symbol is drawn: a light outline with a terminal, filled with the secondary label color, or red
/// when the level is low.
nonisolated enum BatteryIcon {
    /// Measured on the battery next to the AirPods in the macOS Sound menu.
    static let size = NSSize(width: 20, height: 9.5)
    static let lowLevel = 20
    private static let terminalWidth: CGFloat = 1.5
    private static let terminalHeight: CGFloat = 3.5
    private static let cornerRadius: CGFloat = 2.5
    private static let lineWidth: CGFloat = 1
    private static let fillInset: CGFloat = 2
    private static let outlineAlpha: CGFloat = 0.45

    /// Width of the fill as a fraction of the inner width; any level above zero shows a sliver.
    static func fillFraction(level: Int) -> CGFloat {
        let clamped = min(max(level, 0), 100)
        return clamped == 0 ? 0 : max(CGFloat(clamped) / 100, 0.08)
    }

    static func image(level: Int, accessibilityDescription: String?) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(level: level, in: rect)
            return true
        }
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    /// Colors resolve when the menu draws, so the image follows light and dark mode.
    private static func draw(level: Int, in rect: NSRect) {
        let body = NSRect(x: rect.minX, y: rect.minY, width: rect.width - terminalWidth, height: rect.height)
        let inset = lineWidth / 2
        let outline = NSBezierPath(
            roundedRect: body.insetBy(dx: inset, dy: inset), xRadius: cornerRadius - inset, yRadius: cornerRadius - inset)
        outline.lineWidth = lineWidth
        NSColor.secondaryLabelColor.withAlphaComponent(outlineAlpha).setStroke()
        outline.stroke()

        let terminal = NSRect(x: body.maxX, y: rect.midY - terminalHeight / 2, width: terminalWidth, height: terminalHeight)
        NSColor.secondaryLabelColor.withAlphaComponent(outlineAlpha).setFill()
        NSBezierPath(roundedRect: terminal, xRadius: terminalWidth / 2, yRadius: terminalWidth / 2).fill()

        let inner = body.insetBy(dx: fillInset, dy: fillInset)
        let fill = NSRect(x: inner.minX, y: inner.minY, width: inner.width * fillFraction(level: level), height: inner.height)
        (level <= lowLevel ? NSColor.systemRed : NSColor.secondaryLabelColor).setFill()
        let radius = cornerRadius - fillInset / 2
        NSBezierPath(roundedRect: fill, xRadius: min(radius, fill.width / 2), yRadius: radius).fill()
    }
}
