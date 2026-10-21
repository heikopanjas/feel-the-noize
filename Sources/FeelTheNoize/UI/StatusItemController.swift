import AppKit

/// Menu bar icon and menu (docs/DESIGN.md §5.2, §5.3, §7.5).
///
/// `update(audio:dial:isOutputEnabled:)` changes the icon and every menu line, so an open menu follows the Dial. The device
/// sections and the Input line come from a device list that runs only while the menu is open (§7.11).
final class StatusItemController: NSObject, NSMenuDelegate {
    private static let inputMonitoringSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    var onToggleMute: (() -> Void)?
    /// Called continuously while the volume slider moves, with the new volume 0…1.
    var onSetVolume: ((Float32) -> Void)?
    var onOpenSettings: (() -> Void)?
    /// Lets the owner retry a Dial held by another process while the user looks at the menu.
    var onMenuWillOpen: (() -> Void)?
    /// Called with the UID of the device the user picked in the menu.
    var onSelectOutput: ((String) -> Void)?
    var onSelectInput: ((String) -> Void)?
    /// The input device Feel the Noize keeps (§7.13); the Input line marks it.
    var keptInputUID: String? {
        didSet { updateInputRow() }
    }
    var iconStyle = KnobIcon.Style.arc {
        didSet { update(audio: audio, dial: dial, isOutputEnabled: isOutputEnabled) }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let dialItem = NSMenuItem()
    private let accessItem = NSMenuItem(title: "Allow Input Monitoring…", action: #selector(openInputMonitoringSettings(_:)), keyEquivalent: "")
    private let outputItem = NSMenuItem()
    private let inputItem = NSMenuItem()
    private let volumeItem = NSMenuItem()
    private let dialRow = MenuInfoRow()
    private let outputRow = MenuInfoRow()
    private let inputRow = MenuInfoRow()
    private let volumeRow = MenuInfoRow()
    private let muteItem = NSMenuItem(title: "Mute", action: #selector(toggleMute(_:)), keyEquivalent: "")
    private let muteRow = MenuMuteRow()
    /// A section header like Output and Input, so all three share the system style.
    private let volumeHeader = NSMenuItem.sectionHeader(title: "Volume")
    private let volumeSlider = VolumeSlider()
    /// The device sections are inserted right after the slider.
    private let sliderItem = NSMenuItem()
    private let deviceList = AudioDeviceList()
    private var deviceItems: [NSMenuItem] = []
    /// Read with every device list change while the menu is open (§7.10, §7.12).
    private var batteries = AccessoryBattery.Readings()
    private var audio: AudioState?
    private var dial = DialConnection.notConnected
    private var isOutputEnabled = true
    private static let iconSize: CGFloat = 18
    /// The slider lines up with the section headers; AppKit widens the row to the menu.
    private static let sliderRowWidth: CGFloat = 240
    private static let sliderInset = MenuInfoRow.inset
    private static let sliderVerticalPadding: CGFloat = 5

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

    func setAccessDenied(_ isDenied: Bool) {
        accessItem.isHidden = !isDenied
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        // Items are enabled by hand: the info lines stay disabled, the actions always work.
        menu.autoenablesItems = false
        menu.delegate = self

        for (item, row) in [(dialItem, dialRow), (outputItem, outputRow), (inputItem, inputRow), (volumeItem, volumeRow)] {
            item.view = row
            item.isEnabled = false
        }
        inputRow.text = Self.inputTitle(nil, isKept: false)
        accessItem.target = self
        accessItem.isHidden = true
        muteItem.target = self
        muteItem.view = muteRow
        buildSliderItem()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        let aboutItem = NSMenuItem(title: "About Feel the Noize", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        let quitItem = NSMenuItem(title: "Quit Feel the Noize", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for item in [
            dialItem, accessItem, outputItem, inputItem, volumeItem, .separator(), volumeHeader, sliderItem, .separator(), muteItem, .separator(),
            settingsItem, aboutItem, .separator(), quitItem
        ] {
            menu.addItem(item)
        }
        statusItem.menu = menu
    }

    private func buildSliderItem() {
        let sliderHeight = VolumeSlider.trackHeight
        let row = NSView(frame: NSRect(x: 0, y: 0, width: Self.sliderRowWidth, height: sliderHeight + 2 * Self.sliderVerticalPadding))
        row.autoresizingMask = [.width]
        volumeSlider.frame = NSRect(
            x: Self.sliderInset, y: Self.sliderVerticalPadding, width: Self.sliderRowWidth - 2 * Self.sliderInset, height: sliderHeight)
        volumeSlider.autoresizingMask = [.width]
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeSliderChanged(_:))
        volumeSlider.setAccessibilityLabel("Volume")
        row.addSubview(volumeSlider)
        sliderItem.view = row
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
        updateDialRow()
        let suffix = audio != nil && !isOutputEnabled ? " (Dial off)" : ""
        outputRow.text = "Output: \(audio?.deviceName ?? "None")\(suffix)"

        switch audio {
            case .none:
                volumeRow.text = "Volume: –"
            case .some(let state) where !state.canSetVolume:
                volumeRow.text = "Volume: not adjustable"
            case .some(let state) where state.isInUseElsewhere:
                volumeRow.text = "Volume: in use by another device"
            case .some(let state):
                let suffix = state.isSoftwareVolume ? " (software)" : ""
                volumeRow.text = "Volume: \(VolumePresentation.percent(state.volume))\(suffix)"
        }

        // Like the system Sound menu, the slider stands at zero while muted; a device without volume control shows its fixed
        // full level, disabled.
        volumeSlider.doubleValue = Double(audio.map { $0.isMuted ? 0 : $0.volume } ?? 0)
        volumeSlider.isEnabled = audio.map { $0.canSetVolume && !$0.isInUseElsewhere } ?? false
        updateSliderSymbol()

        muteRow.isMuted = audio?.isMuted == true
        muteItem.isEnabled = audio.map { $0.hasHardwareMute || $0.canSetVolume } ?? false
        muteRow.needsDisplay = true
    }

    // MARK: - Devices

    private func deviceListChanged() {
        updateInputRow()
        updateSliderSymbol()

        guard let menu = statusItem.menu else { return }
        for item in deviceItems {
            menu.removeItem(item)
        }
        batteries = AccessoryBattery.read()
        updateDialRow()
        let sections = Self.deviceSections(deviceList.devices)
        deviceItems =
            sectionItems(.output, devices: sections.outputs, defaultUID: deviceList.defaultOutputUID)
            + sectionItems(.input, devices: sections.inputs, defaultUID: deviceList.defaultInputUID)
        let start = menu.index(of: sliderItem) + 1
        for (offset, item) in deviceItems.enumerated() {
            menu.insertItem(item, at: start + offset)
        }
    }

    private func updateInputRow() {
        let defaultInput = deviceList.devices.first { $0.hasInput && $0.uid == deviceList.defaultInputUID }
        inputRow.text = Self.inputTitle(defaultInput?.name, isKept: defaultInput != nil && defaultInput?.uid == keptInputUID)
    }

    /// The device list knows the transport and model the symbol depends on; it runs while the menu is open, the only time
    /// the slider is visible.
    private func updateSliderSymbol() {
        let output = audio.flatMap { state in deviceList.devices.first { $0.uid == state.deviceUID } }
        volumeSlider.symbolName = DeviceIcon.sliderSymbolName(for: output)
    }

    /// A section without devices is left out entirely. As in the macOS Sound menu, the default device is marked by the accent
    /// circle of its icon, and its name is bold. The title stays set for type-to-select; the row view draws the item.
    private func sectionItems(_ direction: DeviceIcon.Direction, devices: [AudioDeviceInfo], defaultUID: String?) -> [NSMenuItem] {
        guard !devices.isEmpty else { return [] }
        let (title, action, current) =
            switch direction {
                case .output: ("Output", #selector(selectOutput(_:)), "current output")
                case .input: ("Input", #selector(selectInput(_:)), "current input")
            }
        let items = devices.map { device in
            let item = NSMenuItem(title: device.name, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            let isDefault = device.uid == defaultUID
            let battery = battery(for: device)
            let icon = DeviceIcon.image(
                symbolName: DeviceIcon.symbolName(for: device, direction: direction), isDefault: isDefault, accessibilityDescription: nil)
            let description = [device.name, isDefault ? current : nil, battery.map { "battery \($0.text)" }].compactMap(\.self)
            item.view = MenuDeviceRow(
                name: device.name, isDefault: isDefault, icon: icon, battery: battery.map { ($0.text, $0.singleLevel) },
                accessibilityLabel: description.joined(separator: ", "))
            return item
        }
        return [.sectionHeader(title: title)] + items
    }

    /// A device with output and input, such as AirPods, shows the same battery in both sections.
    private func battery(for device: AudioDeviceInfo) -> AccessoryBattery? {
        AccessoryBattery.address(in: device.uid).flatMap { batteries.devices[$0] }
    }

    /// Both sections are sorted by name like the Devices tab; a device with output and input appears in both.
    static func deviceSections(_ devices: [AudioDeviceInfo]) -> (outputs: [AudioDeviceInfo], inputs: [AudioDeviceInfo]) {
        let sorted = devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (sorted.filter(\.hasOutput), sorted.filter(\.hasInput))
    }

    static func inputTitle(_ deviceName: String?, isKept: Bool) -> String {
        "Input: \(deviceName ?? "None")\(isKept ? " (kept)" : "")"
    }

    // MARK: - Titles

    /// The battery level shows only while the Dial is connected; it is read when the menu opens, the only time the row is
    /// visible.
    private func updateDialRow() {
        dialRow.text = Self.title(for: dial)
        dialRow.batteryLevel = dial == .connected ? batteries.dialLevel : nil
    }

    static func title(for dial: DialConnection) -> String {
        switch dial {
            case .connected: "Surface Dial: Connected"
            case .notConnected: "Surface Dial: Not Connected"
            case .inUseElsewhere: "Surface Dial: In Use by Another App"
        }
    }

    // MARK: - Actions

    @objc private func toggleMute(_ sender: NSMenuItem) {
        onToggleMute?()
    }

    @objc private func volumeSliderChanged(_ sender: NSSlider) {
        onSetVolume?(Float32(sender.doubleValue))
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
