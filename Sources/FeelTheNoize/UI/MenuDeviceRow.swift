import AppKit

/// One device in the Output or Input section of the menu (Docs/DESIGN.md §5.3, §7.11): the device icon, the name, and the
/// battery at the right edge, in the column of the Dial row's battery.
///
/// A custom item view, because a menu item title cannot align anything with the right edge of the menu. It therefore
/// draws its own highlight, a rounded gray background like the macOS Sound menu, and performs the item's action on click.
final class MenuDeviceRow: NSView {
    private static let height: CGFloat = 32
    private static let iconGap: CGFloat = 8
    private static let batterySpacing: CGFloat = 12
    private static let highlightInset: CGFloat = 5
    private static let highlightRadius: CGFloat = 6
    private static let highlightColor = NSColor.labelColor.withAlphaComponent(0.1)

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let batteryLabel = NSTextField(labelWithString: "")

    /// `battery` is the text and, for a single cell, the level that adds the battery symbol.
    init(name: String, isDefault: Bool, icon: NSImage, battery: (text: String, level: Int?)?, accessibilityLabel: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Self.height))
        autoresizingMask = [.width]

        iconView.image = icon
        iconView.imageScaling = .scaleNone
        nameLabel.stringValue = name
        let fontSize = NSFont.menuFont(ofSize: 0).pointSize
        nameLabel.font = isDefault ? .boldSystemFont(ofSize: fontSize) : .menuFont(ofSize: fontSize)
        nameLabel.lineBreakMode = .byTruncatingTail
        if let battery {
            batteryLabel.attributedStringValue = BatteryIcon.attributedText(battery.text, level: battery.level)
        }
        batteryLabel.isHidden = battery == nil
        for subview in [iconView, nameLabel, batteryLabel] {
            subview.setAccessibilityElement(false)
            addSubview(subview)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(accessibilityLabel)
        layoutRow(hasBattery: battery != nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Same layout as `MenuInfoRow`: the natural width sizes the menu, and the battery keeps its distance from the right edge.
    private func layoutRow(hasBattery: Bool) {
        nameLabel.sizeToFit()
        batteryLabel.sizeToFit()
        let inset = MenuInfoRow.inset
        let iconSize = NSSize(width: DeviceIcon.diameter, height: DeviceIcon.diameter)
        let batteryWidth = hasBattery ? Self.batterySpacing + batteryLabel.frame.width : 0
        frame.size.width = inset + iconSize.width + Self.iconGap + nameLabel.frame.width + batteryWidth + inset

        let midY = bounds.midY
        iconView.frame = NSRect(origin: NSPoint(x: inset, y: midY - iconSize.height / 2), size: iconSize)
        batteryLabel.setFrameOrigin(
            NSPoint(x: bounds.maxX - inset - batteryLabel.frame.width, y: midY - batteryLabel.frame.height / 2))
        batteryLabel.autoresizingMask = [.minXMargin]
        let nameX = iconView.frame.maxX + Self.iconGap
        let nameRight = hasBattery ? batteryLabel.frame.minX - Self.batterySpacing : bounds.maxX - inset
        nameLabel.frame = NSRect(x: nameX, y: midY - nameLabel.frame.height / 2, width: nameRight - nameX, height: nameLabel.frame.height)
        nameLabel.autoresizingMask = [.width]
    }

    // MARK: - Menu Item Behavior

    override func draw(_ dirtyRect: NSRect) {
        guard enclosingMenuItem?.isHighlighted == true else { return }
        Self.highlightColor.setFill()
        let rect = bounds.insetBy(dx: Self.highlightInset, dy: 0)
        NSBezierPath(roundedRect: rect, xRadius: Self.highlightRadius, yRadius: Self.highlightRadius).fill()
    }

    /// A view-based item does not send its action by itself.
    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, item.isEnabled, let menu = item.menu, let action = item.action else { return }
        menu.cancelTracking()
        NSApp.sendAction(action, to: item.target, from: item)
    }
}
