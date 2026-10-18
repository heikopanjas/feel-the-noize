import CoreAudio

/// Snapshot of the default output device as published by `AudioOutput`.
struct AudioState: Equatable {
    var deviceID: AudioObjectID
    var deviceUID: String
    var deviceName: String
    /// 0...1, virtual main volume.
    var volume: Float32
    var isMuted: Bool
    var canSetVolume: Bool
    var hasHardwareMute: Bool
    /// The volume is Manopola's software gain, because the device has no volume control of its own (§7.9).
    var isSoftwareVolume = false
}
