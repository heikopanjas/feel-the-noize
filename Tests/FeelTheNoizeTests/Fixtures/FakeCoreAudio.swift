import CoreAudio

@testable import FeelTheNoize

/// An in-memory HAL for the audio adapters: devices by object ID, the two defaults, recorded writes and listeners the
/// test fires with `notify(_:on:)`.
final class FakeCoreAudio: CoreAudioAccess {
    struct Device {
        var uid: String
        var name: String
        /// `nil` means the device has no volume control.
        var volume: Float32?
        /// `nil` means the device has no mute control.
        var isMuted: Bool?
        var hasOutput = true
        var hasInput = false
        var isHidden = false
        var transportType: UInt32 = kAudioDeviceTransportTypeUSB
        var modelUID: String?
        var outputDataSource: UInt32?
    }

    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    var devices: [AudioObjectID: Device] = [:]
    var defaultOutputID: AudioObjectID?
    var defaultInputID: AudioObjectID?
    /// Undoes every volume write, as AirPods do while another device owns their audio: the stored volume stays.
    var rejectsVolumeWrites = false

    private(set) var volumeWrites: [Float32] = []
    private(set) var muteWrites: [Bool] = []
    private(set) var defaultInputWrites: [AudioObjectID] = []

    private var listeners: [(objectID: AudioObjectID, selector: AudioObjectPropertySelector, block: CoreAudioProperty.ListenerBlock)] = []

    var listenerCount: Int {
        return self.listeners.count
    }

    /// Delivers a property change to every listener registered for `selector` on `objectID`, as the HAL would.
    func notify(_ selector: AudioObjectPropertySelector, on objectID: AudioObjectID) -> Void {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let blocks = self.listeners.filter { $0.objectID == objectID && $0.selector == selector }.map(\.block)
        for block in blocks {
            withUnsafePointer(to: &address) { pointer in
                block(1, pointer)
            }
        }
    }

    // MARK: - CoreAudioAccess

    func readDefaultDevice(scope: AudioObjectPropertyScope) throws -> AudioObjectID? {
        if scope == kAudioDevicePropertyScopeInput {
            return self.defaultInputID
        }
        return self.defaultOutputID
    }

    func writeDefaultDevice(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) throws -> Void {
        _ = try self.device(deviceID, operation: "Setting the default device")
        if scope == kAudioDevicePropertyScopeInput {
            self.defaultInputWrites.append(deviceID)
            self.defaultInputID = deviceID
        }
        else {
            self.defaultOutputID = deviceID
        }
    }

    func readDevice(uid: String) throws -> AudioObjectID? {
        return self.devices.first { $0.value.uid == uid }?.key
    }

    func readDeviceIDs() throws -> [AudioObjectID] {
        return self.devices.keys.sorted()
    }

    func readString(_ selector: AudioObjectPropertySelector, of deviceID: AudioObjectID) throws -> String {
        let device = try self.device(deviceID, operation: "Reading a device string")
        switch selector {
            case kAudioDevicePropertyDeviceUID:
                return device.uid
            case kAudioObjectPropertyName:
                return device.name
            case kAudioDevicePropertyModelUID:
                guard let modelUID = device.modelUID else {
                    throw CoreAudioError(status: kAudioHardwareUnknownPropertyError, operation: "Reading a device string")
                }
                return modelUID
            default:
                throw CoreAudioError(status: kAudioHardwareUnknownPropertyError, operation: "Reading a device string")
        }
    }

    func isSettable(_ address: AudioObjectPropertyAddress, of deviceID: AudioObjectID) -> Bool {
        guard let device = self.devices[deviceID] else {
            return false
        }
        switch address.mSelector {
            case kAudioHardwareServiceDeviceProperty_VirtualMainVolume:
                return device.volume != nil
            case kAudioDevicePropertyMute:
                return device.isMuted != nil
            default:
                return false
        }
    }

    func hasStreams(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        guard let device = self.devices[deviceID] else {
            return false
        }
        if scope == kAudioDevicePropertyScopeInput {
            return device.hasInput
        }
        return device.hasOutput
    }

    func isHidden(_ deviceID: AudioObjectID) -> Bool {
        return self.devices[deviceID]?.isHidden ?? false
    }

    func readTransportType(of deviceID: AudioObjectID) -> UInt32 {
        return self.devices[deviceID]?.transportType ?? 0
    }

    func readOutputDataSource(of deviceID: AudioObjectID) -> UInt32? {
        return self.devices[deviceID]?.outputDataSource
    }

    func readVolume(of deviceID: AudioObjectID) throws -> Float32 {
        guard let volume = try self.device(deviceID, operation: "Reading the volume").volume else {
            throw CoreAudioError(status: kAudioHardwareUnknownPropertyError, operation: "Reading the volume")
        }
        return volume
    }

    func writeVolume(_ volume: Float32, of deviceID: AudioObjectID) throws -> Void {
        guard self.devices[deviceID]?.volume != nil else {
            throw CoreAudioError(status: kAudioHardwareUnknownPropertyError, operation: "Setting the volume")
        }
        self.volumeWrites.append(volume)
        if self.rejectsVolumeWrites == false {
            self.devices[deviceID]?.volume = volume
        }
    }

    func readMute(of deviceID: AudioObjectID) throws -> Bool {
        guard let isMuted = try self.device(deviceID, operation: "Reading the mute state").isMuted else {
            throw CoreAudioError(status: kAudioHardwareUnknownPropertyError, operation: "Reading the mute state")
        }
        return isMuted
    }

    func writeMute(_ muted: Bool, of deviceID: AudioObjectID) throws -> Void {
        guard self.devices[deviceID]?.isMuted != nil else {
            throw CoreAudioError(status: kAudioHardwareUnknownPropertyError, operation: "Setting the mute state")
        }
        self.muteWrites.append(muted)
        self.devices[deviceID]?.isMuted = muted
    }

    func addListener(
        _ listener: CoreAudioProperty.ListenerBlock, for address: AudioObjectPropertyAddress, on objectID: AudioObjectID
    ) -> OSStatus {
        self.listeners.append((objectID: objectID, selector: address.mSelector, block: listener))
        return noErr
    }

    func removeListener(
        _ listener: CoreAudioProperty.ListenerBlock, for address: AudioObjectPropertyAddress, on objectID: AudioObjectID
    ) -> Void {
        // The HAL identifies a listener by its block; so does this fake.
        let identity = ObjectIdentifier(listener as AnyObject)
        self.listeners.removeAll { entry in
            return entry.objectID == objectID && entry.selector == address.mSelector && ObjectIdentifier(entry.block as AnyObject) == identity
        }
    }

    private func device(_ deviceID: AudioObjectID, operation: String) throws -> Device {
        guard let device = self.devices[deviceID] else {
            throw CoreAudioError(status: kAudioHardwareBadObjectError, operation: operation)
        }
        return device
    }
}
