import CoreAudio

/// The production `CoreAudioAccess`: the HAL, through the `CoreAudioProperty` helpers and the listener block calls.
struct CoreAudioHAL: CoreAudioAccess {
    func readDefaultDevice(scope: AudioObjectPropertyScope) throws -> AudioObjectID? {
        return try CoreAudioProperty.readDefaultDevice(scope: scope)
    }

    func writeDefaultDevice(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) throws -> Void {
        try CoreAudioProperty.writeDefaultDevice(deviceID, scope: scope)
    }

    func readDevice(uid: String) throws -> AudioObjectID? {
        return try CoreAudioProperty.readDevice(uid: uid)
    }

    func readDeviceIDs() throws -> [AudioObjectID] {
        return try CoreAudioProperty.readDeviceIDs()
    }

    func readString(_ selector: AudioObjectPropertySelector, of deviceID: AudioObjectID) throws -> String {
        return try CoreAudioProperty.readString(selector, of: deviceID)
    }

    func isSettable(_ address: AudioObjectPropertyAddress, of deviceID: AudioObjectID) -> Bool {
        return CoreAudioProperty.isSettable(address, of: deviceID)
    }

    func hasStreams(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        return CoreAudioProperty.hasStreams(deviceID, scope: scope)
    }

    func isHidden(_ deviceID: AudioObjectID) -> Bool {
        return CoreAudioProperty.isHidden(deviceID)
    }

    func readTransportType(of deviceID: AudioObjectID) -> UInt32 {
        return CoreAudioProperty.readTransportType(of: deviceID)
    }

    func readOutputDataSource(of deviceID: AudioObjectID) -> UInt32? {
        return CoreAudioProperty.readOutputDataSource(of: deviceID)
    }

    func readVolume(of deviceID: AudioObjectID) throws -> Float32 {
        return try CoreAudioProperty.readVolume(of: deviceID)
    }

    func writeVolume(_ volume: Float32, of deviceID: AudioObjectID) throws -> Void {
        try CoreAudioProperty.writeVolume(volume, of: deviceID)
    }

    func readMute(of deviceID: AudioObjectID) throws -> Bool {
        return try CoreAudioProperty.readMute(of: deviceID)
    }

    func writeMute(_ muted: Bool, of deviceID: AudioObjectID) throws -> Void {
        try CoreAudioProperty.writeMute(muted, of: deviceID)
    }

    func addListener(
        _ listener: CoreAudioProperty.ListenerBlock, for address: AudioObjectPropertyAddress, on objectID: AudioObjectID
    ) -> OSStatus {
        var address = address
        return AudioObjectAddPropertyListenerBlock(objectID, &address, .main, listener)
    }

    func removeListener(
        _ listener: CoreAudioProperty.ListenerBlock, for address: AudioObjectPropertyAddress, on objectID: AudioObjectID
    ) -> Void {
        var address = address
        AudioObjectRemovePropertyListenerBlock(objectID, &address, .main, listener)
    }
}
