import Testing

@testable import FeelTheNoize

struct DelayedActionTests {
    @Test func runsOnceAfterTheDelayAndNotBefore() async {
        let sleeper = ManualSleeper()
        let action = DelayedAction(sleep: { duration in await sleeper.sleep(for: duration) })
        var runs = 0
        var finished: CheckedContinuation<Void, Never>?
        action.schedule(after: .seconds(1)) {
            runs += 1
            finished?.resume()
            finished = nil
        }
        #expect(action.isPending == true)

        await sleeper.waitUntilAsleep()
        #expect(runs == 0, "Nothing runs before the delay")

        await withCheckedContinuation { continuation in
            finished = continuation
            sleeper.release()
        }
        #expect(runs == 1)
        #expect(action.isPending == false)
    }

    @Test func schedulingAgainReplacesThePendingAction() async {
        let sleeper = ManualSleeper()
        let action = DelayedAction(sleep: { duration in await sleeper.sleep(for: duration) })
        var ran: [String] = []
        var finished: CheckedContinuation<Void, Never>?
        action.schedule(after: .seconds(1)) {
            ran.append("first")
        }
        await sleeper.waitUntilAsleep()

        action.schedule(after: .seconds(1)) {
            ran.append("second")
            finished?.resume()
            finished = nil
        }
        await sleeper.waitUntilAsleep(count: 2)

        await withCheckedContinuation { continuation in
            finished = continuation
            sleeper.release()
        }
        #expect(ran == ["second"])
        #expect(action.isPending == false)
    }

    @Test func cancelDropsThePendingAction() async {
        let sleeper = ManualSleeper()
        let action = DelayedAction(sleep: { duration in await sleeper.sleep(for: duration) })
        var runs = 0
        action.schedule(after: .seconds(1)) {
            runs += 1
        }
        await sleeper.waitUntilAsleep()

        action.cancel()
        #expect(action.isPending == false)
        sleeper.release()
        await Task.yield()
        #expect(runs == 0)
    }
}
