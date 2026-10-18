import AppKit

/// The Devices settings tab (docs/DESIGN.md §7.6): every output device, what it supports, and whether the Dial may use it.
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

        var title: String {
            switch self {
                case .use: "Use"
                case .device: "Device"
                case .connection: "Connection"
                case .volume: "Volume Control"
                case .mute: "Mute"
            }
        }

        var width: CGFloat {
            switch self {
                case .use: 36
                case .device: 230
                case .connection: 100
                case .volume: 100
                case .mute: 70
            }
        }
    }

    private static let margin: CGFloat = 20
    private static let contentSize = NSSize(width: 620, height: 330)

    private let settings: Settings
    private let deviceList = AudioDeviceList()
    private let tableView = NSTableView()
    private var rows: [Row] = []

    init(settings: Settings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        title = "Devices"
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = column.width
            tableView.addTableColumn(tableColumn)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.selectionHighlightStyle = .none
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.style = .fullWidth
        tableView.rowHeight = 22

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let footnote = NSTextField(
            wrappingLabelWithString:
                "The Dial controls the current output only when it is ticked. Devices without volume control can only be muted.")
        footnote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        footnote.textColor = .secondaryLabelColor

        let container = NSView()
        for subview in [scrollView, footnote] {
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
            footnote.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.margin)
        ])
        view = container
        preferredContentSize = Self.contentSize

        deviceList.onChange = { [weak self] in
            self?.deviceListChanged()
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        deviceList.start()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        deviceList.stop()
    }

    // MARK: - Rows

    private func deviceListChanged() {
        let connected = deviceList.devices
        settings.rememberDevices(Dictionary(connected.map { ($0.uid, $0.name) }, uniquingKeysWith: { first, _ in first }))

        let connectedUIDs = Set(connected.map(\.uid))
        let connectedRows = connected.map { device in
            Row(uid: device.uid, name: device.name, device: device, isDefaultOutput: device.uid == deviceList.defaultDeviceUID)
        }
        let rememberedRows = settings.knownDevices.filter { !connectedUIDs.contains($0.key) }.map { uid, name in
            Row(uid: uid, name: name, device: nil, isDefaultOutput: false)
        }
        rows = Self.sortedByName(connectedRows) + Self.sortedByName(rememberedRows)
        tableView.reloadData()
    }

    private static func sortedByName(_ rows: [Row]) -> [Row] {
        rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier, let column = Column(rawValue: identifier.rawValue), rows.indices.contains(index) else {
            return nil
        }
        let row = rows[index]
        switch column {
            case .use:
                return useCheckbox(for: row, at: index)
            case .device:
                return deviceCell(for: row)
            case .connection:
                return textCell(row.device?.transport.label ?? "Not connected", row: row)
            case .volume:
                return textCell(row.device.map { $0.canSetVolume ? "Yes" : "No" } ?? "–", row: row)
            case .mute:
                return textCell(row.device.map(Self.muteLabel) ?? "–", row: row)
        }
    }

    private func useCheckbox(for row: Row, at index: Int) -> NSView {
        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleDevice(_:)))
        checkbox.tag = index
        // Remembered devices stay configurable; a connected device without volume and mute has nothing to control.
        let isControllable = row.device?.isControllable ?? true
        checkbox.isEnabled = isControllable
        checkbox.state = isControllable && settings.isDeviceEnabled(row.uid) ? .on : .off
        checkbox.setAccessibilityLabel("Use \(row.name)")
        return Self.centered(checkbox)
    }

    private func deviceCell(for row: Row) -> NSView {
        let marker = NSImageView()
        if row.isDefaultOutput {
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
        Self.leadingCentered(Self.label(text, row: row))
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
        if device.hasHardwareMute {
            return "Yes"
        }
        // AudioOutput emulates mute through the volume when the device has no mute control (§7.4).
        return device.canSetVolume ? "Emulated" : "No"
    }

    // MARK: - Actions

    @objc private func toggleDevice(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag) else { return }
        settings.setDevice(rows[sender.tag].uid, enabled: sender.state == .on)
    }
}
