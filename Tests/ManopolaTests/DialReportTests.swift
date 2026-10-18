import Testing

@testable import Manopola

struct DialReportTests {
    // MARK: - Input Parsing

    @Test(
        "Parses input reports with and without the report ID byte",
        arguments: [
            ([0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3A], DialInputReport(isPressed: false, delta: 1)),
            ([0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3A], DialInputReport(isPressed: false, delta: 1))
        ] as [([UInt8], DialInputReport)])
    func bothBufferShapes(bytes: [UInt8], expected: DialInputReport) {
        #expect(DialReport.parseInput(reportID: 1, bytes: bytes) == expected)
    }

    @Test func clockwiseIsPositive() {
        let report = DialReport.parseInput(reportID: 1, bytes: [0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3A])
        #expect(report?.delta == 1)
    }

    @Test func counterClockwiseIsNegative() {
        let report = DialReport.parseInput(reportID: 1, bytes: [0x01, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x3A])
        #expect(report?.delta == -1)
    }

    @Test func fastTurnCarriesSeveralDetents() {
        let report = DialReport.parseInput(reportID: 1, bytes: [0x01, 0x00, 0xFD, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x3A])
        #expect(report?.delta == -3)
    }

    @Test func pressed() {
        let report = DialReport.parseInput(reportID: 1, bytes: [0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3A])
        #expect(report == DialInputReport(isPressed: true, delta: 0))
    }

    @Test func touchBitIsIgnored() {
        let report = DialReport.parseInput(reportID: 1, bytes: [0x01, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3A])
        #expect(report?.isPressed == false)
    }

    @Test(
        "Rejects a wrong report ID or length",
        arguments: [
            (2, [0x02, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3A]),
            (2, [0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3A]),
            (1, [0x01, 0x00, 0x01]),
            (1, []),
            (42, [0x2A, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        ] as [(UInt32, [UInt8])])
    func rejectsUnknownReports(reportID: UInt32, bytes: [UInt8]) {
        #expect(DialReport.parseInput(reportID: reportID, bytes: bytes) == nil)
    }

    // MARK: - Feature Report

    @Test func hapticConfigurationWithHapticsOn() {
        #expect(
            DialReport.hapticConfiguration(detentsPerRevolution: 36, hapticsEnabled: true) == [0x01, 0x24, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00])
    }

    @Test func hapticConfigurationWithHapticsOff() {
        #expect(
            DialReport.hapticConfiguration(detentsPerRevolution: 72, hapticsEnabled: false) == [0x01, 0x48, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00])
    }

    @Test func resolutionMultiplierIsLittleEndianAndClamped() {
        #expect(DialReport.hapticConfiguration(detentsPerRevolution: 3600, hapticsEnabled: true)[1 ... 2] == [0x10, 0x0E])
        #expect(DialReport.hapticConfiguration(detentsPerRevolution: 5000, hapticsEnabled: true)[1 ... 2] == [0x10, 0x0E])
    }

    // MARK: - Manual Triggers

    @Test func unmutePattern() {
        #expect(DialReport.manualTrigger(waveform: .click, repeatCount: 0, retriggerMilliseconds: 0) == [0x01, 0x00, 0x03, 0x00, 0x00])
    }

    @Test func mutePattern() {
        #expect(DialReport.manualTrigger(waveform: .click, repeatCount: 1, retriggerMilliseconds: 120) == [0x01, 0x01, 0x03, 0x78, 0x00])
    }

    @Test func endStopPattern() {
        #expect(DialReport.manualTrigger(waveform: .buzz, repeatCount: 0, retriggerMilliseconds: 0) == [0x01, 0x00, 0x04, 0x00, 0x00])
    }
}
