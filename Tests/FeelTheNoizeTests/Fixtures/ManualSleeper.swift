/// Stands in for `Task.sleep` in tests of timer code. The code under test parks in `sleep(for:)`; the test releases it
/// with `releaseAndWait()` or `wakeAndWaitUntilAsleep()` and gets control back once the woken code has run on. Everything
/// is driven by continuations on the main actor, so no test waits on wall-clock time and the order of events is fixed.
final class ManualSleeper {
    /// How often the code under test went to sleep, in total.
    private(set) var sleepCount = 0
    /// How often a sleep ended because the test released it.
    private(set) var wokeCount = 0

    /// Every sleep that has not been released; a replaced timer leaves its cancelled task parked here until the release.
    private var sleepers: [CheckedContinuation<Void, Never>] = []
    private var sleepWaiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?
    private var wakeWaiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?

    var isAsleep: Bool {
        return self.sleepers.isEmpty == false
    }

    /// Passed to the code under test in place of `Task.sleep`; the duration is ignored. Like `Task.sleep`, it returns at
    /// once when the task is already cancelled.
    func sleep(for duration: Duration) async -> Void {
        self.sleepCount += 1
        if Task.isCancelled == true {
            return
        }
        await withCheckedContinuation { continuation in
            self.sleepers.append(continuation)
            if let waiter = self.sleepWaiter, self.sleepCount >= waiter.count {
                self.sleepWaiter = nil
                waiter.continuation.resume()
            }
        }
        // The woken code runs on from here to its next suspension or its end before the resumed test gets the actor.
        self.wokeCount += 1
        if let waiter = self.wakeWaiter, self.wokeCount >= waiter.count {
            self.wakeWaiter = nil
            waiter.continuation.resume()
        }
    }

    /// Returns once the code under test has gone to sleep `count` times in total.
    func waitUntilAsleep(count: Int = 1) async -> Void {
        if self.sleepCount >= count {
            return
        }
        await withCheckedContinuation { continuation in
            self.sleepWaiter = (count: count, continuation: continuation)
        }
    }

    /// Ends every current sleep and returns once each woken piece of code has run to its next suspension or its end.
    func releaseAndWait() async -> Void {
        let target = self.wokeCount + self.sleepers.count
        self.release()
        if self.wokeCount >= target {
            return
        }
        await withCheckedContinuation { continuation in
            self.wakeWaiter = (count: target, continuation: continuation)
        }
    }

    /// Ends every current sleep and returns once the code under test has gone to sleep once more, for timer loops.
    func wakeAndWaitUntilAsleep() async -> Void {
        let target = self.sleepCount + 1
        self.release()
        await self.waitUntilAsleep(count: target)
    }

    /// Ends every current sleep without waiting.
    func release() -> Void {
        let sleepers = self.sleepers
        self.sleepers = []
        for sleeper in sleepers {
            sleeper.resume()
        }
    }
}
