import AppKit

/// Menu bar icon and menu (docs/DESIGN.md §5.2, §5.3, §7.5).
///
/// `update(audio:dial:)` changes the icon and the Dial line; other menu titles are refreshed right before the menu opens.
final class StatusItemController: NSObject, NSMenuDelegate {
    private static let inputMonitoringSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    var onToggleMute: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    /// Lets the owner retry a Dial held by another process while the user looks at the menu.
    var onMenuWillOpen: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let dialItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let accessItem = NSMenuItem(title: "Allow Input Monitoring…", action: #selector(openInputMonitoringSettings(_:)), keyEquivalent: "")
    private let outputItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let volumeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let muteItem = NSMenuItem(title: "Mute", action: #selector(toggleMute(_:)), keyEquivalent: "")
    private var audio: AudioState?
    private var dial = DialConnection.notConnected

    override init() {
        super.init()
        buildMenu()
        update(audio: nil, dial: .notConnected)
    }

    func update(audio: AudioState?, dial: DialConnection) {
        self.audio = audio
        self.dial = dial
        // Updated here too, so a retry started by opening the menu shows its result while the menu is open.
        dialItem.title = Self.title(for: dial)

        guard let button = statusItem.button else { return }
        var description = VolumePresentation.accessibilityDescription(for: audio)
        switch dial {
            case .connected: break
            case .notConnected: description += ", Surface Dial not connected"
            case .inUseElsewhere: description += ", Surface Dial in use by another app"
        }
        button.image = VolumePresentation.image(for: audio, accessibilityDescription: description)
        button.appearsDisabled = dial != .connected || audio?.canSetVolume != true
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

        for infoItem in [dialItem, outputItem, volumeItem] {
            infoItem.isEnabled = false
        }
        accessItem.target = self
        accessItem.isHidden = true
        muteItem.target = self

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        let aboutItem = NSMenuItem(title: "About Manopola", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        let quitItem = NSMenuItem(title: "Quit Manopola", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for item in [
            dialItem, accessItem, outputItem, volumeItem, .separator(), muteItem, .separator(), settingsItem, aboutItem, .separator(), quitItem
        ] {
            menu.addItem(item)
        }
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        onMenuWillOpen?()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        dialItem.title = Self.title(for: dial)
        outputItem.title = "Output: \(audio?.deviceName ?? "None")"

        switch audio {
            case .none:
                volumeItem.title = "Volume: –"
            case .some(let state) where !state.canSetVolume:
                volumeItem.title = "Volume: not adjustable"
            case .some(let state):
                volumeItem.title = "Volume: \(VolumePresentation.percent(state.volume))"
        }

        muteItem.state = audio?.isMuted == true ? .on : .off
        muteItem.isEnabled = audio.map { $0.hasHardwareMute || $0.canSetVolume } ?? false
    }

    private static func title(for dial: DialConnection) -> String {
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
