/// What `AudioOutput` needs from the software volume (Docs/DESIGN.md §7.9): `SoftwareVolume` in the app, a fake in the
/// tests, so the state machine around it runs without a process tap.
protocol SoftwareVolumeControlling: AnyObject {
    /// The device being controlled, or `nil` while stopped.
    var deviceUID: String? { get }
    /// 0…1 as shown to the user.
    var level: Float { get set }

    func start(deviceUID: String, level: Float) throws -> Void
    func stop() -> Void
}
