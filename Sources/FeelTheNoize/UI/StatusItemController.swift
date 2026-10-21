import AppKit

/// Menu bar icon and menu (docs/DESIGN.md §5.2, §5.3, §7.5).
///
/// `update(audio:dial:isOutputEnabled:)` changes the icon and every menu line, so an open menu follows the Dial. The device
/// sections and the Input line come from a device list that runs only while the menu is open (§7.11).
final class StatusItemController: NSObject, NSMenuDelegate {
    private static let inputMonitoringSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    var onToggleMute: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    /// Lets the owner retry a Dial held by another process while the user looks at the menu.
    var onMenuWillOpen: (() -> Void)?
    /// Called with the UID of the device the user picked in the menu.
    var onSelectOutput: ((String) -> Void)?
    var onSelectInput: ((String) -> Void)?
    var iconStyle = KnobIcon.Style.arc {
        didSet { update(audio: audio, dial: dial, isOutputEnabled: isOutputEnabled) }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let dialItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let accessItem = NSMenuItem(title: "Allow Input Monitoring…", action: #selector(openInputMonitoringSettings(_:)), keyEquivalent: "")
    private let outputItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let inputItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let volumeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let muteItem = NSMenuItem(title: "Mute", action: #selector(toggleMute(_:)), keyEquivalent: "")
    /// The device sections are inserted right after this separator.
    private let deviceSeparator = NSMenuItem.separator()
    private let deviceList = AudioDeviceList()
    private var deviceItems: [NSMenuItem] = []
    private var audio: AudioState?
    private var dial = DialConnection.notConnected
    private var isOutputEnabled = true
    private var dialBatteryLevel: Int?
    /// The status lines at the top are information, not commands, so they use a smaller font than the menu items.
    private static let iconSize: CGFloat = 18
    private static let infoAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
        .foregroundColor: NSColor.secondaryLabelColor
    ]
    /// Device items are commands in the regular menu font; the default device of a section is bold.
    private static let deviceAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0)]
    private static let defaultDeviceAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize)
    ]

    override init() {
        super.init()
        buildMenu()
        deviceList.onChange = { [weak self] in
            self?.deviceListChanged()
        }
        update(audio: nil, dial: .notConnected, isOutputEnabled: true)
    }

    /// `isOutputEnabled` is false when the user excluded the current output in the Devices settings.
    func update(audio: AudioState?, dial: DialConnection, isOutputEnabled: Bool) {
        self.audio = audio
        self.dial = dial
        self.isOutputEnabled = isOutputEnabled
        // Titles are set on every change, not when the menu opens: turning the Dial or a retry started by opening the
        // menu must show while the menu is open.
        updateMenuItems()

        guard let button = statusItem.button else { return }
        var description = VolumePresentation.accessibilityDescription(for: audio)
        switch dial {
            case .connected: break
            case .notConnected: description += ", Surface Dial not connected"
            case .inUseElsewhere: description += ", Surface Dial in use by another app"
        }
        if !isOutputEnabled {
            description += ", Dial off for this output"
        }
        button.image = VolumePresentation.knobImage(for: audio, style: iconStyle, size: Self.iconSize, accessibilityDescription: description)
        button.appearsDisabled =
            dial != .connected || audio?.canSetVolume != true || audio?.isInUseElsewhere == true || !isOutputEnabled
    }

    /// `nil` while the level is unknown, for example right after the Dial connected.
    func setDialBatteryLevel(_ level: Int?) {
        dialBatteryLevel = level
        Self.setInfoTitle(dialItem, Self.title(for: dial, batteryLevel: level))
    }

    func setAccessDenied(_ isDenied: Bool) {
        accessItem.isHidden = !isDenied
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        // Items are enabled by hand: the info lines stay disabled, the actions always work.
        menu.autoenablesItems = false
        menu.delegate = self

        for infoItem in [dialItem, outputItem, inputItem, volumeItem] {
            infoItem.isEnabled = false
        }
        Self.setInfoTitle(inputItem, Self.inputTitle(nil))
        accessItem.target = self
        accessItem.isHidden = true
        muteItem.target = self

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        let aboutItem = NSMenuItem(title: "About Feel the Noize", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        let quitItem = NSMenuItem(title: "Quit Feel the Noize", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for item in [
            dialItem, accessItem, outputItem, inputItem, volumeItem, deviceSeparator, .separator(), muteItem, .separator(), settingsItem,
            aboutItem, .separator(), quitItem
        ] {
            menu.addItem(item)
        }
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Fills the device sections before the menu shows and keeps them current while it is open.
        deviceList.start()
        onMenuWillOpen?()
    }

    func menuDidClose(_ menu: NSMenu) {
        deviceList.stop()
    }

    private func updateMenuItems() {
        Self.setInfoTitle(dialItem, Self.title(for: dial, batteryLevel: dialBatteryLevel))
        let suffix = audio != nil && !isOutputEnabled ? " (Dial off)" : ""
        Self.setInfoTitle(outputItem, "Output: \(audio?.deviceName ?? "None")\(suffix)")

        switch audio {
            case .none:
                Self.setInfoTitle(volumeItem, "Volume: –")
            case .some(let state) where !state.canSetVolume:
                Self.setInfoTitle(volumeItem, "Volume: not adjustable")
            case .some(let state) where state.isInUseElsewhere:
                Self.setInfoTitle(volumeItem, "Volume: in use by another device")
            case .some(let state):
                let suffix = state.isSoftwareVolume ? " (software)" : ""
                Self.setInfoTitle(volumeItem, "Volume: \(VolumePresentation.percent(state.volume))\(suffix)")
        }

        muteItem.state = audio?.isMuted == true ? .on : .off
        muteItem.isEnabled = audio.map { $0.hasHardwareMute || $0.canSetVolume } ?? false
    }

    // MARK: - Devices

    private func deviceListChanged() {
        let defaultInput = deviceList.devices.first { $0.hasInput && $0.uid == deviceList.defaultInputUID }
        Self.setInfoTitle(inputItem, Self.inputTitle(defaultInput?.name))

        guard let menu = statusItem.menu else { return }
        for item in deviceItems {
            menu.removeItem(item)
        }
        let sections = Self.deviceSections(deviceList.devices)
        deviceItems =
            sectionItems("Output", devices: sections.outputs, defaultUID: deviceList.defaultOutputUID, action: #selector(selectOutput(_:)))
            + sectionItems("Input", devices: sections.inputs, defaultUID: deviceList.defaultInputUID, action: #selector(selectInput(_:)))
        let start = menu.index(of: deviceSeparator) + 1
        for (offset, item) in deviceItems.enumerated() {
            menu.insertItem(item, at: start + offset)
        }
        // Without any device the separator would double the one above Mute.
        deviceSeparator.isHidden = deviceItems.isEmpty
    }

    /// A section without devices is left out entirely.
    private func sectionItems(_ title: String, devices: [AudioDeviceInfo], defaultUID: String?, action: Selector) -> [NSMenuItem] {
        guard !devices.isEmpty else { return [] }
        let items = devices.map { device in
            let item = NSMenuItem(title: device.name, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            let attributes = device.uid == defaultUID ? Self.defaultDeviceAttributes : Self.deviceAttributes
            item.attributedTitle = NSAttributedString(string: device.name, attributes: attributes)
            return item
        }
        return [.sectionHeader(title: title)] + items
    }

    /// Both sections are sorted by name like the Devices tab; a device with output and input appears in both.
    static func deviceSections(_ devices: [AudioDeviceInfo]) -> (outputs: [AudioDeviceInfo], inputs: [AudioDeviceInfo]) {
        let sorted = devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (sorted.filter(\.hasOutput), sorted.filter(\.hasInput))
    }

    static func inputTitle(_ deviceName: String?) -> String {
        "Input: \(deviceName ?? "None")"
    }

    // MARK: - Titles

    static func title(for dial: DialConnection, batteryLevel: Int?) -> String {
        switch (dial, batteryLevel) {
            case (.connected, .some(let level)): "Surface Dial: Connected, battery \(level) %"
            case (.connected, .none): "Surface Dial: Connected"
            case (.notConnected, _): "Surface Dial: Not Connected"
            case (.inUseElsewhere, _): "Surface Dial: In Use by Another App"
        }
    }

    /// Always through the attributed title: setting `title` alone would leave a stale attributed title on screen.
    private static func setInfoTitle(_ item: NSMenuItem, _ text: String) {
        item.attributedTitle = NSAttributedString(string: text, attributes: infoAttributes)
    }

    // MARK: - Actions

    @objc private func toggleMute(_ sender: NSMenuItem) {
        onToggleMute?()
    }

    @objc private func selectOutput(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        onSelectOutput?(uid)
    }

    @objc private func selectInput(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        onSelectInput?(uid)
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        onOpenSettings?()
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openInputMonitoringSettings(_ sender: NSMenuItem) {
        guard let url = URL(string: Self.inputMonitoringSettingsURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
