/// Notices volume writes that the device undoes, as AirPods do while another Apple device owns their audio
/// (Docs/DESIGN.md §7.4).
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
        return self.latestWrite != nil
    }

    mutating func willWrite(_ volume: Float32, current: Float32) -> Void {
        if self.baseline == nil {
            self.baseline = current
        }
        self.latestWrite = volume
    }

    mutating func didRead(_ volume: Float32) -> Void {
        guard let baseline = self.baseline else {
            self.clearRejection(unlessDeviceReturnedTo: volume)
            return
        }
        guard let latestWrite = self.latestWrite else {
            self.clearRejection(unlessDeviceReturnedTo: volume)
            return
        }
        // The echo of the write itself can arrive first; only a return to the baseline counts.
        if Self.isClose(volume, baseline) == true {
            if Self.isClose(volume, latestWrite) == false {
                self.didSnapBack = true
                self.isRejected = true
                self.rejectedVolume = baseline
            }
        }
    }

    /// Ends the window: a write that stood for the whole window clears the rejection.
    mutating func finish() -> Void {
        guard self.isPending == true else {
            return
        }
        if self.didSnapBack == false {
            self.isRejected = false
            self.rejectedVolume = nil
        }
        self.baseline = nil
        self.latestWrite = nil
        self.didSnapBack = false
    }

    /// Without a pending write, a volume other than the one the device returns to means a change got through.
    private mutating func clearRejection(unlessDeviceReturnedTo volume: Float32) -> Void {
        guard self.isRejected == true else {
            return
        }
        guard let rejectedVolume = self.rejectedVolume else {
            return
        }
        if Self.isClose(volume, rejectedVolume) == false {
            self.isRejected = false
            self.rejectedVolume = nil
        }
    }

    private static func isClose(_ a: Float32, _ b: Float32) -> Bool {
        return abs(a - b) < Self.tolerance
    }
}
