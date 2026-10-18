import Foundation

/// Maps a software volume level (0…1, as shown to the user) to a linear amplitude factor (docs/DESIGN.md §7.9).
///
/// Loudness is perceived logarithmically, so the level is spread evenly in decibels over `range`; 0 is silence.
nonisolated enum SoftwareGain {
    static let range = 50.0

    static func amplitude(for level: Float) -> Float {
        guard level > 0 else { return 0 }
        guard level < 1 else { return 1 }
        let decibels = -range * (1 - Double(level))
        return Float(pow(10, decibels / 20))
    }
}
