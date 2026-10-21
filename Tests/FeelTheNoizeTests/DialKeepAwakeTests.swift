import Testing

@testable import FeelTheNoize

struct DialKeepAwakeTests {
    @Test func runsOnlyWhileEnabledConnectedAndDisplaysAwake() {
        let keepAwake = DialKeepAwake {}
        #expect(keepAwake.isRunning == false)

        keepAwake.isEnabled = true
        #expect(keepAwake.isRunning == false)

        keepAwake.isDialConnected = true
        #expect(keepAwake.isRunning == true)

        keepAwake.areDisplaysAwake = false
        #expect(keepAwake.isRunning == false)

        keepAwake.areDisplaysAwake = true
        #expect(keepAwake.isRunning == true)

        keepAwake.isDialConnected = false
        #expect(keepAwake.isRunning == false)

        keepAwake.isDialConnected = true
        keepAwake.isEnabled = false
        #expect(keepAwake.isRunning == false)
    }

    @Test func stopEndsTheTimer() {
        let keepAwake = DialKeepAwake {}
        keepAwake.isEnabled = true
        keepAwake.isDialConnected = true
        keepAwake.stop()
        #expect(keepAwake.isRunning == false)
    }

    @Test func sendNowSendsOnlyWhileRunning() {
        var sendCount = 0
        let keepAwake = DialKeepAwake { sendCount += 1 }
        keepAwake.sendNow()
        #expect(sendCount == 0)

        keepAwake.isEnabled = true
        keepAwake.isDialConnected = true
        keepAwake.sendNow()
        keepAwake.stop()
        #expect(sendCount == 1)
    }

    @Test func sendsAfterEachIntervalAndNotAtStart() async {
        let sleeper = ManualSleeper()
        var sendCount = 0
        let keepAwake = DialKeepAwake(sleep: { duration in await sleeper.sleep(for: duration) }) { sendCount += 1 }
        keepAwake.isEnabled = true
        keepAwake.isDialConnected = true

        await sleeper.waitUntilAsleep()
        #expect(sendCount == 0, "The first report waits a full interval")

        await sleeper.wakeAndWaitUntilAsleep()
        #expect(sendCount == 1)

        await sleeper.wakeAndWaitUntilAsleep()
        #expect(sendCount == 2)
        #expect(sleeper.sleepCount == 3)

        keepAwake.stop()
        sleeper.release()
    }

    @Test func stopWhileAsleepSendsNothingMore() async {
        let sleeper = ManualSleeper()
        var sendCount = 0
        let keepAwake = DialKeepAwake(sleep: { duration in await sleeper.sleep(for: duration) }) { sendCount += 1 }
        keepAwake.isEnabled = true
        keepAwake.isDialConnected = true
        await sleeper.waitUntilAsleep()

        keepAwake.stop()
        sleeper.release()
        await Task.yield()
        #expect(sendCount == 0)
        #expect(keepAwake.isRunning == false)
    }
}
