import IOKit
import Testing

@testable import Manopola

struct UserActivityTests {
    @Test func declaresAtMostOncePerInterval() {
        var declarationCount = 0
        let activity = UserActivity(minimumInterval: .seconds(60)) {
            declarationCount += 1
            return kIOReturnSuccess
        }
        activity.declare()
        activity.declare()
        activity.declare()
        #expect(declarationCount == 1)
    }

    @Test func declaresAgainAfterTheInterval() {
        var declarationCount = 0
        let activity = UserActivity(minimumInterval: .zero) {
            declarationCount += 1
            return kIOReturnSuccess
        }
        activity.declare()
        activity.declare()
        #expect(declarationCount == 2)
    }

    @Test func keepsDeclaringAfterAFailure() {
        var declarationCount = 0
        let activity = UserActivity(minimumInterval: .zero) {
            declarationCount += 1
            return kIOReturnError
        }
        activity.declare()
        activity.declare()
        #expect(declarationCount == 2)
    }
}
