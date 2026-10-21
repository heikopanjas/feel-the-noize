import AppKit

/// The Mute item of the menu (Docs/DESIGN.md §5.3): "Mute" or, while muted, "Unmute", and at the right edge a speaker
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
            guard self.isMuted != oldValue else {
                return
            }
            self.setAccessibilityLabel(Self.title(isMuted: self.isMuted))
            self.needsDisplay = true
        }
    }

    init() {
        super.init(frame: .zero)
        // Wide enough for either title, so the menu does not change width when the state changes.
        let titleWidth =
            [false, true].map { NSAttributedString(string: Self.title(isMuted: $0), attributes: [.font: Self.font]).size().width }
            .max() ?? 0
        let inset = MenuInfoRow.inset
        self.frame = NSRect(x: 0, y: 0, width: ceil(inset + titleWidth + Self.symbolGap + Self.symbolPointSize * 1.5 + inset), height: Self.height)
        self.autoresizingMask = [.width]
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.menuItem)
        self.setAccessibilityLabel(Self.title(isMuted: false))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    static func title(isMuted: Bool) -> String {
        return isMuted == true ? "Unmute" : "Mute"
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) -> Void {
        let item = self.enclosingMenuItem
        let isEnabled = item?.isEnabled ?? true
        let isHighlighted = isEnabled == true && item?.isHighlighted == true
        if isHighlighted == true {
            NSColor.controlAccentColor.setFill()
            let rect = self.bounds.insetBy(dx: Self.highlightInset, dy: 0)
            NSBezierPath(roundedRect: rect, xRadius: Self.highlightRadius, yRadius: Self.highlightRadius).fill()
        }
        let textColor: NSColor
        let symbolColor: NSColor
        if isHighlighted == true {
            textColor = .selectedMenuItemTextColor
            symbolColor = .selectedMenuItemTextColor
        }
        else if isEnabled == true {
            textColor = .labelColor
            symbolColor = .secondaryLabelColor
        }
        else {
            textColor = .tertiaryLabelColor
            symbolColor = .tertiaryLabelColor
        }
        let title = NSAttributedString(string: Self.title(isMuted: self.isMuted), attributes: [.font: Self.font, .foregroundColor: textColor])
        let titleSize = title.size()
        title.draw(at: NSPoint(x: MenuInfoRow.inset, y: self.bounds.midY - titleSize.height / 2))

        let configuration = NSImage.SymbolConfiguration(pointSize: Self.symbolPointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: symbolColor))
        let name = self.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill"
        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            let size = symbol.size
            let origin = NSPoint(x: self.bounds.maxX - MenuInfoRow.inset - size.width, y: self.bounds.midY - size.height / 2)
            symbol.draw(in: NSRect(origin: origin, size: size))
        }
    }

    /// A view-based item does not send its action by itself.
    override func mouseUp(with event: NSEvent) -> Void {
        guard let item = self.enclosingMenuItem else {
            return
        }
        guard item.isEnabled == true else {
            return
        }
        guard let menu = item.menu else {
            return
        }
        guard let action = item.action else {
            return
        }
        menu.cancelTracking()
        NSApp.sendAction(action, to: item.target, from: item)
    }
}
