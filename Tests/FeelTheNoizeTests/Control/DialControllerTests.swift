import Testing

@testable import FeelTheNoize

struct DialControllerTests {
    // MARK: - Fakes

    /// Behaves like AudioOutput: writes update the state immediately, emulated mute restores the remembered volume.
    private final class FakeAudio: AudioControlling {
        var state: AudioState?
        private(set) var volumeWrites: [Float32] = []
        private(set) var muteWrites: [Bool] = []
        private var emulatedMuteVolume: Float32?

        init(volume: Float32 = 0.40, isMuted: Bool = false, canSetVolume: Bool = true, hasHardwareMute: Bool = true) {
            self.state = AudioState(
                deviceID: 1, deviceUID: "fake", deviceName: "Fake Output", volume: volume, isMuted: isMuted,
                canSetVolume: canSetVolume, hasHardwareMute: hasHardwareMute)
        }

        func setVolume(_ volume: Float32) -> Void {
            self.volumeWrites.append(volume)
            // Like AudioOutput, a probe on an output owned by another device does not change the state.
            if self.state?.isInUseElsewhere == true {
                return
            }
            self.state?.volume = volume
        }

        func setMuted(_ muted: Bool) -> Void {
            self.muteWrites.append(muted)
            guard var state = self.state else {
                return
            }
            guard state.isMuted != muted else {
                return
            }
            if state.hasHardwareMute == true {
                state.isMuted = muted
            }
            else if state.canSetVolume == true {
                if muted == true {
                    self.emulatedMuteVolume = state.volume
                    state.volume = 0
                }
                else {
                    state.volume = self.emulatedMuteVolume ?? state.volume
                }
                state.isMuted = muted
            }
            self.state = state
        }
    }

    private final class FakeHaptics: HapticFeedback {
        private(set) var endStops = 0
        private(set) var muteToggles: [Bool] = []

        func endStop() -> Void {
            self.endStops += 1
        }

        func muteToggled(isMuted: Bool) -> Void {
            self.muteToggles.append(isMuted)
        }
    }

    private final class AdjustmentRecorder {
        var states: [AudioState] = []
    }

    private struct Fixture {
        let audio: FakeAudio
        let haptics = FakeHaptics()
        let clock = TestClock()
        let controller: DialController
        private let recorder = AdjustmentRecorder()

        var adjustments: [AudioState] {
            return self.recorder.states
        }

        init(audio: FakeAudio = FakeAudio(), settings: ControlSettings = ControlSettings(stepPercent: 2, reverseDirection: false)) {
            self.init(audio: audio, settingsProvider: { settings })
        }

        init(audio: FakeAudio = FakeAudio(), settingsProvider: @escaping () -> ControlSettings) {
            self.audio = audio
            let clock = self.clock
            self.controller = DialController(audio: audio, haptics: self.haptics, settings: settingsProvider, now: { clock.now })
            let recorder = self.recorder
            self.controller.onAdjusted = { recorder.states.append($0) }
        }

        func volume() -> Float32 {
            return self.audio.state?.volume ?? -1
        }
    }

    private static let tolerance: Float32 = 0.000_01
    private static let excludingFake = ControlSettings(stepPercent: 2, reverseDirection: false, excludedDeviceUIDs: ["fake"])

    // MARK: - Rotation

    @Test func clockwiseStepsUp() -> Void {
        let fixture = Fixture()
        fixture.controller.handle(.rotated(detents: 1))
        expectClose(fixture.volume(), 0.42, tolerance: Self.tolerance)
        #expect(fixture.adjustments.count == 1)
    }

    @Test func counterClockwiseStepsDown() -> Void {
        let fixture = Fixture()
        fixture.controller.handle(.rotated(detents: -1))
        expectClose(fixture.volume(), 0.38, tolerance: Self.tolerance)
    }

    @Test func fastTurnStepsSeveralDetents() -> Void {
        let fixture = Fixture()
        fixture.controller.handle(.rotated(detents: 3))
        expectClose(fixture.volume(), 0.46, tolerance: Self.tolerance)
    }

    @Test func stepPercentFromSettingsIsUsed() -> Void {
        let fixture = Fixture(settings: ControlSettings(stepPercent: 5, reverseDirection: false))
        fixture.controller.handle(.rotated(detents: 1))
        expectClose(fixture.volume(), 0.45, tolerance: Self.tolerance)
    }

    @Test func reverseDirectionSwapsMeaning() -> Void {
        let fixture = Fixture(settings: ControlSettings(stepPercent: 2, reverseDirection: true))
        fixture.controller.handle(.rotated(detents: 1))
        expectClose(fixture.volume(), 0.38, tolerance: Self.tolerance)
    }

    @Test func turnWhileMutedUnmutesFirst() -> Void {
        let fixture = Fixture(audio: FakeAudio(isMuted: true))
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.audio.muteWrites == [false])
        #expect(fixture.audio.state?.isMuted == false)
        expectClose(fixture.volume(), 0.42, tolerance: Self.tolerance)
    }

    @Test func turnWhileEmulatedMutedStepsFromRestoredVolume() -> Void {
        let audio = FakeAudio(hasHardwareMute: false)
        audio.setMuted(true)
        let fixture = Fixture(audio: audio)
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.audio.state?.isMuted == false)
        expectClose(fixture.volume(), 0.42, tolerance: Self.tolerance)
    }

    @Test func rotationWithoutVolumeControlBuzzesInsteadOfWriting() -> Void {
        let fixture = Fixture(audio: FakeAudio(canSetVolume: false))
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.audio.volumeWrites.isEmpty == true)
        #expect(fixture.adjustments.isEmpty == true)
        #expect(fixture.haptics.endStops == 1)
    }

    @Test func turningOnADeviceWithoutVolumeControlBuzzesOncePerGesture() -> Void {
        let fixture = Fixture(audio: FakeAudio(canSetVolume: false))
        for _ in 0 ..< 10 {
            fixture.controller.handle(.rotated(detents: 1))
            fixture.clock.advance(by: .milliseconds(100))
        }
        #expect(fixture.haptics.endStops == 1)
        fixture.clock.advance(by: .milliseconds(300))
        fixture.controller.handle(.rotated(detents: -1))
        #expect(fixture.haptics.endStops == 2)
    }

    @Test func turningAnOutputOwnedElsewhereProbesAndBuzzesOncePerGesture() -> Void {
        let audio = FakeAudio(volume: 0.50)
        audio.state?.isInUseElsewhere = true
        let fixture = Fixture(audio: audio)
        for _ in 0 ..< 5 {
            fixture.controller.handle(.rotated(detents: 1))
            fixture.clock.advance(by: .milliseconds(100))
        }
        #expect(fixture.audio.volumeWrites.count == 5)
        expectClose(fixture.volume(), 0.50, tolerance: Self.tolerance)
        #expect(fixture.haptics.endStops == 1)
    }

    @Test func pressStillTogglesHardwareMuteWithoutVolumeControl() -> Void {
        let fixture = Fixture(audio: FakeAudio(canSetVolume: false, hasHardwareMute: true))
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.released)
        #expect(fixture.audio.state?.isMuted == true)
        #expect(fixture.haptics.muteToggles == [true])
    }

    @Test func rotationAndPressAreIgnoredWithoutOutputDevice() -> Void {
        let audio = FakeAudio()
        audio.state = nil
        let fixture = Fixture(audio: audio)
        fixture.controller.handle(.rotated(detents: 1))
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.released)
        #expect(fixture.audio.volumeWrites.isEmpty == true)
        #expect(fixture.audio.muteWrites.isEmpty == true)
        #expect(fixture.haptics.muteToggles.isEmpty == true)
        #expect(fixture.haptics.endStops == 0)
        #expect(fixture.adjustments.isEmpty == true)
    }

    // MARK: - Press

    @Test func shortPressTogglesMute() -> Void {
        let fixture = Fixture()
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.released)
        #expect(fixture.audio.state?.isMuted == true)
        #expect(fixture.haptics.muteToggles == [true])

        fixture.controller.handle(.pressed)
        fixture.controller.handle(.released)
        #expect(fixture.audio.state?.isMuted == false)
        #expect(fixture.haptics.muteToggles == [true, false])
        #expect(fixture.adjustments.count == 2)
    }

    @Test func pressAndTurnStepsByQuarterAndDoesNotToggleMute() -> Void {
        let fixture = Fixture()
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.rotated(detents: 1))
        fixture.controller.handle(.rotated(detents: 1))
        fixture.controller.handle(.released)
        expectClose(fixture.volume(), 0.41, tolerance: Self.tolerance)
        #expect(fixture.audio.muteWrites.isEmpty == true)
        #expect(fixture.haptics.muteToggles.isEmpty == true)
    }

    @Test func pressAndTurnWithoutSoftwareVolumeStillSuppressesMuteToggle() -> Void {
        let fixture = Fixture(audio: FakeAudio(canSetVolume: false))
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.rotated(detents: 1))
        fixture.controller.handle(.released)
        #expect(fixture.audio.muteWrites.isEmpty == true)
    }

    @Test func releaseWithoutPressDoesNothing() -> Void {
        let fixture = Fixture()
        fixture.controller.handle(.released)
        #expect(fixture.audio.muteWrites.isEmpty == true)
    }

    @Test func resetMidPressPreventsMuteToggle() -> Void {
        let fixture = Fixture()
        fixture.controller.handle(.pressed)
        fixture.controller.reset()
        fixture.controller.handle(.released)
        #expect(fixture.audio.muteWrites.isEmpty == true)
        #expect(fixture.haptics.muteToggles.isEmpty == true)
    }

    @Test func noHapticConfirmationWhenTheDeviceCannotMute() -> Void {
        let fixture = Fixture(audio: FakeAudio(canSetVolume: false, hasHardwareMute: false))
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.released)
        #expect(fixture.haptics.muteToggles.isEmpty == true)
        #expect(fixture.adjustments.isEmpty == true)
    }

    @Test func emulatedMuteTogglesThroughVolume() -> Void {
        let fixture = Fixture(audio: FakeAudio(hasHardwareMute: false))
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.released)
        #expect(fixture.audio.state?.isMuted == true)
        #expect(fixture.volume() == 0)

        fixture.controller.handle(.pressed)
        fixture.controller.handle(.released)
        #expect(fixture.audio.state?.isMuted == false)
        expectClose(fixture.volume(), 0.40, tolerance: Self.tolerance)
    }

    // MARK: - Excluded Devices

    @Test func excludedDeviceIgnoresRotation() -> Void {
        let fixture = Fixture(settings: Self.excludingFake)
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.audio.volumeWrites.isEmpty == true)
        #expect(fixture.adjustments.isEmpty == true)
    }

    @Test func excludedDeviceIgnoresPress() -> Void {
        let fixture = Fixture(settings: Self.excludingFake)
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.released)
        #expect(fixture.audio.muteWrites.isEmpty == true)
        #expect(fixture.haptics.muteToggles.isEmpty == true)
        #expect(fixture.adjustments.isEmpty == true)
    }

    @Test func excludedDeviceWithoutVolumeControlDoesNotBuzz() -> Void {
        let fixture = Fixture(audio: FakeAudio(canSetVolume: false), settings: Self.excludingFake)
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.haptics.endStops == 0)
    }

    @Test func excludedDeviceAtTheEndDoesNotBuzz() -> Void {
        let fixture = Fixture(audio: FakeAudio(volume: 1), settings: Self.excludingFake)
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.haptics.endStops == 0)
    }

    @Test func pressAndTurnOnExcludedDeviceStillSuppressesMuteToggle() -> Void {
        let audio = FakeAudio()
        var excluded = true
        let fixture = Fixture(
            audio: audio,
            settingsProvider: {
                return ControlSettings(stepPercent: 2, reverseDirection: false, excludedDeviceUIDs: excluded == true ? ["fake"] : [])
            })
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.rotated(detents: 1))
        // Re-included before the release: the turn still counts, so the release must not mute.
        excluded = false
        fixture.controller.handle(.released)
        #expect(fixture.audio.muteWrites.isEmpty == true)
    }

    @Test func otherDevicesAreUnaffectedByExclusions() -> Void {
        let fixture = Fixture(settings: ControlSettings(stepPercent: 2, reverseDirection: false, excludedDeviceUIDs: ["speakers"]))
        fixture.controller.handle(.rotated(detents: 1))
        expectClose(fixture.volume(), 0.42, tolerance: Self.tolerance)
    }

    // MARK: - End Stop

    @Test("Turning past an end buzzes without writing", arguments: [(Float32(1), 1), (0, -1)])
    func endStop(volume: Float32, detents: Int) -> Void {
        let fixture = Fixture(audio: FakeAudio(volume: volume))
        fixture.controller.handle(.rotated(detents: detents))
        #expect(fixture.haptics.endStops == 1)
        #expect(fixture.audio.volumeWrites.isEmpty == true)
        #expect(fixture.adjustments.count == 1)
    }

    @Test func stepReachingTheEndIsNotAnEndStop() -> Void {
        let fixture = Fixture(audio: FakeAudio(volume: 0.99))
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.volume() == 1)
        #expect(fixture.haptics.endStops == 0)
    }

    @Test func continuousSpinPastTheEndBuzzesOnce() -> Void {
        let fixture = Fixture(audio: FakeAudio(volume: 1))
        for _ in 0 ..< 10 {
            fixture.controller.handle(.rotated(detents: 1))
            fixture.clock.advance(by: .milliseconds(100))
        }
        #expect(fixture.haptics.endStops == 1)
    }

    @Test func endStopBuzzesAgainAfterAPause() -> Void {
        let fixture = Fixture(audio: FakeAudio(volume: 1))
        fixture.controller.handle(.rotated(detents: 1))
        fixture.clock.advance(by: .milliseconds(299))
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.haptics.endStops == 1)
        fixture.clock.advance(by: .milliseconds(300))
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.haptics.endStops == 2)
    }

    @Test func turningAwayFromTheEndWorksImmediately() -> Void {
        let fixture = Fixture(audio: FakeAudio(volume: 1))
        fixture.controller.handle(.rotated(detents: 1))
        fixture.controller.handle(.rotated(detents: -1))
        expectClose(fixture.volume(), 0.98, tolerance: Self.tolerance)
    }
}
