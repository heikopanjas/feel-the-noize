/// A clock the test advances by hand, injected as the `now` closure of code that rate-limits by time.
final class TestClock {
    var now = ContinuousClock.now

    func advance(by duration: Duration) -> Void {
        self.now += duration
    }
}
