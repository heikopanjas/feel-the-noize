import AppKit

/// The General settings tab from docs/DESIGN.md §7.6. Every change applies immediately.
final class GeneralSettingsViewController: NSViewController {
    private static let margin: CGFloat = 20

    private let settings: Settings
    private let detentsPopUp = NSPopUpButton()
    private let stepPopUp = NSPopUpButton()
    private let reverseCheckbox = NSButton(checkboxWithTitle: "Reverse direction", target: nil, action: nil)
    private let hapticsCheckbox = NSButton(checkboxWithTitle: "Haptic detents", target: nil, action: nil)
    private let overlayCheckbox = NSButton(checkboxWithTitle: "Show volume overlay", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let approvalLabel = NSTextField(labelWithString: "Launching at login needs your approval.")
    private let approvalButton = NSButton(title: "Open Login Items…", target: nil, action: nil)
    private var approvalRow: NSGridRow?

    init(settings: Settings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        title = "General"
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        configureControls()

        let approvalStack = NSStackView(views: [approvalLabel, approvalButton])
        approvalStack.orientation = .vertical
        approvalStack.alignment = .leading
        approvalStack.spacing = 6

        let grid = NSGridView(views: [
            [Self.label("Detents per turn:"), detentsPopUp],
            [Self.label("Volume step:"), stepPopUp],
            [NSGridCell.emptyContentView, reverseCheckbox],
            [NSGridCell.emptyContentView, hapticsCheckbox],
            [NSGridCell.emptyContentView, overlayCheckbox],
            [NSGridCell.emptyContentView, loginCheckbox],
            [NSGridCell.emptyContentView, approvalStack]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.row(at: 2).topPadding = 8
        approvalRow = grid.row(at: 6)

        let container = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.margin),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.margin),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.margin),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.margin)
        ])
        view = container
    }

    /// Launch at login can change in System Settings, so the controls are re-read every time the window appears.
    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    // MARK: - Controls

    private func configureControls() {
        for detents in Settings.detentChoices {
            detentsPopUp.addItem(withTitle: "\(detents)")
            detentsPopUp.lastItem?.tag = detents
        }
        for percent in Settings.stepPercentChoices {
            stepPopUp.addItem(withTitle: "\(percent) %")
            stepPopUp.lastItem?.tag = percent
        }

        let actions: [(NSControl, Selector)] = [
            (detentsPopUp, #selector(detentsChanged(_:))), (stepPopUp, #selector(stepChanged(_:))),
            (reverseCheckbox, #selector(reverseChanged(_:))), (hapticsCheckbox, #selector(hapticsChanged(_:))),
            (overlayCheckbox, #selector(overlayChanged(_:))), (loginCheckbox, #selector(loginChanged(_:))),
            (approvalButton, #selector(openLoginItems(_:)))
        ]
        for (control, action) in actions {
            control.target = self
            control.action = action
        }

        approvalLabel.textColor = .secondaryLabelColor
        approvalLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        approvalButton.controlSize = .small
    }

    private func refresh() {
        detentsPopUp.selectItem(withTag: settings.detentsPerRevolution)
        stepPopUp.selectItem(withTag: settings.volumeStepPercent)
        reverseCheckbox.state = settings.reverseDirection ? .on : .off
        hapticsCheckbox.state = settings.hapticDetents ? .on : .off
        overlayCheckbox.state = settings.showOverlay ? .on : .off
        loginCheckbox.state = LoginItem.isEnabled ? .on : .off
        approvalRow?.isHidden = LoginItem.status != .requiresApproval
        // The tab view sizes the window from this; without it the grid is stretched to a default size.
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    private static func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    // MARK: - Actions

    @objc private func detentsChanged(_ sender: NSPopUpButton) {
        settings.detentsPerRevolution = sender.selectedTag()
    }

    @objc private func stepChanged(_ sender: NSPopUpButton) {
        settings.volumeStepPercent = sender.selectedTag()
    }

    @objc private func reverseChanged(_ sender: NSButton) {
        settings.reverseDirection = sender.state == .on
    }

    @objc private func hapticsChanged(_ sender: NSButton) {
        settings.hapticDetents = sender.state == .on
    }

    @objc private func overlayChanged(_ sender: NSButton) {
        settings.showOverlay = sender.state == .on
    }

    @objc private func loginChanged(_ sender: NSButton) {
        LoginItem.setEnabled(sender.state == .on)
        refresh()
    }

    @objc private func openLoginItems(_ sender: NSButton) {
        LoginItem.openSystemSettings()
    }
}
