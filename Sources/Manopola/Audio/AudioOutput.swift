import AudioToolbox
import CoreAudio

/// Wraps Core Audio for the current default output device (docs/DESIGN.md §7.4).
///
/// Listener blocks are registered on the main queue, so all notifications arrive on the main thread.
final class AudioOutput: AudioControlling {
    /// Core Audio identifies a listener by the block pointer, so each block is stored as an Objective-C block once and
    /// the same instance is passed to both add and remove.
    private typealias ListenerBlock = @convention(block) (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void

    // Core Audio reads a written volume back with float noise, e.g. 0.58 as 0.58000004. Smaller differences are no change.
    private static let volumeTolerance: Float32 = 0.0001

    /// `nil` when there is no output device.
    private(set) var state: AudioState?
    var onChange: ((AudioState?) -> Void)?

    private var observedDeviceID: AudioObjectID?
    private var systemListener: ListenerBlock?
    private var deviceListener: ListenerBlock?
    /// Volumes remembered by emulated mute, keyed by device UID. Kept in memory only.
    private var emulatedMuteVolumes: [String: Float32] = [:]

    func start() {
        guard systemListener == nil else { return }

        let systemListener: ListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.defaultDeviceChanged()
            }
        }
        let deviceListener: ListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        self.systemListener = systemListener
        self.deviceListener = deviceListener

        var address = Self.defaultOutputDeviceAddress
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, systemListener)
        if status != noErr {
            Log.audio.error("\(CoreAudioError(status: status, operation: "Observing the default output device"), privacy: .public)")
        }
        defaultDeviceChanged()
    }

    func stop() {
        if let systemListener {
            var address = Self.defaultOutputDeviceAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, systemListener)
        }
        detachFromDevice()
        systemListener = nil
        deviceListener = nil
    }

    func setVolume(_ volume: Float32) {
        guard var state, state.canSetVolume else { return }
        let volume = min(max(volume, 0), 1)
        do {
            try Self.writeVolume(volume, of: state.deviceID)
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
                try Self.writeMute(muted, of: state.deviceID)
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
                try Self.writeVolume(0, of: state.deviceID)
            }
            catch {
                emulatedMuteVolumes[state.deviceUID] = nil
                throw error
            }
            state.volume = 0
        }
        else {
            let restored = emulatedMuteVolumes.removeValue(forKey: state.deviceUID) ?? state.volume
            try Self.writeVolume(restored, of: state.deviceID)
            state.volume = restored
        }
    }

    // MARK: - Observation

    private func defaultDeviceChanged() {
        let deviceID: AudioObjectID?
        do {
            deviceID = try Self.readDefaultOutputDevice()
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
        let uid = try Self.readString(kAudioDevicePropertyDeviceUID, of: deviceID)
        let name = try Self.readString(kAudioObjectPropertyName, of: deviceID)
        let canSetVolume = Self.isSettable(Self.virtualMainVolumeAddress, of: deviceID)
        // Without software volume the device plays at its fixed level, which is shown as full.
        var volume = canSetVolume ? try Self.readVolume(of: deviceID) : 1
        let hasHardwareMute = Self.isSettable(Self.muteAddress, of: deviceID)

        let isMuted: Bool
        if hasHardwareMute {
            isMuted = try Self.readMute(of: deviceID)
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
            hasHardwareMute: hasHardwareMute)
    }

    // MARK: - Property Addresses

    private static let defaultOutputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    /// Core Audio derives the virtual main volume from the per-channel controls; it behaves like the system volume slider.
    /// The HAL serves it through the regular AudioObject calls; the AudioHardwareService API is deprecated since macOS 10.11.
    private static let virtualMainVolumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    private static let observedDeviceAddresses = [
        virtualMainVolumeAddress,
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementWildcard),
        muteAddress
    ]

    // MARK: - Property Access

    private static func readDefaultOutputDevice() throws -> AudioObjectID? {
        var address = defaultOutputDeviceAddress
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
            .throwIfError("Reading the default output device")
        return deviceID == kAudioObjectUnknown ? nil : deviceID
    }

    private static func readString(_ selector: AudioObjectPropertySelector, of deviceID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        // Core Audio returns the string retained (+1), so it is taken as a retained value below.
        try withUnsafeMutablePointer(to: &value) { pointer in
            try AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer).throwIfError("Reading a device string")
        }
        guard let value else {
            throw CoreAudioError(status: kAudioHardwareUnspecifiedError, operation: "Reading a device string")
        }
        return value.takeRetainedValue() as String
    }

    private static func isSettable(_ address: AudioObjectPropertyAddress, of deviceID: AudioObjectID) -> Bool {
        var address = address
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var isSettable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr && isSettable.boolValue
    }

    private static func readVolume(of deviceID: AudioObjectID) throws -> Float32 {
        var address = virtualMainVolumeAddress
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        try AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume).throwIfError("Reading the volume")
        return volume
    }

    private static func writeVolume(_ volume: Float32, of deviceID: AudioObjectID) throws {
        var address = virtualMainVolumeAddress
        var volume = volume
        try AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
            .throwIfError("Setting the volume")
    }

    private static func readMute(of deviceID: AudioObjectID) throws -> Bool {
        var address = muteAddress
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted).throwIfError("Reading the mute state")
        return muted != 0
    }

    private static func writeMute(_ muted: Bool, of deviceID: AudioObjectID) throws {
        var address = muteAddress
        var value: UInt32 = muted ? 1 : 0
        try AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            .throwIfError("Setting the mute state")
    }
}
