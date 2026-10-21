import CoreAudio

/// Wraps Core Audio for the current default output device (Docs/DESIGN.md §7.4).
///
/// Listener blocks are registered on the main queue, so all notifications arrive on the main thread. Core Audio, the
/// software volume, the clock and the sleep are injected, so the tests drive the state machine with fakes (§11.1).
final class AudioOutput: AudioControlling {
    // Core Audio reads a written volume back with float noise, e.g. 0.58 as 0.58000004. Smaller differences are no change.
    private static let volumeTolerance: Float32 = 0.0001
    /// While another device owns the output, a write only probes whether the Mac has it back; once a second is enough
    /// and spares the device a command per detent.
    private static let probeInterval: Duration = .seconds(1)
    private static let observedDeviceAddresses = [
        CoreAudioProperty.virtualMainVolumeAddress,
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementWildcard),
        CoreAudioProperty.muteAddress
    ]
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// `nil` when there is no output device.
    private(set) var state: AudioState?
    var onChange: ((AudioState?) -> Void)?
    weak var preferences: (any SoftwareVolumePreferences)?
    /// Set when software volume could not start, for example because audio recording permission is missing.
    private(set) var softwareVolumeError: String?

    private let coreAudio: any CoreAudioAccess
    private let softwareVolume: any SoftwareVolumeControlling
    private let now: () -> ContinuousClock.Instant
    private let volumeCheckWindow: DelayedAction
    /// A device whose software volume failed to start is not retried on every refresh, only after a settings change.
    private var failedSoftwareVolumeUID: String?
    private var observedDeviceID: AudioObjectID?
    private var systemListener: CoreAudioProperty.ListenerBlock?
    private var deviceListener: CoreAudioProperty.ListenerBlock?
    /// Volumes remembered by emulated mute, keyed by device UID. Kept in memory only.
    private var emulatedMuteVolumes: [String: Float32] = [:]
    private var volumeCheck = VolumeWriteCheck()
    private var lastProbe: ContinuousClock.Instant?
    /// `onChange` runs synchronously; a listener that refreshed this object from inside it would publish twice.
    private var isPublishing = false

    init(
        coreAudio: any CoreAudioAccess = CoreAudioHAL(), softwareVolume: any SoftwareVolumeControlling = SoftwareVolume(),
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now },
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.coreAudio = coreAudio
        self.softwareVolume = softwareVolume
        self.now = now
        self.volumeCheckWindow = DelayedAction(sleep: sleep)
    }

    func start() -> Void {
        guard self.systemListener == nil else {
            return
        }
        let systemListener: CoreAudioProperty.ListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.defaultDeviceChanged()
            }
        }
        let deviceListener: CoreAudioProperty.ListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        self.systemListener = systemListener
        self.deviceListener = deviceListener

        let status = self.coreAudio.addListener(systemListener, for: CoreAudioProperty.defaultOutputDeviceAddress, on: Self.systemObject)
        if status != noErr {
            Log.audio.error("\(CoreAudioError(status: status, operation: "Observing the default output device"), privacy: .public)")
        }
        self.defaultDeviceChanged()
    }

    func stop() -> Void {
        if let systemListener = self.systemListener {
            self.coreAudio.removeListener(systemListener, for: CoreAudioProperty.defaultOutputDeviceAddress, on: Self.systemObject)
        }
        self.detachFromDevice()
        self.softwareVolume.stop()
        self.resetVolumeCheck()
        self.systemListener = nil
        self.deviceListener = nil
    }

    /// Re-evaluates software volume after its settings changed, and retries a start that failed.
    func refreshSoftwareVolume() -> Void {
        self.failedSoftwareVolumeUID = nil
        self.refresh()
    }

    func setVolume(_ volume: Float32) -> Void {
        guard var state = self.state else {
            return
        }
        guard state.canSetVolume == true else {
            return
        }
        let volume = min(max(volume, 0), 1)
        if state.isInUseElsewhere == true {
            if self.shouldProbe() == false {
                return
            }
        }
        do {
            if state.isSoftwareVolume == false {
                self.checkVolumeWrite(volume, current: state.volume)
            }
            try self.writeVolume(volume, state: state)
            if state.isSoftwareVolume == true {
                self.preferences?.setSoftwareVolumeLevel(state.deviceUID, volume)
            }
            // A probe is not shown; the state changes only once the device keeps the new volume.
            if state.isInUseElsewhere == true {
                return
            }
            state.volume = volume
            if state.hasHardwareMute == false {
                if volume > 0 {
                    if self.emulatedMuteVolumes.removeValue(forKey: state.deviceUID) != nil {
                        state.isMuted = false
                    }
                }
            }
            // Optimistic: the listener confirms or corrects the value.
            self.publish(state)
        }
        catch {
            Log.audio.error("\(error, privacy: .public)")
        }
    }

    func setMuted(_ muted: Bool) -> Void {
        guard var state = self.state else {
            return
        }
        guard state.isMuted != muted else {
            return
        }
        do {
            if state.hasHardwareMute == true {
                try self.coreAudio.writeMute(muted, of: state.deviceID)
            }
            else if state.canSetVolume == true {
                try self.setEmulatedMute(muted, state: &state)
            }
            else {
                Log.audio.notice("\(state.deviceName, privacy: .public) has neither mute nor software volume")
                return
            }
            state.isMuted = muted
            self.publish(state)
        }
        catch {
            Log.audio.error("\(error, privacy: .public)")
        }
    }

    // MARK: - Emulated Mute

    /// For devices without a mute control: mute remembers the volume and sets it to 0, unmute restores it.
    private func setEmulatedMute(_ muted: Bool, state: inout AudioState) throws -> Void {
        if muted == true {
            // Stored before writing so the listener round-trip already sees the device as muted.
            self.emulatedMuteVolumes[state.deviceUID] = state.volume
            do {
                try self.writeVolume(0, state: state)
            }
            catch {
                self.emulatedMuteVolumes[state.deviceUID] = nil
                throw error
            }
            state.volume = 0
        }
        else {
            let restored = self.emulatedMuteVolumes.removeValue(forKey: state.deviceUID) ?? state.volume
            try self.writeVolume(restored, state: state)
            state.volume = restored
        }
    }

    /// Without a mute control, a remembered volume means muted at zero; a non-zero volume set elsewhere clears it.
    private func resolveEmulatedMute(in state: inout AudioState) -> Void {
        guard state.hasHardwareMute == false else {
            return
        }
        guard self.emulatedMuteVolumes[state.deviceUID] != nil else {
            return
        }
        if state.volume > 0 {
            self.emulatedMuteVolumes[state.deviceUID] = nil
        }
        else {
            state.isMuted = true
        }
    }

    private func writeVolume(_ volume: Float32, state: AudioState) throws -> Void {
        if state.isSoftwareVolume == true {
            self.softwareVolume.level = volume
        }
        else {
            try self.coreAudio.writeVolume(volume, of: state.deviceID)
        }
    }

    // MARK: - Rejected Writes

    /// While another device owns the output, at most one write per interval goes out, as a probe.
    private func shouldProbe() -> Bool {
        let now = self.now()
        if let lastProbe = self.lastProbe {
            if now - lastProbe < Self.probeInterval {
                return false
            }
        }
        self.lastProbe = now
        return true
    }

    private func checkVolumeWrite(_ volume: Float32, current: Float32) -> Void {
        self.volumeCheck.willWrite(volume, current: current)
        self.volumeCheckWindow.schedule(after: VolumeWriteCheck.window) { [weak self] in
            guard let self else {
                return
            }
            self.volumeCheck.finish()
            self.refresh()
        }
    }

    private func resetVolumeCheck() -> Void {
        self.volumeCheckWindow.cancel()
        self.volumeCheck = VolumeWriteCheck()
        self.lastProbe = nil
    }

    // MARK: - Software Volume

    /// The device that should get software volume: a default output without native volume control that the user opted
    /// in; `nil` otherwise.
    private func softwareVolumeCandidate(uid: String?, nativeCanSetVolume: Bool) -> String? {
        guard let uid = uid else {
            return nil
        }
        guard nativeCanSetVolume == false else {
            return nil
        }
        guard let preferences = self.preferences else {
            return nil
        }
        guard preferences.wantsSoftwareVolume(uid) == true else {
            return nil
        }
        return uid
    }

    /// Starts or stops software volume so it runs exactly for a default output that lacks volume control and is opted in.
    /// Returns whether it runs for `uid`.
    private func reconcileSoftwareVolume(uid: String?, nativeCanSetVolume: Bool) -> Bool {
        guard let uid = self.softwareVolumeCandidate(uid: uid, nativeCanSetVolume: nativeCanSetVolume) else {
            self.softwareVolume.stop()
            return false
        }
        if self.softwareVolume.deviceUID == uid {
            return true
        }
        if self.failedSoftwareVolumeUID == uid {
            return false
        }
        let level = self.preferences?.softwareVolumeLevel(uid) ?? 1
        do {
            try self.softwareVolume.start(deviceUID: uid, level: level)
            self.softwareVolumeError = nil
            return true
        }
        catch {
            Log.audio.error("Software volume could not start: \(error, privacy: .public)")
            self.failedSoftwareVolumeUID = uid
            self.softwareVolumeError = String(describing: error)
            return false
        }
    }

    // MARK: - Observation

    private func defaultDeviceChanged() -> Void {
        let deviceID: AudioObjectID?
        do {
            deviceID = try self.coreAudio.readDefaultDevice(scope: kAudioDevicePropertyScopeOutput)
        }
        catch {
            Log.audio.error("\(error, privacy: .public)")
            deviceID = nil
        }

        if deviceID != self.observedDeviceID {
            self.detachFromDevice()
            if let deviceID = deviceID {
                self.attach(to: deviceID)
            }
        }
        self.refresh()
    }

    private func attach(to deviceID: AudioObjectID) -> Void {
        self.observedDeviceID = deviceID
        // A rejection belongs to the device that refused; another device starts unchecked.
        self.resetVolumeCheck()
        if let deviceListener = self.deviceListener {
            for address in Self.observedDeviceAddresses {
                let status = self.coreAudio.addListener(deviceListener, for: address, on: deviceID)
                // Devices without a mute or volume control refuse the listener; that is expected.
                if status != noErr {
                    Log.audio.debug("\(CoreAudioError(status: status, operation: "Observing device property"), privacy: .public)")
                }
            }
        }
    }

    private func detachFromDevice() -> Void {
        guard let deviceID = self.observedDeviceID else {
            return
        }
        self.observedDeviceID = nil
        if let deviceListener = self.deviceListener {
            for address in Self.observedDeviceAddresses {
                self.coreAudio.removeListener(deviceListener, for: address, on: deviceID)
            }
        }
    }

    /// Re-reads the full state; `onChange` fires only when it differs from the cached one. Software volume is reconciled,
    /// the rejected-write check fed and the emulated mute resolved here, so `readState` stays a pure read.
    private func refresh() -> Void {
        guard let deviceID = self.observedDeviceID else {
            _ = self.reconcileSoftwareVolume(uid: nil, nativeCanSetVolume: true)
            self.publish(nil)
            return
        }
        do {
            let uid = try self.coreAudio.readString(kAudioDevicePropertyDeviceUID, of: deviceID)
            let name = try self.coreAudio.readString(kAudioObjectPropertyName, of: deviceID)
            let nativeCanSetVolume = self.coreAudio.isSettable(CoreAudioProperty.virtualMainVolumeAddress, of: deviceID)
            let isSoftwareVolume = self.reconcileSoftwareVolume(uid: uid, nativeCanSetVolume: nativeCanSetVolume)
            var state = try self.readState(
                of: deviceID, uid: uid, name: name, nativeCanSetVolume: nativeCanSetVolume, isSoftwareVolume: isSoftwareVolume)
            if nativeCanSetVolume == true {
                self.volumeCheck.didRead(state.volume)
                state.isInUseElsewhere = self.volumeCheck.isRejected
            }
            self.resolveEmulatedMute(in: &state)
            self.publish(state)
        }
        catch {
            Log.audio.error("\(error, privacy: .public)")
            // The cached state stays at the last confirmed value, but never one that belongs to another device.
            if self.state?.deviceID != deviceID {
                self.publish(nil)
            }
        }
    }

    /// A pure read of the device: no state of this object changes here.
    private func readState(
        of deviceID: AudioObjectID, uid: String, name: String, nativeCanSetVolume: Bool, isSoftwareVolume: Bool
    ) throws -> AudioState {
        // Without any volume control the device plays at its fixed level, which is shown as full.
        let volume: Float32
        if nativeCanSetVolume == true {
            volume = try self.coreAudio.readVolume(of: deviceID)
        }
        else if isSoftwareVolume == true {
            volume = self.softwareVolume.level
        }
        else {
            volume = 1
        }
        let hasHardwareMute = self.coreAudio.isSettable(CoreAudioProperty.muteAddress, of: deviceID)
        let isMuted: Bool
        if hasHardwareMute == true {
            isMuted = try self.coreAudio.readMute(of: deviceID)
        }
        else {
            isMuted = false
        }
        return AudioState(
            deviceID: deviceID, deviceUID: uid, deviceName: name, volume: volume, isMuted: isMuted,
            canSetVolume: nativeCanSetVolume || isSoftwareVolume, hasHardwareMute: hasHardwareMute, isSoftwareVolume: isSoftwareVolume)
    }

    // MARK: - Publishing

    private func publish(_ newState: AudioState?) -> Void {
        assert(self.isPublishing == false, "AudioOutput.publish re-entered from its own onChange")
        let newState = self.absorbingFloatNoise(newState)
        if newState == self.state {
            return
        }
        self.logOwnershipChange(from: self.state, to: newState)
        self.state = newState
        self.isPublishing = true
        defer { self.isPublishing = false }
        self.onChange?(newState)
    }

    /// A re-read that differs from the cached volume of the same device by float noise keeps the cached value.
    private func absorbingFloatNoise(_ candidate: AudioState?) -> AudioState? {
        guard var candidate = candidate else {
            return nil
        }
        guard let state = self.state else {
            return candidate
        }
        guard candidate.deviceID == state.deviceID else {
            return candidate
        }
        if abs(candidate.volume - state.volume) < Self.volumeTolerance {
            candidate.volume = state.volume
        }
        return candidate
    }

    /// Only a change on the same device is news; switching away from a rejected device says nothing about the new one.
    private func logOwnershipChange(from state: AudioState?, to newState: AudioState?) -> Void {
        guard let newState = newState else {
            return
        }
        guard let state = state else {
            return
        }
        guard newState.deviceID == state.deviceID else {
            return
        }
        guard newState.isInUseElsewhere != state.isInUseElsewhere else {
            return
        }
        if newState.isInUseElsewhere == true {
            Log.audio.notice("\(newState.deviceName, privacy: .public) undid the volume change; another device owns it")
        }
        else {
            Log.audio.notice("\(newState.deviceName, privacy: .public) accepts volume changes again")
        }
    }
}
