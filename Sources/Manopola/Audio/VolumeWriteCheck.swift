/// Notices volume writes that the device undoes, as AirPods do while another Apple device owns their audio
/// (docs/DESIGN.md §7.4).
///
/// Core Audio has no property for that ownership: the AirPods stay connected and report a settable volume, but restore
/// the previous value 5 to 17 ms after every write (measured 2026-10-19).
struct VolumeWriteCheck {
    /// Wide margin over the measured snap-back time; the caller calls `finish()` this long after the last write.
    static let window: Duration = .milliseconds(250)
    private static let tolerance: Float32 = 0.0001

    /// The device undid the last write and nothing has changed the volume since.
    private(set) var isRejected = false
    /// The volume before the first write of the current window. During a fast spin several writes are pending at once,
    /// and the snap-back returns to this value, not to the one before the latest write.
    private var baseline: Float32?
    private var latestWrite: Float32?
    private var didSnapBack = false
    /// The volume the device keeps returning to while rejected.
    private var rejectedVolume: Float32?

    var isPending: Bool {
        latestWrite != nil
    }

    mutating func willWrite(_ volume: Float32, current: Float32) {
        if baseline == nil {
            baseline = current
        }
        latestWrite = volume
    }

    mutating func didRead(_ volume: Float32) {
        guard let baseline, let latestWrite else {
            // Without a pending write, a volume other than the one the device returns to means a change got through.
            if isRejected, let rejectedVolume, !Self.isClose(volume, rejectedVolume) {
                isRejected = false
                self.rejectedVolume = nil
            }
            return
        }
        // The echo of the write itself can arrive first; only a return to the baseline counts.
        if Self.isClose(volume, baseline), !Self.isClose(volume, latestWrite) {
            didSnapBack = true
            isRejected = true
            rejectedVolume = baseline
        }
    }

    /// Ends the window: a write that stood for the whole window clears the rejection.
    mutating func finish() {
        guard isPending else { return }
        if !didSnapBack {
            isRejected = false
            rejectedVolume = nil
        }
        baseline = nil
        latestWrite = nil
        didSnapBack = false
    }

    private static func isClose(_ a: Float32, _ b: Float32) -> Bool {
        abs(a - b) < tolerance
    }
}
