import AppKit

/// The Mute item of the menu (docs/DESIGN.md §5.3): "Mute" or, while muted, "Unmute", and at the right edge a speaker
/// symbol that shows whether the output is muted.
///
/// A checkmark would make macOS add a state column to the whole menu, which shifts every standard item to the right while
/// the custom rows stay put. This custom item view shows the state without one. It draws the standard accent highlight,
/// since it sits among standard items, and performs the item's action on click.
final class MenuMuteRow: NSView {
    private static let height: CGFloat = 22
    private static let symbolPointSize: CGFloat = 13
    private static let symbolGap: CGFloat = 20
    private static let highlightInset: CGFloat = 5
    private static let highlightRadius: CGFloat = 4
    private static let font = NSFont.menuFont(ofSize: 0)

    var isMuted = false {
        didSet {
            guard isMuted != oldValue else { return }
            setAccessibilityLabel(Self.title(isMuted: isMuted))
            needsDisplay = true
        }
    }

    init() {
        super.init(frame: .zero)
        // Wide enough for either title, so the menu does not change width when the state changes.
        let titleWidth =
            [false, true].map { NSAttributedString(string: Self.title(isMuted: $0), attributes: [.font: Self.font]).size().width }
            .max() ?? 0
        let inset = MenuInfoRow.inset
        frame = NSRect(x: 0, y: 0, width: ceil(inset + titleWidth + Self.symbolGap + Self.symbolPointSize * 1.5 + inset), height: Self.height)
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(Self.title(isMuted: false))
    }

    required init?(coder: NSCoder) {
        nil
    }

    static func title(isMuted: Bool) -> String {
        isMuted ? "Unmute" : "Mute"
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let item = enclosingMenuItem
        let isEnabled = item?.isEnabled ?? true
        let isHighlighted = isEnabled && item?.isHighlighted == true
        if isHighlighted {
            NSColor.controlAccentColor.setFill()
            let rect = bounds.insetBy(dx: Self.highlightInset, dy: 0)
            NSBezierPath(roundedRect: rect, xRadius: Self.highlightRadius, yRadius: Self.highlightRadius).fill()
        }
        let textColor: NSColor = isHighlighted ? .selectedMenuItemTextColor : isEnabled ? .labelColor : .tertiaryLabelColor
        let title = NSAttributedString(string: Self.title(isMuted: isMuted), attributes: [.font: Self.font, .foregroundColor: textColor])
        let titleSize = title.size()
        title.draw(at: NSPoint(x: MenuInfoRow.inset, y: bounds.midY - titleSize.height / 2))

        let symbolColor: NSColor = isHighlighted ? .selectedMenuItemTextColor : isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: Self.symbolPointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: symbolColor))
        let name = isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        else { return }
        let size = symbol.size
        symbol.draw(
            in: NSRect(x: bounds.maxX - MenuInfoRow.inset - size.width, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
    }

    /// A view-based item does not send its action by itself.
    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, item.isEnabled, let menu = item.menu, let action = item.action else { return }
        menu.cancelTracking()
        NSApp.sendAction(action, to: item.target, from: item)
    }
}
