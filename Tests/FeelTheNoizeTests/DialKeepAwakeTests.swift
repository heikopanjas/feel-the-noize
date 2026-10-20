import Testing

@testable import FeelTheNoize

struct DialKeepAwakeTests {
    @Test func runsOnlyWhileEnabledConnectedAndDisplaysAwake() {
        let keepAwake = DialKeepAwake {}
        #expect(!keepAwake.isRunning)

        keepAwake.isEnabled = true
        #expect(!keepAwake.isRunning)

        keepAwake.isDialConnected = true
        #expect(keepAwake.isRunning)

        keepAwake.areDisplaysAwake = false
        #expect(!keepAwake.isRunning)

        keepAwake.areDisplaysAwake = true
        #expect(keepAwake.isRunning)

        keepAwake.isDialConnected = false
        #expect(!keepAwake.isRunning)

        keepAwake.isDialConnected = true
        keepAwake.isEnabled = false
        #expect(!keepAwake.isRunning)
    }

    @Test func stopEndsTheTimer() {
        let keepAwake = DialKeepAwake {}
        keepAwake.isEnabled = true
        keepAwake.isDialConnected = true
        keepAwake.stop()
        #expect(!keepAwake.isRunning)
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

    @Test func sendsAfterEachInterval() async {
        var sendCount = 0
        let keepAwake = DialKeepAwake(interval: .milliseconds(10)) { sendCount += 1 }
        keepAwake.isEnabled = true
        keepAwake.isDialConnected = true
        #expect(sendCount == 0)

        let deadline = ContinuousClock.now + .seconds(2)
        while sendCount < 2, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        keepAwake.stop()
        #expect(sendCount >= 2)
    }
}
