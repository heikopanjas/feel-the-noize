import AudioToolbox
import CoreAudio
import Foundation

/// Typed access to the Core Audio properties Feel the Noize reads and writes (Docs/DESIGN.md §7.4). The audio adapters reach
/// them through `CoreAudioAccess` and `CoreAudioHAL`; `AppDelegate` and `SoftwareVolume` call them directly.
enum CoreAudioProperty {
    /// Core Audio identifies a listener by the block pointer, so each block is stored as an Objective-C block once and
    /// the same instance is passed to both add and remove.
    typealias ListenerBlock = @convention(block) (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void

    // MARK: - Addresses

    static let defaultOutputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    static let defaultInputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    /// Core Audio derives the virtual main volume from the per-channel controls; it behaves like the system volume slider.
    /// The HAL serves it through the regular AudioObject calls; the AudioHardwareService API is deprecated since macOS 10.11.
    static let virtualMainVolumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    static let devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    // MARK: - Default Devices

    /// `scope` is `kAudioDevicePropertyScopeOutput` or `kAudioDevicePropertyScopeInput`.
    static func readDefaultDevice(scope: AudioObjectPropertyScope) throws -> AudioObjectID? {
        var address = Self.defaultDeviceAddress(scope: scope)
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try AudioObjectGetPropertyData(Self.systemObject, &address, 0, nil, &size, &deviceID).throwIfError("Reading the default device")
        return deviceID == kAudioObjectUnknown ? nil : deviceID
    }

    static func writeDefaultDevice(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) throws -> Void {
        var address = Self.defaultDeviceAddress(scope: scope)
        var deviceID = deviceID
        try AudioObjectSetPropertyData(Self.systemObject, &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &deviceID)
            .throwIfError("Setting the default device")
    }

    /// `nil` when no connected device has this UID, for example after it disconnected while the menu was open.
    static func readDevice(uid: String) throws -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid = uid as CFString
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try AudioObjectGetPropertyData(Self.systemObject, &address, UInt32(MemoryLayout<CFString>.size), &uid, &size, &deviceID)
            .throwIfError("Looking up a device by UID")
        return deviceID == kAudioObjectUnknown ? nil : deviceID
    }

    /// The default device properties live in the global scope of the system object; the direction picks the selector.
    private static func defaultDeviceAddress(scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        return scope == kAudioDevicePropertyScopeInput ? Self.defaultInputDeviceAddress : Self.defaultOutputDeviceAddress
    }

    // MARK: - Device Properties

    static func readString(_ selector: AudioObjectPropertySelector, of deviceID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        // Core Audio returns the string retained (+1), so it is taken as a retained value below.
        try withUnsafeMutablePointer(to: &value) { pointer in
            try AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer).throwIfError("Reading a device string")
        }
        if let value = value {
            return value.takeRetainedValue() as String
        }
        throw CoreAudioError(status: kAudioHardwareUnspecifiedError, operation: "Reading a device string")
    }

    static func isSettable(_ address: AudioObjectPropertyAddress, of deviceID: AudioObjectID) -> Bool {
        var address = address
        if AudioObjectHasProperty(deviceID, &address) == false {
            return false
        }
        var isSettable: DarwinBoolean = false
        if AudioObjectIsPropertySettable(deviceID, &address, &isSettable) != noErr {
            return false
        }
        return isSettable.boolValue
    }

    static func readVolume(of deviceID: AudioObjectID) throws -> Float32 {
        var address = Self.virtualMainVolumeAddress
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        try AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume).throwIfError("Reading the volume")
        return volume
    }

    static func writeVolume(_ volume: Float32, of deviceID: AudioObjectID) throws -> Void {
        var address = Self.virtualMainVolumeAddress
        var volume = volume
        try AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
            .throwIfError("Setting the volume")
    }

    static func readMute(of deviceID: AudioObjectID) throws -> Bool {
        var address = Self.muteAddress
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted).throwIfError("Reading the mute state")
        return muted != 0
    }

    static func writeMute(_ muted: Bool, of deviceID: AudioObjectID) throws -> Void {
        var address = Self.muteAddress
        var value: UInt32 = muted == true ? 1 : 0
        try AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            .throwIfError("Setting the mute state")
    }

    // MARK: - Device List

    static func readDeviceIDs() throws -> [AudioObjectID] {
        var address = Self.devicesAddress
        var size: UInt32 = 0
        try AudioObjectGetPropertyDataSize(Self.systemObject, &address, 0, nil, &size).throwIfError("Reading the device list size")
        var deviceIDs = [AudioObjectID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try deviceIDs.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else {
                return
            }
            try AudioObjectGetPropertyData(Self.systemObject, &address, 0, nil, &size, base).throwIfError("Reading the device list")
        }
        return Array(deviceIDs.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// Input-only devices have no output streams, output-only devices no input streams.
    static func hasStreams(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        if AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) != noErr {
            return false
        }
        return size > 0
    }

    static func isHidden(_ deviceID: AudioObjectID) -> Bool {
        let hidden = (try? Self.readUInt32(kAudioDevicePropertyIsHidden, of: deviceID)) ?? 0
        return hidden != 0
    }

    static func readTransportType(of deviceID: AudioObjectID) -> UInt32 {
        return (try? Self.readUInt32(kAudioDevicePropertyTransportType, of: deviceID)) ?? 0
    }

    /// `nil` for devices without a selectable output source; most have none.
    static func readOutputDataSource(of deviceID: AudioObjectID) -> UInt32? {
        return try? Self.readUInt32(kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput, of: deviceID)
    }

    // MARK: - Software Volume

    /// The Core Audio process object of Feel the Noize itself, so a tap can leave its own audio out.
    static func readOwnProcessObject() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var pid = ProcessInfo.processInfo.processIdentifier
        var processObject = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try AudioObjectGetPropertyData(Self.systemObject, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &processObject)
            .throwIfError("Looking up the own process object")
        return processObject
    }

    /// Channel count of each buffer the device delivers in an IO cycle, in buffer order.
    static func readBufferChannelCounts(of deviceID: AudioObjectID, scope: AudioObjectPropertyScope) throws -> [Int] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size).throwIfError("Reading the stream configuration size")
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        try AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw).throwIfError("Reading the stream configuration")
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.map { Int($0.mNumberChannels) }
    }

    private static func readUInt32(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, of deviceID: AudioObjectID
    ) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value).throwIfError("Reading a device property")
        return value
    }
}
