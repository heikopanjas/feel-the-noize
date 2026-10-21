/// What `DialController` needs from the audio output (Docs/DESIGN.md §7.3); `AudioOutput` conforms, the tests use a fake.
protocol AudioControlling: AnyObject {
    var state: AudioState? { get }

    func setVolume(_ volume: Float32) -> Void
    func setMuted(_ muted: Bool) -> Void
}
