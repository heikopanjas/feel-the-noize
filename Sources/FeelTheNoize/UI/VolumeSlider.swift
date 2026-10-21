import AppKit

/// The menu's volume slider, drawn like the slider of the macOS Sound menu (docs/DESIGN.md §5.3): a bordered capsule track,
/// a white fill up to a white round knob, and the output symbol at the left end.
///
/// Only drawing is replaced; `NSSliderCell` keeps tracking, keyboard control and accessibility. Colors were measured on a
/// screenshot of the Sound menu in light mode; the dark values are estimates.
final class VolumeSlider: NSSlider {
    static let trackHeight: CGFloat = 22

    /// SF Symbol drawn at the left end; set by the menu for the current output.
    var symbolName: String {
        get { drawingCell.symbolName }
        set {
            drawingCell.symbolName = newValue
            needsDisplay = true
        }
    }

    private let drawingCell = Cell()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = drawingCell
        minValue = 0
        maxValue = 1
        isContinuous = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Menus draw item views over a vibrant material, which would wash out the measured colors.
    override var allowsVibrancy: Bool {
        false
    }

    // MARK: - Cell

    /// The bar spans the whole cell and the knob is as thick as the bar, so the default tracking puts the knob under the pointer.
    private final class Cell: NSSliderCell {
        private static let glyphPointSize: CGFloat = 11
        private static let borderWidth: CGFloat = 1
        private static let disabledAlpha: CGFloat = 0.5
        private static let trackColor = dynamicColor(light: 0xD8, dark: 0x4A)
        private static let borderColor = dynamicColor(light: 0xC6, dark: 0x60)
        /// The left end is always white, under the fill or the knob, so the glyph color does not depend on the appearance.
        private static let glyphColor = NSColor(white: 0xB8 / 255, alpha: 1)
        private static let knobEdgeAlpha: CGFloat = 0.18
        private static let knobShadowAlpha: CGFloat = 0.25

        var symbolName = "speaker.wave.2.fill"

        override var knobThickness: CGFloat {
            VolumeSlider.trackHeight
        }

        override func barRect(flipped: Bool) -> NSRect {
            let bounds = controlView?.bounds ?? .zero
            return NSRect(x: bounds.minX, y: bounds.midY - VolumeSlider.trackHeight / 2, width: bounds.width, height: VolumeSlider.trackHeight)
        }

        override func knobRect(flipped: Bool) -> NSRect {
            let bar = barRect(flipped: flipped)
            let range = maxValue - minValue
            let fraction = range > 0 ? CGFloat((doubleValue - minValue) / range) : 0
            return NSRect(x: bar.minX + (bar.width - bar.height) * fraction, y: bar.minY, width: bar.height, height: bar.height)
        }

        override func drawBar(inside rect: NSRect, flipped: Bool) {
            let bar = barRect(flipped: flipped)
            let radius = bar.height / 2
            let alpha = isEnabled ? 1 : Self.disabledAlpha
            Self.trackColor.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()

            let fill = NSRect(x: bar.minX, y: bar.minY, width: knobRect(flipped: flipped).maxX - bar.minX, height: bar.height)
            NSColor.white.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()

            // The border runs around the whole capsule, over the fill as well.
            let inset = Self.borderWidth / 2
            let border = NSBezierPath(roundedRect: bar.insetBy(dx: inset, dy: inset), xRadius: radius - inset, yRadius: radius - inset)
            border.lineWidth = Self.borderWidth
            Self.borderColor.withAlphaComponent(alpha).setStroke()
            border.stroke()
        }

        /// The symbol is drawn after the knob, so it stays visible when the knob covers the left end at low volume.
        override func drawKnob(_ knobRect: NSRect) {
            let alpha = isEnabled ? 1 : Self.disabledAlpha
            let knob = NSBezierPath(ovalIn: knobRect.insetBy(dx: 0.5, dy: 0.5))
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(Self.knobShadowAlpha * alpha)
            shadow.shadowOffset = .zero
            shadow.shadowBlurRadius = 4
            shadow.set()
            NSColor.white.withAlphaComponent(alpha).setFill()
            knob.fill()
            NSGraphicsContext.restoreGraphicsState()
            knob.lineWidth = 0.5
            NSColor.black.withAlphaComponent(Self.knobEdgeAlpha * alpha).setStroke()
            knob.stroke()

            drawSymbol(alpha: alpha)
        }

        private func drawSymbol(alpha: CGFloat) {
            let bar = barRect(flipped: controlView?.isFlipped ?? false)
            let configuration = NSImage.SymbolConfiguration(pointSize: Self.glyphPointSize, weight: .regular)
                .applying(NSImage.SymbolConfiguration(hierarchicalColor: Self.glyphColor.withAlphaComponent(alpha)))
            guard let glyph = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
            else { return }
            let size = glyph.size
            let center = NSPoint(x: bar.minX + bar.height / 2, y: bar.midY)
            glyph.draw(in: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height))
        }

        private static func dynamicColor(light: Int, dark: Int) -> NSColor {
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(white: CGFloat(isDark ? dark : light) / 255, alpha: 1)
            }
        }
    }
}
