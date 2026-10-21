import AppKit

/// One status line at the top of the menu (docs/DESIGN.md §5.3), with an optional battery level at the right edge.
///
/// A custom item view, because a menu item title cannot align anything with the right edge of the menu. All status lines use
/// it, so they share the left inset of the volume heading and slider. AppKit widens the row to the menu.
final class MenuInfoRow: NSView {
    static let inset: CGFloat = 14
    private static let height: CGFloat = 19
    private static let batterySpacing: CGFloat = 5
    /// The status lines are information, not commands, so they use a smaller font and the secondary label color.
    private static let font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)

    var text = "" {
        didSet {
            label.stringValue = text
            layoutRow()
        }
    }

    /// Shows "85 %" and a battery symbol at the right edge; `nil` hides both.
    var batteryLevel: Int? {
        didSet {
            guard batteryLevel != oldValue else { return }
            updateBattery()
            layoutRow()
        }
    }

    private let label = NSTextField(labelWithString: "")
    /// The percentage and the battery symbol as one attributed string, so they stay together and share the baseline.
    private let batteryLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Self.height))
        autoresizingMask = [.width]
        for field in [label, batteryLabel] {
            field.font = Self.font
            field.textColor = .secondaryLabelColor
            addSubview(field)
        }
        label.lineBreakMode = .byTruncatingTail
        label.autoresizingMask = [.width]
        batteryLabel.autoresizingMask = [.minXMargin]
        updateBattery()
        layoutRow()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func updateBattery() {
        batteryLabel.isHidden = batteryLevel == nil
        guard let batteryLevel else { return }
        let attachment = NSTextAttachment()
        attachment.image = BatteryIcon.image(level: batteryLevel, accessibilityDescription: "battery")
        // Centers the symbol on the digits instead of sitting on the baseline.
        let offset = (Self.font.capHeight - BatteryIcon.size.height) / 2
        attachment.bounds = NSRect(origin: NSPoint(x: 0, y: offset), size: BatteryIcon.size)
        let text = NSMutableAttributedString(
            string: "\(batteryLevel) %\u{2002}", attributes: [.font: Self.font, .foregroundColor: NSColor.secondaryLabelColor])
        text.append(NSAttributedString(attachment: attachment))
        batteryLabel.attributedStringValue = text
    }

    /// Sets the natural width, which the menu uses to size itself, and places the parts from both edges.
    private func layoutRow() {
        label.sizeToFit()
        batteryLabel.sizeToFit()
        let batteryWidth = batteryLevel == nil ? 0 : Self.batterySpacing + batteryLabel.frame.width
        let width = Self.inset + label.frame.width + batteryWidth + Self.inset
        frame.size.width = max(frame.width, width)

        let midY = bounds.midY
        batteryLabel.setFrameOrigin(
            NSPoint(x: bounds.maxX - Self.inset - batteryLabel.frame.width, y: midY - batteryLabel.frame.height / 2))
        let labelRight = batteryLevel == nil ? bounds.maxX - Self.inset : batteryLabel.frame.minX - Self.batterySpacing
        label.frame = NSRect(
            x: Self.inset, y: midY - label.frame.height / 2, width: max(labelRight - Self.inset, 0), height: label.frame.height)
    }
}
