import AppKit

/// Owns all long-lived objects, wires their callbacks, starts and stops them (docs/DESIGN.md §6).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: Settings
    private let audio: AudioOutput
    private let dial: DialDevice
    private let controller: DialController
    private let overlay = VolumeOverlay()
    private let battery = DialBattery()
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var isAccessDenied = false
    private var appliedDetents: Int?
    private var appliedHaptics: Bool?
    /// The first connection after launch stays silent; later ones are wake-ups and confirm readiness with a click.
    private var hasDialConnectedBefore = false

    override init() {
        let settings = Settings()
        let audio = AudioOutput()
        let dial = DialDevice()
        self.settings = settings
        self.audio = audio
        self.dial = dial
        controller = DialController(audio: audio, haptics: dial, settings: { settings.controlSettings })
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
            self?.audio.refreshSoftwareVolume()
            // Excluding or including the current output changes the icon.
            self?.refreshStatusItem()
        }
        // Stored before start(), so the first match already gets the user's configuration.
        applyDialConfiguration()

        dial.onEvent = { [weak self] event in
            Log.control.debug("Dial event: \(String(describing: event), privacy: .public)")
            self?.controller.handle(event)
        }
        dial.onConnectionChange = { [weak self] connection in
            Log.control.info("Dial \(String(describing: connection), privacy: .public)")
            if connection != .connected {
                self?.controller.reset()
            }
            self?.confirmReconnection(connection)
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
        refreshStatusItem()

        #if DEBUG
        startKeepAliveSpike()
        #endif
    }

    #if DEBUG
    // Keep-awake spike (docs/DESIGN.md §14): sends the reports named in the `keepAliveSpike` default every 4 minutes.
    private var keepAliveSpikeTask: Task<Void, Never>?

    private func startKeepAliveSpike() {
        let names = UserDefaults.standard.stringArray(forKey: "keepAliveSpike") ?? []
        let reports = names.compactMap(DialDevice.KeepAliveReport.init(rawValue:))
        guard !reports.isEmpty else { return }
        Log.dial.info("Keep-alive spike with \(names, privacy: .public) every 4 minutes")
        keepAliveSpikeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(240))
                guard let self, !Task.isCancelled else { return }
                Log.dial.info("Keep-alive spike tick, Dial \(String(describing: self.dial.connection), privacy: .public)")
                self.dial.sendKeepAlive(reports)
            }
        }
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
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

    /// The turn that wakes the Dial is lost while macOS reconnects, so a click tells the user when the Dial is ready.
    private func confirmReconnection(_ connection: DialConnection) {
        guard connection == .connected else { return }
        if hasDialConnectedBefore {
            dial.playHaptic(.click)
        }
        hasDialConnectedBefore = true
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

    private func showSettings() {
        let window = settingsWindow ?? SettingsWindowController(settings: settings)
        settingsWindow = window
        window.show()
    }
}
