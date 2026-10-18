import AppKit

/// Symbol and text for a volume state, shared by the menu bar icon and the overlay (docs/DESIGN.md §5.2).
enum VolumePresentation {
    static func image(for state: AudioState?, accessibilityDescription: String) -> NSImage? {
        let image: NSImage?
        switch state {
            case .some(let state) where state.isMuted:
                image = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: accessibilityDescription)
            case .some(let state) where state.canSetVolume && state.volume <= 0:
                image = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: accessibilityDescription)
            case .some(let state) where state.canSetVolume:
                image = NSImage(
                    systemSymbolName: "speaker.wave.3.fill", variableValue: Double(state.volume),
                    accessibilityDescription: accessibilityDescription)
            default:
                // No output device, or one without software volume.
                image = NSImage(systemSymbolName: "speaker.fill", accessibilityDescription: accessibilityDescription)
        }
        image?.isTemplate = true
        return image
    }

    static func percent(_ volume: Float32) -> String {
        "\(Int((Double(volume) * 100).rounded())) %"
    }

    /// For example "Volume 42 %, muted".
    static func accessibilityDescription(for state: AudioState?) -> String {
        guard let state else { return "No output device" }
        guard state.canSetVolume else { return state.isMuted ? "Volume not adjustable, muted" : "Volume not adjustable" }
        return state.isMuted ? "Volume \(percent(state.volume)), muted" : "Volume \(percent(state.volume))"
    }
}
