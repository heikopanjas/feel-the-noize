import Foundation
import Testing

@testable import FeelTheNoize

struct SoftwareGainTests {
    @Test func zeroIsSilent() {
        #expect(SoftwareGain.amplitude(for: 0) == 0)
        #expect(SoftwareGain.amplitude(for: -0.5) == 0)
    }

    @Test func fullIsUnity() {
        #expect(SoftwareGain.amplitude(for: 1) == 1)
        #expect(SoftwareGain.amplitude(for: 1.5) == 1)
    }

    @Test("Spreads the level evenly in decibels", arguments: [(Float(0.5), -25.0), (0.8, -10.0), (0.02, -49.0)])
    func decibels(level: Float, expected: Double) {
        let decibels = 20 * log10(Double(SoftwareGain.amplitude(for: level)))
        expectClose(decibels, expected, tolerance: 0.01)
    }

    @Test func isMonotonic() {
        let amplitudes = stride(from: Float(0), through: 1, by: 0.01).map(SoftwareGain.amplitude(for:))
        #expect(zip(amplitudes, amplitudes.dropFirst()).allSatisfy { $0 < $1 })
    }
}
