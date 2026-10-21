import AppKit

/// The Devices settings tab (Docs/DESIGN.md §7.6): every output device, what it supports, and whether the Dial may use it,
/// and the input device to keep (§7.13).
///
/// Connected devices come first, then remembered ones that are absent right now. The device list is observed only while
/// the tab is visible.
final class DeviceSettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private struct Row {
        let uid: String
        let name: String
        /// `nil` for a remembered device that is not connected.
        let device: AudioDeviceInfo?
        let isDefaultOutput: Bool
    }

    private enum Column: String, CaseIterable {
        case use
        case device
        case connection
        case volume
        case mute
        case software

        var title: String {
            switch self {
                case .use:
                    return "Use"
                case .device:
                    return "Device"
                case .connection:
                    return "Connection"
                case .volume:
                    return "Volume Control"
                case .mute:
                    return "Mute"
                case .software:
                    return "Software Volume"
            }
        }

        var width: CGFloat {
            switch self {
                case .use:
                    return 36
                case .device:
                    return 200
                case .connection:
                    return 100
                case .volume:
                    return 100
                case .mute:
                    return 70
                case .software:
                    return 110
            }
        }
    }

    private static let margin: CGFloat = 20
    private static let contentSize = NSSize(width: 740, height: 430)
    private static let offTitle = "Off"

    private let settings: Settings
    private let deviceList = AudioDeviceList()
    private let tableView = NSTableView()
    private let keepPopup = NSPopUpButton()
    private var rows: [Row] = []

    init(settings: Settings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        self.title = "Devices"
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() -> Void {
        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = column.width
            self.tableView.addTableColumn(tableColumn)
        }
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.usesAlternatingRowBackgroundColors = true
        self.tableView.selectionHighlightStyle = .none
        self.tableView.allowsColumnReordering = false
        self.tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        self.tableView.style = .fullWidth
        self.tableView.rowHeight = 22

        let scrollView = NSScrollView()
        scrollView.documentView = self.tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let footnote = NSTextField(
            wrappingLabelWithString:
                "The Dial controls the current output only when it is ticked under Use. For devices without volume control, Software "
                + "Volume adjusts the audio sent to them; it needs permission to record system audio and adds a few milliseconds "
                + "of latency.")
        footnote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        footnote.textColor = .secondaryLabelColor

        let keepLabel = NSTextField(labelWithString: "Keep input device:")
        self.keepPopup.target = self
        self.keepPopup.action = #selector(self.keepInputChanged(_:))
        self.keepPopup.setAccessibilityLabel("Keep input device")
        let keepRow = NSStackView(views: [keepLabel, self.keepPopup])
        keepRow.spacing = 8
        let keepFootnote = NSTextField(
            wrappingLabelWithString:
                "While this device is connected, Feel the Noize switches the input back to it whenever another device takes over. "
                + "Choosing an input in the menu moves the keep to that device.")
        keepFootnote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        keepFootnote.textColor = .secondaryLabelColor

        let container = NSView()
        for subview in [scrollView, footnote, keepRow, keepFootnote] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.contentSize.width),
            container.heightAnchor.constraint(equalToConstant: Self.contentSize.height),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.margin),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.margin),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.margin),
            footnote.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            footnote.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            footnote.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            keepRow.topAnchor.constraint(equalTo: footnote.bottomAnchor, constant: 20),
            keepRow.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            keepFootnote.topAnchor.constraint(equalTo: keepRow.bottomAnchor, constant: 8),
            keepFootnote.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            keepFootnote.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            keepFootnote.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.margin)
        ])
        self.view = container
        self.preferredContentSize = Self.contentSize

        self.deviceList.onChange = { [weak self] in
            self?.deviceListChanged()
        }
    }

    override func viewWillAppear() -> Void {
        super.viewWillAppear()
        self.deviceList.start()
    }

    override func viewDidDisappear() -> Void {
        super.viewDidDisappear()
        self.deviceList.stop()
    }

    // MARK: - Rows

    private func deviceListChanged() -> Void {
        // The list also carries inputs for the status menu; this tab is about outputs only.
        let connected = self.deviceList.devices.filter(\.hasOutput)
        self.settings.rememberDevices(Dictionary(connected.map { ($0.uid, $0.name) }, uniquingKeysWith: { first, _ in first }))

        let connectedUIDs = Set(connected.map(\.uid))
        let connectedRows = connected.map { device in
            return Row(uid: device.uid, name: device.name, device: device, isDefaultOutput: device.uid == self.deviceList.defaultOutputUID)
        }
        let rememberedRows = self.settings.knownDevices.filter { connectedUIDs.contains($0.key) == false }.map { uid, name in
            return Row(uid: uid, name: name, device: nil, isDefaultOutput: false)
        }
        self.rows = Self.sortedByName(connectedRows) + Self.sortedByName(rememberedRows)
        self.tableView.reloadData()

        let inputs = self.deviceList.devices.filter(\.hasInput)
        self.settings.rememberInputDevices(Dictionary(inputs.map { ($0.uid, $0.name) }, uniquingKeysWith: { first, _ in first }))
        self.rebuildKeepPopup(inputs: inputs)
    }

    // MARK: - Kept Input

    private func rebuildKeepPopup(inputs: [AudioDeviceInfo]) -> Void {
        let keptUID = self.settings.keptInputDeviceUID
        self.keepPopup.removeAllItems()
        let off = NSMenuItem(title: Self.offTitle, action: nil, keyEquivalent: "")
        self.keepPopup.menu?.addItem(off)
        let choices = Self.keepChoices(inputs: inputs, keptUID: keptUID, knownNames: self.settings.knownInputDevices)
        if choices.isEmpty == false {
            self.keepPopup.menu?.addItem(.separator())
        }
        for choice in choices {
            let item = NSMenuItem(title: choice.title, action: nil, keyEquivalent: "")
            item.representedObject = choice.uid
            self.keepPopup.menu?.addItem(item)
            if choice.uid == keptUID {
                self.keepPopup.select(item)
            }
        }
        if keptUID == nil {
            self.keepPopup.select(off)
        }
    }

    /// Connected inputs sorted by name, then the kept device marked as not connected while it is absent, so the popup can
    /// still show it.
    static func keepChoices(inputs: [AudioDeviceInfo], keptUID: String?, knownNames: [String: String]) -> [(uid: String, title: String)] {
        let connected = inputs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map { (uid: $0.uid, title: $0.name) }
        if let keptUID = keptUID {
            if connected.contains(where: { $0.uid == keptUID }) == false {
                return connected + [(uid: keptUID, title: "\(knownNames[keptUID] ?? keptUID) (not connected)")]
            }
        }
        return connected
    }

    private static func sortedByName(_ rows: [Row]) -> [Row] {
        return rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier else {
            return nil
        }
        guard let column = Column(rawValue: identifier.rawValue) else {
            return nil
        }
        guard self.rows.indices.contains(index) else {
            return nil
        }
        let row = self.rows[index]
        switch column {
            case .use:
                return self.useCheckbox(for: row, at: index)
            case .device:
                return self.deviceCell(for: row)
            case .connection:
                return self.textCell(row.device?.transport.label ?? "Not connected", row: row)
            case .volume:
                return self.textCell(row.device.map { $0.canSetVolume == true ? "Yes" : "No" } ?? "–", row: row)
            case .mute:
                return self.textCell(row.device.map(Self.muteLabel) ?? "–", row: row)
            case .software:
                return self.softwareVolumeCheckbox(for: row, at: index)
        }
    }

    private func useCheckbox(for row: Row, at index: Int) -> NSView {
        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(self.toggleDevice(_:)))
        checkbox.tag = index
        // Every device can be selected: one without volume control can still get software volume.
        checkbox.state = self.settings.isDeviceEnabled(row.uid) == true ? .on : .off
        checkbox.setAccessibilityLabel("Use \(row.name)")
        return Self.centered(checkbox)
    }

    private func softwareVolumeCheckbox(for row: Row, at index: Int) -> NSView {
        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(self.toggleSoftwareVolume(_:)))
        checkbox.tag = index
        // Only for connected devices without volume control; remembered devices show their stored choice.
        checkbox.isEnabled = row.device.map { $0.canSetVolume == false } ?? false
        checkbox.state = self.settings.softwareVolumeDeviceUIDs.contains(row.uid) == true ? .on : .off
        checkbox.setAccessibilityLabel("Software volume for \(row.name)")
        return Self.centered(checkbox)
    }

    private func deviceCell(for row: Row) -> NSView {
        let marker = NSImageView()
        if row.isDefaultOutput == true {
            marker.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Current output")
            marker.contentTintColor = .controlAccentColor
            marker.toolTip = "Current output"
        }
        marker.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let label = Self.label(row.name, row: row)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [marker, label])
        stack.spacing = 4
        return Self.leadingCentered(stack)
    }

    private func textCell(_ text: String, row: Row) -> NSView {
        return Self.leadingCentered(Self.label(text, row: row))
    }

    private static func label(_ text: String, row: Row) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = row.device == nil ? .secondaryLabelColor : .labelColor
        return label
    }

    private static func centered(_ view: NSView) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    /// A bare label as cell view is drawn at the top of the row; this centers it vertically.
    private static func leadingCentered(_ view: NSView) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private static func muteLabel(_ device: AudioDeviceInfo) -> String {
        if device.hasHardwareMute == true {
            return "Yes"
        }
        // AudioOutput emulates mute through the volume when the device has no mute control (§7.4).
        return device.canSetVolume == true ? "Emulated" : "No"
    }

    // MARK: - Actions

    @objc private func toggleDevice(_ sender: NSButton) -> Void {
        guard self.rows.indices.contains(sender.tag) else {
            return
        }
        self.settings.setDevice(self.rows[sender.tag].uid, enabled: sender.state == .on)
    }

    @objc private func keepInputChanged(_ sender: NSPopUpButton) -> Void {
        self.settings.keptInputDeviceUID = sender.selectedItem?.representedObject as? String
    }

    @objc private func toggleSoftwareVolume(_ sender: NSButton) -> Void {
        guard self.rows.indices.contains(sender.tag) else {
            return
        }
        self.settings.setSoftwareVolume(self.rows[sender.tag].uid, enabled: sender.state == .on)
    }
}
