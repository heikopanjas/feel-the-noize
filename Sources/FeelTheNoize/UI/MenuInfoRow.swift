import AppKit

/// One status line at the top of the menu (Docs/DESIGN.md §5.3), with an optional battery level at the right edge.
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
            self.label.stringValue = self.text
            self.layoutRow()
        }
    }

    /// Shows "85 %" and a battery symbol at the right edge; `nil` hides both.
    var batteryLevel: Int? {
        didSet {
            guard self.batteryLevel != oldValue else {
                return
            }
            self.updateBattery()
            self.layoutRow()
        }
    }

    private let label = NSTextField(labelWithString: "")
    /// The percentage and the battery symbol as one attributed string, so they stay together and share the baseline.
    private let batteryLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Self.height))
        self.autoresizingMask = [.width]
        for field in [self.label, self.batteryLabel] {
            field.font = Self.font
            field.textColor = .secondaryLabelColor
            self.addSubview(field)
        }
        self.label.lineBreakMode = .byTruncatingTail
        self.label.autoresizingMask = [.width]
        self.batteryLabel.autoresizingMask = [.minXMargin]
        self.updateBattery()
        self.layoutRow()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func updateBattery() -> Void {
        self.batteryLabel.isHidden = self.batteryLevel == nil
        if let batteryLevel = self.batteryLevel {
            self.batteryLabel.attributedStringValue = BatteryIcon.attributedText("\(batteryLevel) %", level: batteryLevel)
        }
    }

    /// Sets the natural width, which the menu uses to size itself, and places the parts from both edges.
    private func layoutRow() -> Void {
        self.label.sizeToFit()
        self.batteryLabel.sizeToFit()
        let batteryWidth = self.batteryLevel == nil ? 0 : Self.batterySpacing + self.batteryLabel.frame.width
        let width = Self.inset + self.label.frame.width + batteryWidth + Self.inset
        self.frame.size.width = max(self.frame.width, width)

        let midY = self.bounds.midY
        self.batteryLabel.setFrameOrigin(
            NSPoint(x: self.bounds.maxX - Self.inset - self.batteryLabel.frame.width, y: midY - self.batteryLabel.frame.height / 2))
        let labelRight = self.batteryLevel == nil ? self.bounds.maxX - Self.inset : self.batteryLabel.frame.minX - Self.batterySpacing
        self.label.frame = NSRect(
            x: Self.inset, y: midY - self.label.frame.height / 2, width: max(labelRight - Self.inset, 0), height: self.label.frame.height)
    }
}
