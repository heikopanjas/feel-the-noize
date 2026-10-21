import AppKit
import CoreAudio

/// Owns all long-lived objects, wires their callbacks, starts and stops them (Docs/DESIGN.md §6).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: Settings
    private let audio: AudioOutput
    private let dial: DialDevice
    private let controller: DialController
    private let overlay = VolumeOverlay()
    private let keepAwake: DialKeepAwake
    private let userActivity = UserActivity()
    private let inputKeeper = InputDeviceKeeper()
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
        self.controller = DialController(audio: audio, haptics: dial, settings: { settings.controlSettings })
        self.keepAwake = DialKeepAwake { dial.sendKeepAlive() }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) -> Void {
        let statusItem = StatusItemController()
        statusItem.onToggleMute = { [weak self] in
            self?.toggleMuteFromMenu()
        }
        statusItem.onSetVolume = { [weak self] volume in
            self?.setVolumeFromMenu(volume)
        }
        statusItem.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        statusItem.onMenuWillOpen = { [weak self] in
            self?.dial.retryIfInUseElsewhere()
        }
        statusItem.onSelectOutput = { [weak self] uid in
            self?.selectDefaultDevice(uid, scope: kAudioDevicePropertyScopeOutput)
        }
        statusItem.onSelectInput = { [weak self] uid in
            self?.selectInputFromMenu(uid)
        }
        self.statusItem = statusItem

        self.audio.preferences = self.settings
        self.applyIconStyle()
        self.settings.onChange = { [weak self] in
            self?.applyIconStyle()
            self?.applyDialConfiguration()
            self?.applyKeepAwake()
            self?.applyKeptInput()
            self?.audio.refreshSoftwareVolume()
            // Excluding or including the current output changes the icon.
            self?.refreshStatusItem()
        }
        // Stored before start(), so the first match already gets the user's configuration.
        self.applyDialConfiguration()
        self.applyKeepAwake()
        self.applyKeptInput()

        self.dial.onEvent = { [weak self] event in
            Log.control.debug("Dial event: \(String(describing: event), privacy: .public)")
            self?.controller.handle(event)
        }
        // The seized Dial bypasses the HID event system, so its use is declared to macOS like mouse input.
        self.dial.onActivity = { [weak self] in
            self?.userActivity.declare()
        }
        self.dial.onConnectionChange = { [weak self] connection in
            Log.control.info("Dial \(String(describing: connection), privacy: .public)")
            if connection != .connected {
                self?.controller.reset()
            }
            // Keep-awake first, so a Dial awake at launch can get its first report right away.
            self?.keepAwake.isDialConnected = connection == .connected
            self?.confirmConnection(connection)
            self?.refreshStatusItem()
        }
        self.dial.onAccessDenied = { [weak self] in
            self?.isAccessDenied = true
            self?.statusItem?.setAccessDenied(true)
        }

        self.audio.onChange = { [weak self] state in
            Log.audio.info("Audio state: \(String(describing: state), privacy: .public)")
            if let state = state {
                // Remembered here too, so the Devices tab lists outputs seen while it was closed.
                self?.settings.rememberDevices([state.deviceUID: state.deviceName])
            }
            self?.refreshStatusItem()
        }
        self.controller.onAdjusted = { [weak self] state in
            guard let self = self else {
                return
            }
            guard self.settings.showOverlay == true else {
                return
            }
            self.overlay.show(state)
        }

        self.audio.start()
        self.dial.start()
        self.isReadyClickSkipped = self.dial.isPresent
        self.keepAwake.start()
        self.refreshStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) -> Void {
        self.keepAwake.stop()
        self.dial.stop()
        self.audio.stop()
    }

    /// Retries a Dial held by another process, and opening the Dial after the user may have granted Input Monitoring
    /// (Docs/DESIGN.md §9.2).
    func applicationDidBecomeActive(_ notification: Notification) -> Void {
        self.dial.retryIfInUseElsewhere()
        if self.isAccessDenied == false {
            return
        }
        self.isAccessDenied = false
        self.statusItem?.setAccessDenied(false)
        self.dial.stop()
        self.dial.start()
    }

    // MARK: - Wiring

    private func refreshStatusItem() -> Void {
        let isOutputEnabled = self.audio.state.map { self.settings.isDeviceEnabled($0.deviceUID) } ?? true
        self.statusItem?.update(audio: self.audio.state, dial: self.dial.connection, isOutputEnabled: isOutputEnabled)
    }

    /// Menu changes go straight to the audio device: no haptics and no overlay, which belong to the Dial.
    private func toggleMuteFromMenu() -> Void {
        guard let state = self.audio.state else {
            return
        }
        self.audio.setMuted(state.isMuted == false)
    }

    /// Moving the slider unmutes, as in the system Sound menu. No haptics and no overlay, as for the menu's Mute.
    private func setVolumeFromMenu(_ volume: Float32) -> Void {
        guard let state = self.audio.state else {
            return
        }
        guard state.canSetVolume == true else {
            return
        }
        if state.isMuted == true {
            self.audio.setMuted(false)
        }
        self.audio.setVolume(volume)
    }

    /// While a device is kept, the menu choice becomes the new kept device (Docs/DESIGN.md §7.13). The keep moves before the
    /// switch, so the keeper does not revert it.
    private func selectInputFromMenu(_ uid: String) -> Void {
        if self.settings.keptInputDeviceUID != nil {
            self.rememberInputName(uid: uid)
            self.settings.keptInputDeviceUID = uid
        }
        self.selectDefaultDevice(uid, scope: kAudioDevicePropertyScopeInput)
    }

    /// So the Devices tab can name the kept device while it is disconnected.
    private func rememberInputName(uid: String) -> Void {
        guard let deviceID = try? CoreAudioProperty.readDevice(uid: uid) else {
            return
        }
        guard let name = try? CoreAudioProperty.readString(kAudioObjectPropertyName, of: deviceID) else {
            return
        }
        self.settings.rememberInputDevices([uid: name])
    }

    /// `AudioOutput` and the open menu follow the new default through their own listeners (Docs/DESIGN.md §7.11).
    private func selectDefaultDevice(_ uid: String, scope: AudioObjectPropertyScope) -> Void {
        let direction = scope == kAudioDevicePropertyScopeInput ? "input" : "output"
        do {
            try self.switchDefaultDevice(to: uid, scope: scope, direction: direction)
        }
        catch {
            Log.audio.error("\(error, privacy: .public)")
        }
    }

    private func switchDefaultDevice(to uid: String, scope: AudioObjectPropertyScope, direction: String) throws -> Void {
        guard let deviceID = try CoreAudioProperty.readDevice(uid: uid) else {
            Log.audio.error("Cannot select \(uid, privacy: .public) as default \(direction, privacy: .public): not connected")
            return
        }
        try CoreAudioProperty.writeDefaultDevice(deviceID, scope: scope)
        Log.audio.info("Selected \(uid, privacy: .public) as default \(direction, privacy: .public)")
    }

    /// The turn that wakes the Dial is lost while macOS reconnects, so a click tells the user when the Dial is ready. An
    /// app cannot wake a sleeping Dial (Docs/DESIGN.md §2.1), so after a launch the user's touch is the wake-up as well.
    /// A Dial already awake at launch gets no click but an immediate keep-alive, since its idle time is unknown (§7.14).
    private func confirmConnection(_ connection: DialConnection) -> Void {
        guard connection == .connected else {
            return
        }
        if self.isReadyClickSkipped == true {
            self.keepAwake.sendNow()
        }
        else {
            self.dial.playHaptic(.click)
        }
        self.isReadyClickSkipped = false
    }

    private func applyIconStyle() -> Void {
        self.statusItem?.iconStyle = self.settings.iconStyle
        self.overlay.iconStyle = self.settings.iconStyle
    }

    private func applyDialConfiguration() -> Void {
        let detents = self.settings.detentsPerRevolution
        let haptics = self.settings.hapticDetents
        if detents == self.appliedDetents {
            if haptics == self.appliedHaptics {
                return
            }
        }
        self.appliedDetents = detents
        self.appliedHaptics = haptics
        self.dial.configure(detentsPerRevolution: detents, hapticsEnabled: haptics)
    }

    private func applyKeepAwake() -> Void {
        self.keepAwake.isEnabled = self.settings.keepDialAwake
    }

    private func applyKeptInput() -> Void {
        self.inputKeeper.keptUID = self.settings.keptInputDeviceUID
        self.statusItem?.keptInputUID = self.settings.keptInputDeviceUID
    }

    private func showSettings() -> Void {
        let window = self.settingsWindow ?? SettingsWindowController(settings: self.settings)
        self.settingsWindow = window
        window.show()
    }
}
