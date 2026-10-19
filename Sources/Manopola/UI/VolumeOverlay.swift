import AppKit

/// On-screen volume display for Dial-initiated changes (docs/DESIGN.md §5.4).
///
/// Core Audio writes do not show the system volume HUD, so Manopola shows its own. Keyboard changes keep the system HUD,
/// which is why this overlay is never shown for them.
final class VolumeOverlay {
    private static let size = NSSize(width: 200, height: 200)
    private static let cornerRadius: CGFloat = 18
    private static let bottomOffset: CGFloat = 140
    private static let visibleDuration: Duration = .milliseconds(1500)
    private static let fadeDuration: TimeInterval = 0.3

    private let imageView = NSImageView()
    private let levelBar = LevelBar()
    private let label = NSTextField(labelWithString: "")
    private lazy var panel = makePanel()
    private var hideTask: Task<Void, Never>?
    // Lets a fade that finishes after a new show() leave the panel on screen.
    private var showGeneration = 0
    private static let knobSize: CGFloat = 72

    var iconStyle = KnobIcon.Style.arc

    func show(_ state: AudioState) {
        imageView.image = VolumePresentation.knobImage(
            for: state, style: iconStyle, size: Self.knobSize, accessibilityDescription: VolumePresentation.accessibilityDescription(for: state))
        levelBar.level = state.isMuted ? 0 : state.volume
        if state.isInUseElsewhere {
            label.stringValue = "Other Device"
        }
        else {
            label.stringValue = state.isMuted ? "Muted" : VolumePresentation.percent(state.volume)
        }

        positionOnPointerScreen()
        showGeneration += 1
        // A zero-length animation replaces a fade-out that may still be running.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()
        scheduleFadeOut()
    }

    // MARK: - Visibility

    private func scheduleFadeOut() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        let generation = showGeneration
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = Self.fadeDuration
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.showGeneration == generation else { return }
                    self.panel.orderOut(nil)
                }
            })
    }

    /// Centered horizontally on the screen with the pointer, above the bottom of its visible frame.
    private func positionOnPointerScreen() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - Self.size.width / 2, y: visible.minY + Self.bottomOffset))
    }

    // MARK: - Panel

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: true)
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        // The app is almost never active; the default would hide the panel right away.
        panel.hidesOnDeactivate = false

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)

        // The knob is a template image, so the tint gives it the HUD's label color in light and dark mode.
        imageView.contentTintColor = .labelColor
        label.font = .monospacedDigitSystemFont(ofSize: 20, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center

        let stack = NSStackView(views: [imageView, levelBar, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: background.centerYAnchor)
        ])

        panel.contentView = background
        return panel
    }

    /// The documented way to round an NSVisualEffectView: a stretchable mask with cap insets.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// The 16-segment level bar inside the overlay.
private final class LevelBar: NSView {
    private static let segments = 16
    private static let gap: CGFloat = 2

    var level: Float32 = 0 {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 160, height: 8)
    }

    override func draw(_ dirtyRect: NSRect) {
        let count = CGFloat(Self.segments)
        let width = (bounds.width - Self.gap * (count - 1)) / count
        let filled = Int((Double(level) * Double(Self.segments)).rounded())
        for index in 0 ..< Self.segments {
            let rect = NSRect(x: CGFloat(index) * (width + Self.gap), y: 0, width: width, height: bounds.height)
            let color = index < filled ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.2)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
