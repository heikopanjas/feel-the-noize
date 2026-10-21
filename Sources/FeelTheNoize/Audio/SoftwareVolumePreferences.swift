/// Where `AudioOutput` learns whether a device should get software volume and keeps its level (Docs/DESIGN.md §7.9);
/// `Settings` conforms.
protocol SoftwareVolumePreferences: AnyObject {
    func wantsSoftwareVolume(_ uid: String) -> Bool
    func softwareVolumeLevel(_ uid: String) -> Float
    func setSoftwareVolumeLevel(_ uid: String, _ level: Float) -> Void
}
