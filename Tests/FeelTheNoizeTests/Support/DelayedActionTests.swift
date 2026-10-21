import Testing

@testable import FeelTheNoize

struct DelayedActionTests {
    @Test func runsOnceAfterTheDelayAndNotBefore() async -> Void {
        let sleeper = ManualSleeper()
        let action = DelayedAction(sleep: { duration in await sleeper.sleep(for: duration) })
        var runs = 0
        action.schedule(after: .seconds(1)) {
            runs += 1
        }
        #expect(action.isPending == true)

        await sleeper.waitUntilAsleep()
        #expect(runs == 0, "Nothing runs before the delay")

        await sleeper.releaseAndWait()
        #expect(runs == 1)
        #expect(action.isPending == false)
    }

    @Test func schedulingAgainReplacesThePendingAction() async -> Void {
        let sleeper = ManualSleeper()
        let action = DelayedAction(sleep: { duration in await sleeper.sleep(for: duration) })
        var ran: [String] = []
        action.schedule(after: .seconds(1)) {
            ran.append("first")
        }
        await sleeper.waitUntilAsleep()

        action.schedule(after: .seconds(1)) {
            ran.append("second")
        }
        await sleeper.waitUntilAsleep(count: 2)

        await sleeper.releaseAndWait()
        #expect(ran == ["second"])
        #expect(action.isPending == false)
    }

    @Test func cancelDropsThePendingAction() async -> Void {
        let sleeper = ManualSleeper()
        let action = DelayedAction(sleep: { duration in await sleeper.sleep(for: duration) })
        var runs = 0
        action.schedule(after: .seconds(1)) {
            runs += 1
        }
        await sleeper.waitUntilAsleep()

        action.cancel()
        #expect(action.isPending == false)
        await sleeper.releaseAndWait()
        #expect(runs == 0)
    }

    @Test func theActionMayScheduleAgain() async -> Void {
        let sleeper = ManualSleeper()
        let action = DelayedAction(sleep: { duration in await sleeper.sleep(for: duration) })
        var runs = 0
        action.schedule(after: .seconds(1)) {
            runs += 1
            action.schedule(after: .seconds(1)) {
                runs += 1
            }
        }
        await sleeper.waitUntilAsleep()
        await sleeper.releaseAndWait()
        #expect(runs == 1)
        #expect(action.isPending == true)

        await sleeper.waitUntilAsleep(count: 2)
        await sleeper.releaseAndWait()
        #expect(runs == 2)
        #expect(action.isPending == false)
    }
}
