import CoreAudio

/// The Core Audio calls `AudioOutput`, `AudioDeviceList` and `InputDeviceKeeper` make, as an injectable seam
/// (Docs/DESIGN.md §7.4): `CoreAudioHAL` in the app, `FakeCoreAudio` in the tests.
protocol CoreAudioAccess {
    /// `scope` is `kAudioDevicePropertyScopeOutput` or `kAudioDevicePropertyScopeInput`; `nil` when there is no default.
    func readDefaultDevice(scope: AudioObjectPropertyScope) throws -> AudioObjectID?
    func writeDefaultDevice(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) throws -> Void
    /// `nil` when no connected device has this UID.
    func readDevice(uid: String) throws -> AudioObjectID?
    func readDeviceIDs() throws -> [AudioObjectID]
    func readString(_ selector: AudioObjectPropertySelector, of deviceID: AudioObjectID) throws -> String
    func isSettable(_ address: AudioObjectPropertyAddress, of deviceID: AudioObjectID) -> Bool
    func hasStreams(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool
    func isHidden(_ deviceID: AudioObjectID) -> Bool
    func readTransportType(of deviceID: AudioObjectID) -> UInt32
    func readOutputDataSource(of deviceID: AudioObjectID) -> UInt32?
    func readVolume(of deviceID: AudioObjectID) throws -> Float32
    func writeVolume(_ volume: Float32, of deviceID: AudioObjectID) throws -> Void
    func readMute(of deviceID: AudioObjectID) throws -> Bool
    func writeMute(_ muted: Bool, of deviceID: AudioObjectID) throws -> Void
    /// Registers `listener` on the main queue; Core Audio identifies it by the block instance, so the same instance is
    /// passed to `removeListener`.
    func addListener(
        _ listener: @escaping CoreAudioProperty.ListenerBlock, for address: AudioObjectPropertyAddress, on objectID: AudioObjectID
    ) -> OSStatus
    func removeListener(
        _ listener: @escaping CoreAudioProperty.ListenerBlock, for address: AudioObjectPropertyAddress, on objectID: AudioObjectID
    ) -> Void
}
