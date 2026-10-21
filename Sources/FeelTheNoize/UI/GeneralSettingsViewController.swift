import AppKit

/// The General settings tab from Docs/DESIGN.md §7.6. Every change applies immediately.
final class GeneralSettingsViewController: NSViewController {
    private static let margin: CGFloat = 20

    private let settings: Settings
    private let detentsPopUp = NSPopUpButton()
    private let stepPopUp = NSPopUpButton()
    private let iconStylePopUp = NSPopUpButton()
    private let reverseCheckbox = NSButton(checkboxWithTitle: "Reverse direction", target: nil, action: nil)
    private let hapticsCheckbox = NSButton(checkboxWithTitle: "Haptic detents", target: nil, action: nil)
    private let keepAwakeCheckbox = NSButton(checkboxWithTitle: "Keep Dial awake while the Mac is in use", target: nil, action: nil)
    private let overlayCheckbox = NSButton(checkboxWithTitle: "Show volume overlay", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let approvalLabel = NSTextField(labelWithString: "Launching at login needs your approval.")
    private let approvalButton = NSButton(title: "Open Login Items…", target: nil, action: nil)
    private var approvalRow: NSGridRow?

    init(settings: Settings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        self.title = "General"
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() -> Void {
        self.configureControls()

        let approvalStack = NSStackView(views: [self.approvalLabel, self.approvalButton])
        approvalStack.orientation = .vertical
        approvalStack.alignment = .leading
        approvalStack.spacing = 6

        let grid = NSGridView(views: [
            [Self.label("Detents per turn:"), self.detentsPopUp],
            [Self.label("Volume step:"), self.stepPopUp],
            [Self.label("Icon style:"), self.iconStylePopUp],
            [NSGridCell.emptyContentView, self.reverseCheckbox],
            [NSGridCell.emptyContentView, self.hapticsCheckbox],
            [NSGridCell.emptyContentView, self.keepAwakeCheckbox],
            [NSGridCell.emptyContentView, self.overlayCheckbox],
            [NSGridCell.emptyContentView, self.loginCheckbox],
            [NSGridCell.emptyContentView, approvalStack]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.row(at: 3).topPadding = 8
        self.approvalRow = grid.row(at: 8)

        let container = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.margin),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.margin),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.margin),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.margin)
        ])
        self.view = container
    }

    /// Launch at login can change in System Settings, so the controls are re-read every time the window appears.
    override func viewWillAppear() -> Void {
        super.viewWillAppear()
        self.refresh()
    }

    // MARK: - Controls

    private func configureControls() -> Void {
        for detents in Settings.detentChoices {
            self.detentsPopUp.addItem(withTitle: "\(detents)")
            self.detentsPopUp.lastItem?.tag = detents
        }
        for (index, style) in KnobIcon.Style.allCases.enumerated() {
            self.iconStylePopUp.addItem(withTitle: style.title)
            self.iconStylePopUp.lastItem?.tag = index
            self.iconStylePopUp.lastItem?.image = KnobIcon.image(style: style, level: 0.6, isMuted: false, size: 16, accessibilityDescription: nil)
        }
        for percent in Settings.stepPercentChoices {
            self.stepPopUp.addItem(withTitle: "\(percent) %")
            self.stepPopUp.lastItem?.tag = percent
        }

        let actions: [(NSControl, Selector)] = [
            (self.detentsPopUp, #selector(self.detentsChanged(_:))), (self.stepPopUp, #selector(self.stepChanged(_:))),
            (self.iconStylePopUp, #selector(self.iconStyleChanged(_:))),
            (self.reverseCheckbox, #selector(self.reverseChanged(_:))), (self.hapticsCheckbox, #selector(self.hapticsChanged(_:))),
            (self.keepAwakeCheckbox, #selector(self.keepAwakeChanged(_:))),
            (self.overlayCheckbox, #selector(self.overlayChanged(_:))), (self.loginCheckbox, #selector(self.loginChanged(_:))),
            (self.approvalButton, #selector(self.openLoginItems(_:)))
        ]
        for (control, action) in actions {
            control.target = self
            control.action = action
        }

        self.approvalLabel.textColor = .secondaryLabelColor
        self.approvalLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        self.approvalButton.controlSize = .small
    }

    private func refresh() -> Void {
        self.detentsPopUp.selectItem(withTag: self.settings.detentsPerRevolution)
        self.stepPopUp.selectItem(withTag: self.settings.volumeStepPercent)
        self.iconStylePopUp.selectItem(withTag: KnobIcon.Style.allCases.firstIndex(of: self.settings.iconStyle) ?? 0)
        self.reverseCheckbox.state = self.settings.reverseDirection == true ? .on : .off
        self.hapticsCheckbox.state = self.settings.hapticDetents == true ? .on : .off
        self.keepAwakeCheckbox.state = self.settings.keepDialAwake == true ? .on : .off
        self.overlayCheckbox.state = self.settings.showOverlay == true ? .on : .off
        self.loginCheckbox.state = LoginItem.isEnabled == true ? .on : .off
        self.approvalRow?.isHidden = LoginItem.status != .requiresApproval
        // The tab view sizes the window from this; without it the grid is stretched to a default size.
        self.view.layoutSubtreeIfNeeded()
        self.preferredContentSize = self.view.fittingSize
    }

    private static func label(_ text: String) -> NSTextField {
        return NSTextField(labelWithString: text)
    }

    // MARK: - Actions

    @objc private func detentsChanged(_ sender: NSPopUpButton) -> Void {
        self.settings.detentsPerRevolution = sender.selectedTag()
    }

    @objc private func iconStyleChanged(_ sender: NSPopUpButton) -> Void {
        let styles = KnobIcon.Style.allCases
        if styles.indices.contains(sender.selectedTag()) == true {
            self.settings.iconStyle = styles[sender.selectedTag()]
        }
    }

    @objc private func stepChanged(_ sender: NSPopUpButton) -> Void {
        self.settings.volumeStepPercent = sender.selectedTag()
    }

    @objc private func reverseChanged(_ sender: NSButton) -> Void {
        self.settings.reverseDirection = sender.state == .on
    }

    @objc private func hapticsChanged(_ sender: NSButton) -> Void {
        self.settings.hapticDetents = sender.state == .on
    }

    @objc private func keepAwakeChanged(_ sender: NSButton) -> Void {
        self.settings.keepDialAwake = sender.state == .on
    }

    @objc private func overlayChanged(_ sender: NSButton) -> Void {
        self.settings.showOverlay = sender.state == .on
    }

    @objc private func loginChanged(_ sender: NSButton) -> Void {
        LoginItem.setEnabled(sender.state == .on)
        self.refresh()
    }

    @objc private func openLoginItems(_ sender: NSButton) -> Void {
        LoginItem.openSystemSettings()
    }
}
