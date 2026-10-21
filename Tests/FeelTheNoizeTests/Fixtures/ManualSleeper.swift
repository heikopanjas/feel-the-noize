/// Stands in for `Task.sleep` in tests of timer code. The code under test parks in `sleep(for:)`; the test releases it
/// with `wakeAndWaitUntilAsleep()` and gets control back once the code has done its work and parked again. Everything
/// is driven by continuations on the main actor, so no test waits on wall-clock time and the order of events is fixed.
final class ManualSleeper {
    /// How often the code under test went to sleep.
    private(set) var sleepCount = 0

    private var sleeper: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    /// Passed to the code under test in place of `Task.sleep`; the duration is ignored.
    func sleep(for duration: Duration) async -> Void {
        self.sleepCount += 1
        await withCheckedContinuation { continuation in
            self.sleeper = continuation
            self.waiter?.resume()
            self.waiter = nil
        }
    }

    /// Returns once the code under test is parked in `sleep(for:)`.
    func waitUntilAsleep() async -> Void {
        if self.sleeper != nil {
            return
        }
        await withCheckedContinuation { continuation in
            self.waiter = continuation
        }
    }

    /// Ends the current sleep and returns once the code under test is parked in the next one.
    func wakeAndWaitUntilAsleep() async -> Void {
        self.release()
        await self.waitUntilAsleep()
    }

    /// Ends the current sleep without waiting, so cancelled code can notice its cancellation and exit.
    func release() -> Void {
        let sleeper = self.sleeper
        self.sleeper = nil
        sleeper?.resume()
    }
}
