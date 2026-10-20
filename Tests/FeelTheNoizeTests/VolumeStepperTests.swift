import Testing

@testable import FeelTheNoize

struct VolumeStepperTests {
    private static let tolerance: Float32 = 0.000_01

    @Test(
        "Snaps to the step grid in the direction of travel",
        arguments: [
            (Float32(0.37), 1, Float32(0.38)),
            (0.37, -1, 0.36),
            (0.40, 1, 0.42),
            (0.40, -1, 0.38),
            (0.99, 1, 1.00),
            (0.01, -3, 0.00),
            (1.00, 1, 1.00),
            (0.00, -1, 0.00),
            (0.50, 3, 0.56),
            (0.50, -25, 0.00)
        ] as [(Float32, Int, Float32)])
    func defaultStep(volume: Float32, detents: Int, expected: Float32) {
        let result = VolumeStepper.volume(from: volume, detents: detents, step: 0.02)
        #expect(abs(result - expected) < Self.tolerance)
    }

    @Test func fineStep() {
        let result = VolumeStepper.volume(from: 0.37, detents: 1, step: 0.005)
        #expect(abs(result - 0.375) < Self.tolerance)
    }

    @Test("Float noise near a grid line neither skips nor repeats a step", arguments: [Float32(0.379_999_97), 0.380_000_03])
    func floatNoise(volume: Float32) {
        #expect(abs(VolumeStepper.volume(from: volume, detents: 1, step: 0.02) - 0.40) < Self.tolerance)
        #expect(abs(VolumeStepper.volume(from: volume, detents: -1, step: 0.02) - 0.36) < Self.tolerance)
    }

    @Test func zeroDetentsLeavesVolumeUnchanged() {
        #expect(VolumeStepper.volume(from: 0.37, detents: 0, step: 0.02) == 0.37)
    }

    @Test func stepThatDoesNotDivideOneStillReachesFull() {
        #expect(VolumeStepper.volume(from: 0.99, detents: 1, step: 0.03) == 1)
    }
}
