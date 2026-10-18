import AudioToolbox
import CoreAudio

/// Typed access to the Core Audio properties Manopola reads and writes, shared by `AudioOutput` and `AudioDeviceList`.
enum CoreAudioProperty {
    /// Core Audio identifies a listener by the block pointer, so each block is stored as an Objective-C block once and
    /// the same instance is passed to both add and remove.
    typealias ListenerBlock = @convention(block) (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void

    // MARK: - Addresses

    static let defaultOutputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    /// Core Audio derives the virtual main volume from the per-channel controls; it behaves like the system volume slider.
    /// The HAL serves it through the regular AudioObject calls; the AudioHardwareService API is deprecated since macOS 10.11.
    static let virtualMainVolumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    // MARK: - Device Properties

    static func readDefaultOutputDevice() throws -> AudioObjectID? {
        var address = defaultOutputDeviceAddress
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
            .throwIfError("Reading the default output device")
        return deviceID == kAudioObjectUnknown ? nil : deviceID
    }

    static func readString(_ selector: AudioObjectPropertySelector, of deviceID: AudioObjectID) throws -> String {
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

    static func isSettable(_ address: AudioObjectPropertyAddress, of deviceID: AudioObjectID) -> Bool {
        var address = address
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var isSettable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr && isSettable.boolValue
    }

    static func readVolume(of deviceID: AudioObjectID) throws -> Float32 {
        var address = virtualMainVolumeAddress
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        try AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume).throwIfError("Reading the volume")
        return volume
    }

    static func writeVolume(_ volume: Float32, of deviceID: AudioObjectID) throws {
        var address = virtualMainVolumeAddress
        var volume = volume
        try AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
            .throwIfError("Setting the volume")
    }

    static func readMute(of deviceID: AudioObjectID) throws -> Bool {
        var address = muteAddress
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted).throwIfError("Reading the mute state")
        return muted != 0
    }

    static func writeMute(_ muted: Bool, of deviceID: AudioObjectID) throws {
        var address = muteAddress
        var value: UInt32 = muted ? 1 : 0
        try AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            .throwIfError("Setting the mute state")
    }

    // MARK: - Device List

    static let devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    static func readDeviceIDs() throws -> [AudioObjectID] {
        var address = devicesAddress
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        try AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size).throwIfError("Reading the device list size")
        var deviceIDs = [AudioObjectID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try deviceIDs.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            try AudioObjectGetPropertyData(system, &address, 0, nil, &size, base).throwIfError("Reading the device list")
        }
        return Array(deviceIDs.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// Input-only devices have no output streams.
    static func hasOutputStreams(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
    }

    static func isHidden(_ deviceID: AudioObjectID) -> Bool {
        (try? readUInt32(kAudioDevicePropertyIsHidden, of: deviceID)) ?? 0 != 0
    }

    static func readTransportType(of deviceID: AudioObjectID) -> UInt32 {
        (try? readUInt32(kAudioDevicePropertyTransportType, of: deviceID)) ?? 0
    }

    private static func readUInt32(_ selector: AudioObjectPropertySelector, of deviceID: AudioObjectID) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value).throwIfError("Reading a device property")
        return value
    }
}
