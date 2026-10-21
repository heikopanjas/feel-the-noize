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
    private let volumeSlider = VolumeSlider()
    /// The device sections are inserted right after the slider.
    private let sliderItem = NSMenuItem()
    private let deviceList = AudioDeviceList()
    private var deviceItems: [NSMenuItem] = []
    private var audio: AudioState?
    private var dial = DialConnection.notConnected
    private var isOutputEnabled = true
    private var dialBatteryLevel: Int?
    /// The status lines at the top are information, not commands, so they use a smaller font than the menu items.
    private static let iconSize: CGFloat = 18
    /// Slider row measured on the macOS Sound menu: a bold heading above the slider, both lined up with the section
    /// headers. AppKit widens the row to the menu.
    private static let sliderRowWidth: CGFloat = 240
    private static let sliderInset: CGFloat = 14
    private static let sliderBottomPadding: CGFloat = 8
    private static let headingSpacing: CGFloat = 6
    private static let headingTopPadding: CGFloat = 2
    private static let infoAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
        .foregroundColor: NSColor.secondaryLabelColor
    ]
    /// The default device of a section is also bold, in addition to the accent circle of its icon.
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
        buildSliderItem()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        let aboutItem = NSMenuItem(title: "About Feel the Noize", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        let quitItem = NSMenuItem(title: "Quit Feel the Noize", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for item in [
            dialItem, accessItem, outputItem, inputItem, volumeItem, .separator(), sliderItem, .separator(), muteItem, .separator(),
            settingsItem, aboutItem, .separator(), quitItem
        ] {
            menu.addItem(item)
        }
        statusItem.menu = menu
    }

    private func buildSliderItem() {
        let heading = NSTextField(labelWithString: "Volume")
        heading.font = .boldSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize)
        heading.sizeToFit()
        heading.setAccessibilityElement(false)

        let sliderHeight = VolumeSlider.trackHeight
        let headingY = Self.sliderBottomPadding + sliderHeight + Self.headingSpacing
        let row = NSView(
            frame: NSRect(x: 0, y: 0, width: Self.sliderRowWidth, height: headingY + heading.frame.height + Self.headingTopPadding))
        row.autoresizingMask = [.width]
        heading.setFrameOrigin(NSPoint(x: Self.sliderInset, y: headingY))
        heading.autoresizingMask = [.maxXMargin]

        volumeSlider.frame = NSRect(
            x: Self.sliderInset, y: Self.sliderBottomPadding, width: Self.sliderRowWidth - 2 * Self.sliderInset, height: sliderHeight)
        volumeSlider.autoresizingMask = [.width]
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeSliderChanged(_:))
        volumeSlider.setAccessibilityLabel("Volume")
        row.addSubview(heading)
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

        // Like the system Sound menu, the slider stands at zero while muted; a device without volume control shows its fixed
        // full level, disabled.
        volumeSlider.doubleValue = Double(audio.map { $0.isMuted ? 0 : $0.volume } ?? 0)
        volumeSlider.isEnabled = audio.map { $0.canSetVolume && !$0.isInUseElsewhere } ?? false
        updateSliderSymbol()

        muteItem.state = audio?.isMuted == true ? .on : .off
        muteItem.isEnabled = audio.map { $0.hasHardwareMute || $0.canSetVolume } ?? false
    }

    // MARK: - Devices

    private func deviceListChanged() {
        let defaultInput = deviceList.devices.first { $0.hasInput && $0.uid == deviceList.defaultInputUID }
        Self.setInfoTitle(inputItem, Self.inputTitle(defaultInput?.name))
        updateSliderSymbol()

        guard let menu = statusItem.menu else { return }
        for item in deviceItems {
            menu.removeItem(item)
        }
        let sections = Self.deviceSections(deviceList.devices)
        deviceItems =
            sectionItems(.output, devices: sections.outputs, defaultUID: deviceList.defaultOutputUID)
            + sectionItems(.input, devices: sections.inputs, defaultUID: deviceList.defaultInputUID)
        let start = menu.index(of: sliderItem) + 1
        for (offset, item) in deviceItems.enumerated() {
            menu.insertItem(item, at: start + offset)
        }
    }

    /// The device list knows the transport and model the symbol depends on; it runs while the menu is open, the only time
    /// the slider is visible.
    private func updateSliderSymbol() {
        let output = audio.flatMap { state in deviceList.devices.first { $0.uid == state.deviceUID } }
        volumeSlider.symbolName = DeviceIcon.sliderSymbolName(for: output)
    }

    /// A section without devices is left out entirely. As in the macOS Sound menu, the default device is marked by the accent
    /// circle of its icon, and its title is bold.
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
            if isDefault {
                item.attributedTitle = NSAttributedString(string: device.name, attributes: Self.defaultDeviceAttributes)
            }
            item.image = DeviceIcon.image(
                symbolName: DeviceIcon.symbolName(for: device, direction: direction), isDefault: isDefault,
                accessibilityDescription: isDefault ? current : nil)
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
