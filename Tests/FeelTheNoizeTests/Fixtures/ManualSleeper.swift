/// Stands in for `Task.sleep` in tests of timer code. The code under test parks in `sleep(for:)`; the test releases it
/// with `release()` or `wakeAndWaitUntilAsleep()` and gets control back once the code has parked again. Everything is
/// driven by continuations on the main actor, so no test waits on wall-clock time and the order of events is fixed.
final class ManualSleeper {
    /// How often the code under test went to sleep, in total.
    private(set) var sleepCount = 0

    /// Every sleep that has not been released; a replaced timer leaves its cancelled task parked here until the release.
    private var sleepers: [CheckedContinuation<Void, Never>] = []
    private var waiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?

    /// Passed to the code under test in place of `Task.sleep`; the duration is ignored.
    func sleep(for duration: Duration) async -> Void {
        self.sleepCount += 1
        await withCheckedContinuation { continuation in
            self.sleepers.append(continuation)
            if let waiter = self.waiter, self.sleepCount >= waiter.count {
                self.waiter = nil
                waiter.continuation.resume()
            }
        }
    }

    /// Returns once the code under test has gone to sleep `count` times in total.
    func waitUntilAsleep(count: Int = 1) async -> Void {
        if self.sleepCount >= count {
            return
        }
        await withCheckedContinuation { continuation in
            self.waiter = (count: count, continuation: continuation)
        }
    }

    /// Ends every current sleep and returns once the code under test has gone to sleep once more.
    func wakeAndWaitUntilAsleep() async -> Void {
        let target = self.sleepCount + 1
        self.release()
        await self.waitUntilAsleep(count: target)
    }

    /// Ends every current sleep without waiting, so cancelled code can notice its cancellation and exit.
    func release() -> Void {
        let sleepers = self.sleepers
        self.sleepers = []
        for sleeper in sleepers {
            sleeper.resume()
        }
    }
}
