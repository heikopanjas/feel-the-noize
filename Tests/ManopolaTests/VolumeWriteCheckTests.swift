import Testing

@testable import Manopola

struct VolumeWriteCheckTests {
    @Test func acceptedWriteIsNotRejected() {
        var check = VolumeWriteCheck()
        check.willWrite(0.51, current: 0.50)
        check.didRead(0.51)
        check.finish()
        #expect(!check.isRejected)
        #expect(!check.isPending)
    }

    @Test func snapBackAfterTheEchoIsRejected() {
        var check = VolumeWriteCheck()
        check.willWrite(0.51, current: 0.50)
        check.didRead(0.51)
        check.didRead(0.50)
        #expect(check.isRejected)
        check.finish()
        #expect(check.isRejected)
    }

    @Test func fastSpinSnapsBackToTheVolumeBeforeTheFirstWrite() {
        var check = VolumeWriteCheck()
        check.willWrite(0.51, current: 0.50)
        check.willWrite(0.52, current: 0.51)
        check.didRead(0.50)
        #expect(check.isRejected)
    }

    @Test func acceptedProbeClearsTheRejection() {
        var check = VolumeWriteCheck()
        check.willWrite(0.51, current: 0.50)
        check.didRead(0.50)
        check.finish()

        check.willWrite(0.51, current: 0.50)
        check.didRead(0.51)
        #expect(check.isRejected)
        check.finish()
        #expect(!check.isRejected)
    }

    @Test func rejectedProbeKeepsTheRejection() {
        var check = VolumeWriteCheck()
        check.willWrite(0.51, current: 0.50)
        check.didRead(0.50)
        check.finish()

        check.willWrite(0.49, current: 0.50)
        check.didRead(0.50)
        check.finish()
        #expect(check.isRejected)
    }

    @Test func outsideChangeClearsTheRejection() {
        var check = VolumeWriteCheck()
        check.willWrite(0.51, current: 0.50)
        check.didRead(0.50)
        check.finish()

        check.didRead(0.50)
        #expect(check.isRejected)
        check.didRead(0.60)
        #expect(!check.isRejected)
    }
}
