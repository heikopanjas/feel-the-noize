@testable import FeelTheNoize

/// Software volume without a process tap: remembers the device and level, counts starts and stops, and fails to start
/// when told to.
final class FakeSoftwareVolume: SoftwareVolumeControlling {
    private(set) var deviceUID: String?
    var level: Float = 1
    /// Thrown by every `start` while set.
    var startError: (any Error)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(deviceUID: String, level: Float) throws -> Void {
        self.startCount += 1
        if let error = self.startError {
            throw error
        }
        self.deviceUID = deviceUID
        self.level = level
    }

    /// Counts only a stop that ends a running software volume, as the real one logs.
    func stop() -> Void {
        if self.deviceUID != nil {
            self.stopCount += 1
        }
        self.deviceUID = nil
    }
}
