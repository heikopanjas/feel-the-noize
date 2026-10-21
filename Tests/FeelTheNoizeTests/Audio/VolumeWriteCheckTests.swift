import Testing

@testable import FeelTheNoize

struct VolumeWriteCheckTests {
    @Test func acceptedWriteIsNotRejected() -> Void {
        var check = VolumeWriteCheck()
        check.willWrite(0.51, current: 0.50)
        check.didRead(0.51)
        check.finish()
        #expect(check.isRejected == false)
        #expect(check.isPending == false)
    }

    @Test func snapBackAfterTheEchoIsRejected() -> Void {
        var check = VolumeWriteCheck()
        check.willWrite(0.51, current: 0.50)
        check.didRead(0.51)
        check.didRead(0.50)
        #expect(check.isRejected == true)
        check.finish()
        #expect(check.isRejected == true)
    }

    @Test func fastSpinSnapsBackToTheVolumeBeforeTheFirstWrite() -> Void {
        var check = VolumeWriteCheck()
        check.willWrite(0.51, current: 0.50)
        check.willWrite(0.52, current: 0.51)
        check.didRead(0.50)
        #expect(check.isRejected == true)
    }

    @Test func acceptedProbeClearsTheRejection() -> Void {
        var check = VolumeWriteCheck()
        check.willWrite(0.51, current: 0.50)
        check.didRead(0.50)
        check.finish()

        check.willWrite(0.51, current: 0.50)
        check.didRead(0.51)
        #expect(check.isRejected == true)
        check.finish()
        #expect(check.isRejected == false)
    }

    @Test func rejectedProbeKeepsTheRejection() -> Void {
        var check = VolumeWriteCheck()
        check.willWrite(0.51, current: 0.50)
        check.didRead(0.50)
        check.finish()

        check.willWrite(0.49, current: 0.50)
        check.didRead(0.50)
        check.finish()
        #expect(check.isRejected == true)
    }

    @Test func outsideChangeClearsTheRejection() -> Void {
        var check = VolumeWriteCheck()
        check.willWrite(0.51, current: 0.50)
        check.didRead(0.50)
        check.finish()

        check.didRead(0.50)
        #expect(check.isRejected == true)
        check.didRead(0.60)
        #expect(check.isRejected == false)
    }
}
