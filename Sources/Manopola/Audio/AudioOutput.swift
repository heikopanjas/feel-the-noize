import CoreAudio

/// Where `AudioOutput` learns whether a device should get software volume and keeps its level; `Settings` conforms.
protocol SoftwareVolumePreferences: AnyObject {
    func wantsSoftwareVolume(_ uid: String) -> Bool
    func softwareVolumeLevel(_ uid: String) -> Float
    func setSoftwareVolumeLevel(_ uid: String, _ level: Float)
}

/// Wraps Core Audio for the current default output device (docs/DESIGN.md §7.4).
///
/// Listener blocks are registered on the main queue, so all notifications arrive on the main thread.
final class AudioOutput: AudioControlling {
    // Core Audio reads a written volume back with float noise, e.g. 0.58 as 0.58000004. Smaller differences are no change.
    private static let volumeTolerance: Float32 = 0.0001

    /// `nil` when there is no output device.
    private(set) var state: AudioState?
    var onChange: ((AudioState?) -> Void)?
    weak var preferences: (any SoftwareVolumePreferences)?
    /// Set when software volume could not start, for example because audio recording permission is missing.
    private(set) var softwareVolumeError: String?

    private let softwareVolume = SoftwareVolume()
    /// A device whose software volume failed to start is not retried on every refresh, only after a settings change.
    private var failedSoftwareVolumeUID: String?
    private var observedDeviceID: AudioObjectID?
    private var systemListener: CoreAudioProperty.ListenerBlock?
    private var deviceListener: CoreAudioProperty.ListenerBlock?
    /// Volumes remembered by emulated mute, keyed by device UID. Kept in memory only.
    private var emulatedMuteVolumes: [String: Float32] = [:]

    func start() {
        guard systemListener == nil else { return }

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

        var address = CoreAudioProperty.defaultOutputDeviceAddress
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, systemListener)
        if status != noErr {
            Log.audio.error("\(CoreAudioError(status: status, operation: "Observing the default output device"), privacy: .public)")
        }
        defaultDeviceChanged()
    }

    func stop() {
        if let systemListener {
            var address = CoreAudioProperty.defaultOutputDeviceAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, systemListener)
        }
        detachFromDevice()
        softwareVolume.stop()
        systemListener = nil
        deviceListener = nil
    }

    /// Re-evaluates software volume after its settings changed, and retries a start that failed.
    func refreshSoftwareVolume() {
        failedSoftwareVolumeUID = nil
        refresh()
    }

    func setVolume(_ volume: Float32) {
        guard var state, state.canSetVolume else { return }
        let volume = min(max(volume, 0), 1)
        do {
            try writeVolume(volume, state: state)
            if state.isSoftwareVolume {
                preferences?.setSoftwareVolumeLevel(state.deviceUID, volume)
            }
            state.volume = volume
            if !state.hasHardwareMute, volume > 0, emulatedMuteVolumes.removeValue(forKey: state.deviceUID) != nil {
                state.isMuted = false
            }
            // Optimistic: the listener confirms or corrects the value.
            publish(state)
        }
        catch {
            Log.audio.error("\(error, privacy: .public)")
        }
    }

    func setMuted(_ muted: Bool) {
        guard var state, state.isMuted != muted else { return }
        do {
            if state.hasHardwareMute {
                try CoreAudioProperty.writeMute(muted, of: state.deviceID)
            }
            else if state.canSetVolume {
                try setEmulatedMute(muted, state: &state)
            }
            else {
                Log.audio.notice("\(state.deviceName, privacy: .public) has neither mute nor software volume")
                return
            }
            state.isMuted = muted
            publish(state)
        }
        catch {
            Log.audio.error("\(error, privacy: .public)")
        }
    }

    // MARK: - Emulated Mute

    /// For devices without a mute control: mute remembers the volume and sets it to 0, unmute restores it.
    private func setEmulatedMute(_ muted: Bool, state: inout AudioState) throws {
        if muted {
            // Stored before writing so the listener round-trip already sees the device as muted.
            emulatedMuteVolumes[state.deviceUID] = state.volume
            do {
                try writeVolume(0, state: state)
            }
            catch {
                emulatedMuteVolumes[state.deviceUID] = nil
                throw error
            }
            state.volume = 0
        }
        else {
            let restored = emulatedMuteVolumes.removeValue(forKey: state.deviceUID) ?? state.volume
            try writeVolume(restored, state: state)
            state.volume = restored
        }
    }

    private func writeVolume(_ volume: Float32, state: AudioState) throws {
        if state.isSoftwareVolume {
            softwareVolume.level = volume
        }
        else {
            try CoreAudioProperty.writeVolume(volume, of: state.deviceID)
        }
    }

    // MARK: - Software Volume

    /// Starts or stops software volume so it runs exactly for a default output that lacks volume control and is opted in.
    /// Returns whether it runs for `uid`.
    private func reconcileSoftwareVolume(uid: String?, nativeCanSetVolume: Bool) -> Bool {
        guard let uid, !nativeCanSetVolume, let preferences, preferences.wantsSoftwareVolume(uid) else {
            softwareVolume.stop()
            return false
        }
        if softwareVolume.deviceUID == uid {
            return true
        }
        if failedSoftwareVolumeUID == uid {
            return false
        }
        do {
            try softwareVolume.start(deviceUID: uid, level: preferences.softwareVolumeLevel(uid))
            softwareVolumeError = nil
            return true
        }
        catch {
            Log.audio.error("Software volume could not start: \(error, privacy: .public)")
            failedSoftwareVolumeUID = uid
            softwareVolumeError = String(describing: error)
            return false
        }
    }

    // MARK: - Observation

    private func defaultDeviceChanged() {
        let deviceID: AudioObjectID?
        do {
            deviceID = try CoreAudioProperty.readDefaultOutputDevice()
        }
        catch {
            Log.audio.error("\(error, privacy: .public)")
            deviceID = nil
        }

        if deviceID != observedDeviceID {
            detachFromDevice()
            if let deviceID {
                attach(to: deviceID)
            }
        }
        refresh()
    }

    private func attach(to deviceID: AudioObjectID) {
        observedDeviceID = deviceID
        guard let deviceListener else { return }
        for var address in Self.observedDeviceAddresses {
            let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, deviceListener)
            // Devices without a mute or volume control refuse the listener; that is expected.
            if status != noErr {
                Log.audio.debug("\(CoreAudioError(status: status, operation: "Observing device property"), privacy: .public)")
            }
        }
    }

    private func detachFromDevice() {
        guard let deviceID = observedDeviceID else { return }
        observedDeviceID = nil
        guard let deviceListener else { return }
        for var address in Self.observedDeviceAddresses {
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, deviceListener)
        }
    }

    /// Re-reads the full state; `onChange` fires only when it differs from the cached one.
    private func refresh() {
        guard let deviceID = observedDeviceID else {
            _ = reconcileSoftwareVolume(uid: nil, nativeCanSetVolume: true)
            publish(nil)
            return
        }
        do {
            publish(try readState(of: deviceID))
        }
        catch {
            Log.audio.error("\(error, privacy: .public)")
            // The cached state stays at the last confirmed value, but never one that belongs to another device.
            if state?.deviceID != deviceID {
                publish(nil)
            }
        }
    }

    private func publish(_ newState: AudioState?) {
        var newState = newState
        if let state, let candidate = newState, candidate.deviceID == state.deviceID,
            abs(candidate.volume - state.volume) < Self.volumeTolerance
        {
            newState?.volume = state.volume
        }
        guard newState != state else { return }
        state = newState
        onChange?(newState)
    }

    private func readState(of deviceID: AudioObjectID) throws -> AudioState {
        let uid = try CoreAudioProperty.readString(kAudioDevicePropertyDeviceUID, of: deviceID)
        let name = try CoreAudioProperty.readString(kAudioObjectPropertyName, of: deviceID)
        let nativeCanSetVolume = CoreAudioProperty.isSettable(CoreAudioProperty.virtualMainVolumeAddress, of: deviceID)
        let isSoftwareVolume = reconcileSoftwareVolume(uid: uid, nativeCanSetVolume: nativeCanSetVolume)
        let canSetVolume = nativeCanSetVolume || isSoftwareVolume
        // Without any volume control the device plays at its fixed level, which is shown as full.
        var volume: Float32
        if nativeCanSetVolume {
            volume = try CoreAudioProperty.readVolume(of: deviceID)
        }
        else {
            volume = isSoftwareVolume ? softwareVolume.level : 1
        }
        let hasHardwareMute = CoreAudioProperty.isSettable(CoreAudioProperty.muteAddress, of: deviceID)

        let isMuted: Bool
        if hasHardwareMute {
            isMuted = try CoreAudioProperty.readMute(of: deviceID)
        }
        else if emulatedMuteVolumes[uid] != nil, volume > 0 {
            // A non-zero volume set elsewhere clears the emulated mute.
            emulatedMuteVolumes[uid] = nil
            isMuted = false
        }
        else {
            isMuted = emulatedMuteVolumes[uid] != nil
            if isMuted {
                volume = 0
            }
        }

        return AudioState(
            deviceID: deviceID, deviceUID: uid, deviceName: name, volume: volume, isMuted: isMuted, canSetVolume: canSetVolume,
            hasHardwareMute: hasHardwareMute, isSoftwareVolume: isSoftwareVolume)
    }

    // MARK: - Property Addresses

    private static let observedDeviceAddresses = [
        CoreAudioProperty.virtualMainVolumeAddress,
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementWildcard),
        CoreAudioProperty.muteAddress
    ]
}
