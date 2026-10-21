import Testing

@testable import FeelTheNoize

struct VolumePresentationTests {
    @Test(
        "Percent text rounds to whole percent",
        arguments: [(Float32(0), "0 %"), (0.42, "42 %"), (0.424, "42 %"), (0.425, "43 %"), (1, "100 %")] as [(Float32, String)])
    func percent(volume: Float32, expected: String) -> Void {
        #expect(VolumePresentation.percent(volume) == expected)
    }

    @Test(
        "Accessibility description per state",
        arguments: [
            (nil, "No output device"),
            (state(volume: 0.42), "Volume 42 %"),
            (state(volume: 0.42, isMuted: true), "Volume 42 %, muted"),
            (state(volume: 1, canSetVolume: false), "Volume not adjustable"),
            (state(volume: 1, isMuted: true, canSetVolume: false), "Volume not adjustable, muted"),
            (state(volume: 0.5, isInUseElsewhere: true), "Volume in use by another device")
        ] as [(AudioState?, String)])
    func accessibilityDescription(state: AudioState?, expected: String) -> Void {
        #expect(VolumePresentation.accessibilityDescription(for: state) == expected)
    }

    @Test("Knob image is a template of the requested size with the description", arguments: [nil, state(volume: 0.42)] as [AudioState?])
    func knobImage(state: AudioState?) -> Void {
        let image = VolumePresentation.knobImage(for: state, style: .arc, size: 18, accessibilityDescription: "test")
        #expect(image.isTemplate == true)
        #expect(image.accessibilityDescription == "test")
        #expect(image.size.width == 18)
    }

    private nonisolated static func state(
        volume: Float32, isMuted: Bool = false, canSetVolume: Bool = true, isInUseElsewhere: Bool = false
    ) -> AudioState {
        return AudioState(
            deviceID: 1, deviceUID: "fake", deviceName: "Fake Output", volume: volume, isMuted: isMuted, canSetVolume: canSetVolume,
            hasHardwareMute: true, isInUseElsewhere: isInUseElsewhere)
    }
}
