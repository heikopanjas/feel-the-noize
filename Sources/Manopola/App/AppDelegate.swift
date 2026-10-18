import AppKit

/// Owns all long-lived objects, wires their callbacks, starts and stops them (docs/DESIGN.md §6).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: Settings
    private let audio: AudioOutput
    private let dial: DialDevice
    private let controller: DialController
    private let overlay = VolumeOverlay()
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var isAccessDenied = false
    private var appliedDetents: Int?
    private var appliedHaptics: Bool?

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
        self.statusItem = statusItem

        settings.onChange = { [weak self] in
            self?.applyDialConfiguration()
        }
        // Stored before start(), so the first match already gets the user's configuration.
        applyDialConfiguration()

        dial.onEvent = { [weak self] event in
            Log.control.debug("Dial event: \(String(describing: event), privacy: .public)")
            self?.controller.handle(event)
        }
        dial.onConnectionChange = { [weak self] isConnected in
            Log.control.info("Dial \(isConnected ? "connected" : "disconnected", privacy: .public)")
            if !isConnected {
                self?.controller.reset()
            }
            self?.refreshStatusItem()
        }
        dial.onAccessDenied = { [weak self] in
            self?.isAccessDenied = true
            self?.statusItem?.setAccessDenied(true)
        }

        audio.onChange = { [weak self] state in
            Log.audio.info("Audio state: \(String(describing: state), privacy: .public)")
            self?.refreshStatusItem()
        }
        controller.onAdjusted = { [weak self] state in
            guard let self, settings.showOverlay else { return }
            overlay.show(state)
        }

        audio.start()
        dial.start()
        refreshStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dial.stop()
        audio.stop()
    }

    /// Retries opening the Dial after the user may have granted Input Monitoring (docs/DESIGN.md §9.2).
    func applicationDidBecomeActive(_ notification: Notification) {
        guard isAccessDenied else { return }
        isAccessDenied = false
        statusItem?.setAccessDenied(false)
        dial.stop()
        dial.start()
    }

    // MARK: - Wiring

    private func refreshStatusItem() {
        statusItem?.update(audio: audio.state, dialConnected: dial.isConnected)
    }

    /// Menu changes go straight to the audio device: no haptics and no overlay, which belong to the Dial.
    private func toggleMuteFromMenu() {
        guard let state = audio.state else { return }
        audio.setMuted(!state.isMuted)
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
