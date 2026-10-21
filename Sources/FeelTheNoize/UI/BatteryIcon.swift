import AppKit

/// Battery symbol filled to the level, as in the battery indicators of the macOS menus (Docs/DESIGN.md §5.3).
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
        if clamped == 0 {
            return 0
        }
        return max(CGFloat(clamped) / 100, 0.08)
    }

    /// The battery text of the menu rows in the small menu font: "85 %" followed by the symbol for a single cell, or text
    /// such as "L 80 %, R 75 %, case 40 %" alone. Dial and device rows share it, so they look the same.
    static func attributedText(_ text: String, level: Int?) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let result = NSMutableAttributedString(string: text, attributes: attributes)
        if let level = level {
            let attachment = NSTextAttachment()
            attachment.image = Self.image(level: level, accessibilityDescription: "battery")
            // Centers the symbol on the digits instead of sitting on the baseline.
            attachment.bounds = NSRect(origin: NSPoint(x: 0, y: (font.capHeight - Self.size.height) / 2), size: Self.size)
            result.append(NSAttributedString(string: "\u{2002}", attributes: attributes))
            result.append(NSAttributedString(attachment: attachment))
        }
        return result
    }

    static func image(level: Int, accessibilityDescription: String?) -> NSImage {
        let image = NSImage(size: Self.size, flipped: false) { rect in
            Self.draw(level: level, in: rect)
            return true
        }
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    /// Colors resolve when the menu draws, so the image follows light and dark mode.
    private static func draw(level: Int, in rect: NSRect) -> Void {
        let body = NSRect(x: rect.minX, y: rect.minY, width: rect.width - Self.terminalWidth, height: rect.height)
        let inset = Self.lineWidth / 2
        let outline = NSBezierPath(
            roundedRect: body.insetBy(dx: inset, dy: inset), xRadius: Self.cornerRadius - inset, yRadius: Self.cornerRadius - inset)
        outline.lineWidth = Self.lineWidth
        NSColor.secondaryLabelColor.withAlphaComponent(Self.outlineAlpha).setStroke()
        outline.stroke()

        let terminal = NSRect(x: body.maxX, y: rect.midY - Self.terminalHeight / 2, width: Self.terminalWidth, height: Self.terminalHeight)
        NSColor.secondaryLabelColor.withAlphaComponent(Self.outlineAlpha).setFill()
        NSBezierPath(roundedRect: terminal, xRadius: Self.terminalWidth / 2, yRadius: Self.terminalWidth / 2).fill()

        let inner = body.insetBy(dx: Self.fillInset, dy: Self.fillInset)
        let fill = NSRect(x: inner.minX, y: inner.minY, width: inner.width * Self.fillFraction(level: level), height: inner.height)
        let fillColor: NSColor = level <= Self.lowLevel ? .systemRed : .secondaryLabelColor
        fillColor.setFill()
        let radius = Self.cornerRadius - Self.fillInset / 2
        NSBezierPath(roundedRect: fill, xRadius: min(radius, fill.width / 2), yRadius: radius).fill()
    }
}
