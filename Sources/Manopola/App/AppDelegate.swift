import AppKit

/// Owns all long-lived objects, wires their callbacks, starts and stops them (docs/DESIGN.md §6).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: Settings
    private let audio: AudioOutput
    private let dial: DialDevice
    private let controller: DialController
    private let overlay = VolumeOverlay()
    private let battery = DialBattery()
    private let keepAwake: DialKeepAwake
    private let userActivity = UserActivity()
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var isAccessDenied = false
    private var appliedDetents: Int?
    private var appliedHaptics: Bool?
    /// A Dial that is already awake at launch connects silently; every other connection is a wake-up the user caused and
    /// confirms readiness with a click.
    private var isReadyClickSkipped = false

    override init() {
        let settings = Settings()
        let audio = AudioOutput()
        let dial = DialDevice()
        self.settings = settings
        self.audio = audio
        self.dial = dial
        controller = DialController(audio: audio, haptics: dial, settings: { settings.controlSettings })
        keepAwake = DialKeepAwake { dial.sendKeepAlive() }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = StatusItemController()
        statusItem.onToggleMute = { [weak self] in
            self?.toggleMuteFromMenu()
        }
        statusItem.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        statusItem.onMenuWillOpen = { [weak self] in
            self?.dial.retryIfInUseElsewhere()
        }
        self.statusItem = statusItem

        audio.preferences = settings
        applyIconStyle()
        settings.onChange = { [weak self] in
            self?.applyIconStyle()
            self?.applyDialConfiguration()
            self?.applyKeepAwake()
            self?.audio.refreshSoftwareVolume()
            // Excluding or including the current output changes the icon.
            self?.refreshStatusItem()
        }
        // Stored before start(), so the first match already gets the user's configuration.
        applyDialConfiguration()
        applyKeepAwake()

        dial.onEvent = { [weak self] event in
            Log.control.debug("Dial event: \(String(describing: event), privacy: .public)")
            self?.controller.handle(event)
        }
        // The seized Dial bypasses the HID event system, so its use is declared to macOS like mouse input.
        dial.onActivity = { [weak self] in
            self?.userActivity.declare()
        }
        dial.onConnectionChange = { [weak self] connection in
            Log.control.info("Dial \(String(describing: connection), privacy: .public)")
            if connection != .connected {
                self?.controller.reset()
            }
            // Keep-awake first, so a Dial awake at launch can get its first report right away.
            self?.keepAwake.isDialConnected = connection == .connected
            self?.confirmConnection(connection)
            if connection == .connected {
                self?.battery.dialConnected()
            }
            else {
                self?.battery.dialDisconnected()
            }
            self?.refreshStatusItem()
        }
        battery.onChange = { [weak self] level in
            self?.statusItem?.setDialBatteryLevel(level)
        }
        dial.onAccessDenied = { [weak self] in
            self?.isAccessDenied = true
            self?.statusItem?.setAccessDenied(true)
        }

        audio.onChange = { [weak self] state in
            Log.audio.info("Audio state: \(String(describing: state), privacy: .public)")
            if let state {
                // Remembered here too, so the Devices tab lists outputs seen while it was closed.
                self?.settings.rememberDevices([state.deviceUID: state.deviceName])
            }
            self?.refreshStatusItem()
        }
        controller.onAdjusted = { [weak self] state in
            guard let self, settings.showOverlay else { return }
            overlay.show(state)
        }

        audio.start()
        dial.start()
        isReadyClickSkipped = dial.isPresent
        keepAwake.start()
        refreshStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        keepAwake.stop()
        dial.stop()
        audio.stop()
    }

    /// Retries a Dial held by another process, and opening the Dial after the user may have granted Input Monitoring
    /// (docs/DESIGN.md §9.2).
    func applicationDidBecomeActive(_ notification: Notification) {
        dial.retryIfInUseElsewhere()
        guard isAccessDenied else { return }
        isAccessDenied = false
        statusItem?.setAccessDenied(false)
        dial.stop()
        dial.start()
    }

    // MARK: - Wiring

    private func refreshStatusItem() {
        let isOutputEnabled = audio.state.map { settings.isDeviceEnabled($0.deviceUID) } ?? true
        statusItem?.update(audio: audio.state, dial: dial.connection, isOutputEnabled: isOutputEnabled)
    }

    /// Menu changes go straight to the audio device: no haptics and no overlay, which belong to the Dial.
    private func toggleMuteFromMenu() {
        guard let state = audio.state else { return }
        audio.setMuted(!state.isMuted)
    }

    /// The turn that wakes the Dial is lost while macOS reconnects, so a click tells the user when the Dial is ready. An
    /// app cannot wake a sleeping Dial (docs/DESIGN.md §2.1), so after a launch the user's touch is the wake-up as well.
    /// A Dial already awake at launch gets no click but an immediate keep-alive, since its idle time is unknown (§7.14).
    private func confirmConnection(_ connection: DialConnection) {
        guard connection == .connected else { return }
        if isReadyClickSkipped {
            keepAwake.sendNow()
        }
        else {
            dial.playHaptic(.click)
        }
        isReadyClickSkipped = false
    }

    private func applyIconStyle() {
        statusItem?.iconStyle = settings.iconStyle
        overlay.iconStyle = settings.iconStyle
    }

    private func applyDialConfiguration() {
        let detents = settings.detentsPerRevolution
        let haptics = settings.hapticDetents
        guard detents != appliedDetents || haptics != appliedHaptics else { return }
        appliedDetents = detents
        appliedHaptics = haptics
        dial.configure(detentsPerRevolution: detents, hapticsEnabled: haptics)
    }

    private func applyKeepAwake() {
        keepAwake.isEnabled = settings.keepDialAwake
    }

    private func showSettings() {
        let window = settingsWindow ?? SettingsWindowController(settings: settings)
        settingsWindow = window
        window.show()
    }
}
