import AppKit

/// Menu bar icon and menu (Docs/DESIGN.md §5.2, §5.3, §7.5).
///
/// `update(audio:dial:isOutputEnabled:)` changes the icon and every menu line, so an open menu follows the Dial. The device
/// sections and the Input line come from a device list that runs only while the menu is open (§7.11).
final class StatusItemController: NSObject, NSMenuDelegate {
    private static let inputMonitoringSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    private static let iconSize: CGFloat = 18
    /// The slider lines up with the section headers; AppKit widens the row to the menu.
    private static let sliderRowWidth: CGFloat = 240
    private static let sliderInset = MenuInfoRow.inset
    private static let sliderVerticalPadding: CGFloat = 5

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
        didSet {
            self.updateInputRow()
        }
    }
    var iconStyle = KnobIcon.Style.arc {
        didSet {
            self.update(audio: self.audio, dial: self.dial, isOutputEnabled: self.isOutputEnabled)
        }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let dialItem = NSMenuItem()
    // A stored property initializer cannot name `self`, so the selector is unqualified here.
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

    override init() {
        super.init()
        self.buildMenu()
        self.deviceList.onChange = { [weak self] in
            self?.deviceListChanged()
        }
        self.update(audio: nil, dial: .notConnected, isOutputEnabled: true)
    }

    /// `isOutputEnabled` is false when the user excluded the current output in the Devices settings.
    func update(audio: AudioState?, dial: DialConnection, isOutputEnabled: Bool) -> Void {
        self.audio = audio
        self.dial = dial
        self.isOutputEnabled = isOutputEnabled
        // Titles are set on every change, not when the menu opens: turning the Dial or a retry started by opening the
        // menu must show while the menu is open.
        self.updateMenuItems()
        if let button = self.statusItem.button {
            self.updateButton(button)
        }
    }

    func setAccessDenied(_ isDenied: Bool) -> Void {
        self.accessItem.isHidden = isDenied == false
    }

    // MARK: - Menu

    private func buildMenu() -> Void {
        let menu = NSMenu()
        // Items are enabled by hand: the info lines stay disabled, the actions always work.
        menu.autoenablesItems = false
        menu.delegate = self

        let infoRows = [
            (self.dialItem, self.dialRow), (self.outputItem, self.outputRow), (self.inputItem, self.inputRow), (self.volumeItem, self.volumeRow)
        ]
        for (item, row) in infoRows {
            item.view = row
            item.isEnabled = false
        }
        self.inputRow.text = Self.inputTitle(nil, isKept: false)
        self.accessItem.target = self
        self.accessItem.isHidden = true
        self.muteItem.target = self
        self.muteItem.view = self.muteRow
        self.buildSliderItem()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(self.openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        let aboutItem = NSMenuItem(title: "About Feel the Noize", action: #selector(self.showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        let quitItem = NSMenuItem(title: "Quit Feel the Noize", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let items: [NSMenuItem] = [
            self.dialItem, self.accessItem, self.outputItem, self.inputItem, self.volumeItem, .separator(), self.volumeHeader, self.sliderItem,
            .separator(), self.muteItem, .separator(), settingsItem, aboutItem, .separator(), quitItem
        ]
        for item in items {
            menu.addItem(item)
        }
        self.statusItem.menu = menu
    }

    private func buildSliderItem() -> Void {
        let sliderHeight = VolumeSlider.trackHeight
        let row = NSView(frame: NSRect(x: 0, y: 0, width: Self.sliderRowWidth, height: sliderHeight + 2 * Self.sliderVerticalPadding))
        row.autoresizingMask = [.width]
        self.volumeSlider.frame = NSRect(
            x: Self.sliderInset, y: Self.sliderVerticalPadding, width: Self.sliderRowWidth - 2 * Self.sliderInset, height: sliderHeight)
        self.volumeSlider.autoresizingMask = [.width]
        self.volumeSlider.target = self
        self.volumeSlider.action = #selector(self.volumeSliderChanged(_:))
        self.volumeSlider.setAccessibilityLabel("Volume")
        row.addSubview(self.volumeSlider)
        self.sliderItem.view = row
    }

    func menuWillOpen(_ menu: NSMenu) -> Void {
        // Fills the device sections before the menu shows and keeps them current while it is open.
        self.deviceList.start()
        self.onMenuWillOpen?()
    }

    func menuDidClose(_ menu: NSMenu) -> Void {
        self.deviceList.stop()
    }

    private func updateButton(_ button: NSStatusBarButton) -> Void {
        var description = VolumePresentation.accessibilityDescription(for: self.audio)
        switch self.dial {
            case .connected:
                break
            case .notConnected:
                description += ", Surface Dial not connected"
            case .inUseElsewhere:
                description += ", Surface Dial in use by another app"
        }
        if self.isOutputEnabled == false {
            description += ", Dial off for this output"
        }
        button.image = VolumePresentation.knobImage(
            for: self.audio, style: self.iconStyle, size: Self.iconSize, accessibilityDescription: description)
        button.appearsDisabled = self.isButtonDisabled()
    }

    /// Dimmed where turning the Dial changes nothing: no Dial, no volume control, output owned elsewhere or excluded.
    private func isButtonDisabled() -> Bool {
        if self.dial != .connected {
            return true
        }
        if self.audio?.canSetVolume != true {
            return true
        }
        if self.audio?.isInUseElsewhere == true {
            return true
        }
        return self.isOutputEnabled == false
    }

    private func updateMenuItems() -> Void {
        self.updateDialRow()
        var outputSuffix = ""
        if self.audio != nil {
            if self.isOutputEnabled == false {
                outputSuffix = " (Dial off)"
            }
        }
        self.outputRow.text = "Output: \(self.audio?.deviceName ?? "None")\(outputSuffix)"

        switch self.audio {
            case .none:
                self.volumeRow.text = "Volume: –"
            case .some(let state) where state.canSetVolume == false:
                self.volumeRow.text = "Volume: not adjustable"
            case .some(let state) where state.isInUseElsewhere == true:
                self.volumeRow.text = "Volume: in use by another device"
            case .some(let state):
                let suffix = state.isSoftwareVolume == true ? " (software)" : ""
                self.volumeRow.text = "Volume: \(VolumePresentation.percent(state.volume))\(suffix)"
        }

        // Like the system Sound menu, the slider stands at zero while muted; a device without volume control shows its fixed
        // full level, disabled.
        self.volumeSlider.doubleValue = Double(self.audio.map { $0.isMuted == true ? 0 : $0.volume } ?? 0)
        self.volumeSlider.isEnabled = self.audio.map { $0.canSetVolume == true && $0.isInUseElsewhere == false } ?? false
        self.updateSliderSymbol()

        self.muteRow.isMuted = self.audio?.isMuted == true
        self.muteItem.title = MenuMuteRow.title(isMuted: self.muteRow.isMuted)
        self.muteItem.isEnabled = self.audio.map { $0.hasHardwareMute == true || $0.canSetVolume == true } ?? false
        self.muteRow.needsDisplay = true
    }

    // MARK: - Devices

    private func deviceListChanged() -> Void {
        self.updateInputRow()
        self.updateSliderSymbol()
        self.batteries = AccessoryBattery.read()
        self.updateDialRow()
        if let menu = self.statusItem.menu {
            self.rebuildDeviceItems(in: menu)
        }
    }

    private func rebuildDeviceItems(in menu: NSMenu) -> Void {
        for item in self.deviceItems {
            menu.removeItem(item)
        }
        let sections = Self.deviceSections(self.deviceList.devices)
        self.deviceItems =
            self.sectionItems(.output, devices: sections.outputs, defaultUID: self.deviceList.defaultOutputUID)
            + self.sectionItems(.input, devices: sections.inputs, defaultUID: self.deviceList.defaultInputUID)
        let start = menu.index(of: self.sliderItem) + 1
        for (offset, item) in self.deviceItems.enumerated() {
            menu.insertItem(item, at: start + offset)
        }
    }

    private func updateInputRow() -> Void {
        let defaultInput = self.deviceList.devices.first { $0.hasInput == true && $0.uid == self.deviceList.defaultInputUID }
        var isKept = false
        if let defaultInput = defaultInput {
            isKept = defaultInput.uid == self.keptInputUID
        }
        self.inputRow.text = Self.inputTitle(defaultInput?.name, isKept: isKept)
    }

    /// The device list knows the transport and model the symbol depends on; it runs while the menu is open, the only time
    /// the slider is visible.
    private func updateSliderSymbol() -> Void {
        let output = self.audio.flatMap { state in self.deviceList.devices.first { $0.uid == state.deviceUID } }
        self.volumeSlider.symbolName = DeviceIcon.sliderSymbolName(for: output)
    }

    /// A section without devices is left out entirely. As in the macOS Sound menu, the default device is marked by the accent
    /// circle of its icon, and its name is bold. The title stays set for type-to-select; the row view draws the item.
    private func sectionItems(_ direction: DeviceIcon.Direction, devices: [AudioDeviceInfo], defaultUID: String?) -> [NSMenuItem] {
        guard devices.isEmpty == false else {
            return []
        }
        let title: String
        let action: Selector
        let current: String
        switch direction {
            case .output:
                title = "Output"
                action = #selector(self.selectOutput(_:))
                current = "current output"
            case .input:
                title = "Input"
                action = #selector(self.selectInput(_:))
                current = "current input"
        }
        let items = devices.map { device in
            return self.menuItem(for: device, direction: direction, action: action, isDefault: device.uid == defaultUID, current: current)
        }
        return [.sectionHeader(title: title)] + items
    }

    private func menuItem(
        for device: AudioDeviceInfo, direction: DeviceIcon.Direction, action: Selector, isDefault: Bool, current: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: device.name, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = device.uid
        let battery = self.battery(for: device)
        let icon = DeviceIcon.image(
            symbolName: DeviceIcon.symbolName(for: device, direction: direction), isDefault: isDefault, accessibilityDescription: nil)
        let description = [device.name, isDefault == true ? current : nil, battery.map { "battery \($0.text)" }].compactMap(\.self)
        item.view = MenuDeviceRow(
            name: device.name, isDefault: isDefault, icon: icon, battery: battery.map { ($0.text, $0.singleLevel) },
            accessibilityLabel: description.joined(separator: ", "))
        return item
    }

    /// A device with output and input, such as AirPods, shows the same battery in both sections.
    private func battery(for device: AudioDeviceInfo) -> AccessoryBattery? {
        return AccessoryBattery.address(in: device.uid).flatMap { self.batteries.devices[$0] }
    }

    /// Both sections are sorted by name like the Devices tab; a device with output and input appears in both.
    static func deviceSections(_ devices: [AudioDeviceInfo]) -> (outputs: [AudioDeviceInfo], inputs: [AudioDeviceInfo]) {
        let sorted = devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (outputs: sorted.filter(\.hasOutput), inputs: sorted.filter(\.hasInput))
    }

    static func inputTitle(_ deviceName: String?, isKept: Bool) -> String {
        return "Input: \(deviceName ?? "None")\(isKept == true ? " (kept)" : "")"
    }

    // MARK: - Titles

    /// The battery level shows only while the Dial is connected; it is read when the menu opens, the only time the row is
    /// visible.
    private func updateDialRow() -> Void {
        self.dialRow.text = Self.title(for: self.dial)
        self.dialRow.batteryLevel = self.dial == .connected ? self.batteries.dialLevel : nil
    }

    static func title(for dial: DialConnection) -> String {
        switch dial {
            case .connected:
                return "Surface Dial: Connected"
            case .notConnected:
                return "Surface Dial: Not Connected"
            case .inUseElsewhere:
                return "Surface Dial: In Use by Another App"
        }
    }

    // MARK: - Actions

    @objc private func toggleMute(_ sender: NSMenuItem) -> Void {
        self.onToggleMute?()
    }

    @objc private func volumeSliderChanged(_ sender: NSSlider) -> Void {
        self.onSetVolume?(Float32(sender.doubleValue))
    }

    @objc private func selectOutput(_ sender: NSMenuItem) -> Void {
        guard let uid = sender.representedObject as? String else {
            return
        }
        self.onSelectOutput?(uid)
    }

    @objc private func selectInput(_ sender: NSMenuItem) -> Void {
        guard let uid = sender.representedObject as? String else {
            return
        }
        self.onSelectInput?(uid)
    }

    @objc private func openSettings(_ sender: NSMenuItem) -> Void {
        self.onOpenSettings?()
    }

    @objc private func showAbout(_ sender: NSMenuItem) -> Void {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openInputMonitoringSettings(_ sender: NSMenuItem) -> Void {
        guard let url = URL(string: Self.inputMonitoringSettingsURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
