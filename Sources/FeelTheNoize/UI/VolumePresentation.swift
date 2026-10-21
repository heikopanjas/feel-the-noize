import AppKit

/// Images and text for a volume state, shared by the menu bar icon and the overlay (Docs/DESIGN.md §5.2).
enum VolumePresentation {
    /// The knob for the menu bar and the overlay. A device without volume control plays at its fixed full level, so the
    /// knob shows full; without any output device it shows the minimum. The caller dims it where nothing can change.
    static func knobImage(for state: AudioState?, style: KnobIcon.Style, size: CGFloat, accessibilityDescription: String) -> NSImage {
        let level: Float32
        if let state {
            level = state.canSetVolume ? state.volume : 1
        }
        else {
            level = 0
        }
        return KnobIcon.image(
            style: style, level: level, isMuted: state?.isMuted ?? false, size: size, accessibilityDescription: accessibilityDescription)
    }

    static func percent(_ volume: Float32) -> String {
        "\(Int((Double(volume) * 100).rounded())) %"
    }

    /// For example "Volume 42 %, muted".
    static func accessibilityDescription(for state: AudioState?) -> String {
        guard let state else { return "No output device" }
        guard state.canSetVolume else { return state.isMuted ? "Volume not adjustable, muted" : "Volume not adjustable" }
        guard !state.isInUseElsewhere else { return "Volume in use by another device" }
        return state.isMuted ? "Volume \(percent(state.volume)), muted" : "Volume \(percent(state.volume))"
    }
}
