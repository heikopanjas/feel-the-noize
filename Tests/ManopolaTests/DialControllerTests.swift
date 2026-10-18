import Testing

@testable import Manopola

struct DialControllerTests {
    // MARK: - Fakes

    /// Behaves like AudioOutput: writes update the state immediately, emulated mute restores the remembered volume.
    private final class FakeAudio: AudioControlling {
        var state: AudioState?
        private(set) var volumeWrites: [Float32] = []
        private(set) var muteWrites: [Bool] = []
        private var emulatedMuteVolume: Float32?

        init(volume: Float32 = 0.40, isMuted: Bool = false, canSetVolume: Bool = true, hasHardwareMute: Bool = true) {
            state = AudioState(
                deviceID: 1, deviceUID: "fake", deviceName: "Fake Output", volume: volume, isMuted: isMuted,
                canSetVolume: canSetVolume, hasHardwareMute: hasHardwareMute)
        }

        func setVolume(_ volume: Float32) {
            volumeWrites.append(volume)
            state?.volume = volume
        }

        func setMuted(_ muted: Bool) {
            muteWrites.append(muted)
            guard var state, state.isMuted != muted else { return }
            if state.hasHardwareMute {
                state.isMuted = muted
            }
            else if state.canSetVolume {
                if muted {
                    emulatedMuteVolume = state.volume
                    state.volume = 0
                }
                else {
                    state.volume = emulatedMuteVolume ?? state.volume
                }
                state.isMuted = muted
            }
            self.state = state
        }
    }

    private final class FakeHaptics: HapticFeedback {
        private(set) var endStops = 0
        private(set) var muteToggles: [Bool] = []

        func endStop() {
            endStops += 1
        }

        func muteToggled(isMuted: Bool) {
            muteToggles.append(isMuted)
        }
    }

    private final class TestClock {
        var now = ContinuousClock.now

        func advance(by duration: Duration) {
            now += duration
        }
    }

    private struct Fixture {
        let audio: FakeAudio
        let haptics = FakeHaptics()
        let clock = TestClock()
        let controller: DialController
        var adjustments: [AudioState] { recorder.states }
        private let recorder = AdjustmentRecorder()

        init(audio: FakeAudio = FakeAudio(), settings: ControlSettings = ControlSettings(stepPercent: 2, reverseDirection: false)) {
            self.init(audio: audio, settingsProvider: { settings })
        }

        init(audio: FakeAudio = FakeAudio(), settingsProvider: @escaping () -> ControlSettings) {
            self.audio = audio
            let clock = clock
            controller = DialController(audio: audio, haptics: haptics, settings: settingsProvider, now: { clock.now })
            let recorder = recorder
            controller.onAdjusted = { recorder.states.append($0) }
        }

        func volume() -> Float32 {
            audio.state?.volume ?? -1
        }
    }

    private final class AdjustmentRecorder {
        var states: [AudioState] = []
    }

    private static let tolerance: Float32 = 0.000_01

    // MARK: - Rotation

    @Test func clockwiseStepsUp() {
        let fixture = Fixture()
        fixture.controller.handle(.rotated(detents: 1))
        #expect(abs(fixture.volume() - 0.42) < Self.tolerance)
        #expect(fixture.adjustments.count == 1)
    }

    @Test func counterClockwiseStepsDown() {
        let fixture = Fixture()
        fixture.controller.handle(.rotated(detents: -1))
        #expect(abs(fixture.volume() - 0.38) < Self.tolerance)
    }

    @Test func fastTurnStepsSeveralDetents() {
        let fixture = Fixture()
        fixture.controller.handle(.rotated(detents: 3))
        #expect(abs(fixture.volume() - 0.46) < Self.tolerance)
    }

    @Test func stepPercentFromSettingsIsUsed() {
        let fixture = Fixture(settings: ControlSettings(stepPercent: 5, reverseDirection: false))
        fixture.controller.handle(.rotated(detents: 1))
        #expect(abs(fixture.volume() - 0.45) < Self.tolerance)
    }

    @Test func reverseDirectionSwapsMeaning() {
        let fixture = Fixture(settings: ControlSettings(stepPercent: 2, reverseDirection: true))
        fixture.controller.handle(.rotated(detents: 1))
        #expect(abs(fixture.volume() - 0.38) < Self.tolerance)
    }

    @Test func turnWhileMutedUnmutesFirst() {
        let fixture = Fixture(audio: FakeAudio(isMuted: true))
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.audio.muteWrites == [false])
        #expect(fixture.audio.state?.isMuted == false)
        #expect(abs(fixture.volume() - 0.42) < Self.tolerance)
    }

    @Test func turnWhileEmulatedMutedStepsFromRestoredVolume() {
        let audio = FakeAudio(hasHardwareMute: false)
        audio.setMuted(true)
        let fixture = Fixture(audio: audio)
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.audio.state?.isMuted == false)
        #expect(abs(fixture.volume() - 0.42) < Self.tolerance)
    }

    @Test func rotationIsIgnoredWithoutSoftwareVolume() {
        let fixture = Fixture(audio: FakeAudio(canSetVolume: false))
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.audio.volumeWrites.isEmpty)
        #expect(fixture.adjustments.isEmpty)
    }

    @Test func rotationAndPressAreIgnoredWithoutOutputDevice() {
        let audio = FakeAudio()
        audio.state = nil
        let fixture = Fixture(audio: audio)
        fixture.controller.handle(.rotated(detents: 1))
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.released)
        #expect(fixture.audio.volumeWrites.isEmpty)
        #expect(fixture.audio.muteWrites.isEmpty)
        #expect(fixture.haptics.muteToggles.isEmpty)
        #expect(fixture.adjustments.isEmpty)
    }

    // MARK: - Press

    @Test func shortPressTogglesMute() {
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

    @Test func pressAndTurnStepsByQuarterAndDoesNotToggleMute() {
        let fixture = Fixture()
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.rotated(detents: 1))
        fixture.controller.handle(.rotated(detents: 1))
        fixture.controller.handle(.released)
        #expect(abs(fixture.volume() - 0.41) < Self.tolerance)
        #expect(fixture.audio.muteWrites.isEmpty)
        #expect(fixture.haptics.muteToggles.isEmpty)
    }

    @Test func pressAndTurnWithoutSoftwareVolumeStillSuppressesMuteToggle() {
        let fixture = Fixture(audio: FakeAudio(canSetVolume: false))
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.rotated(detents: 1))
        fixture.controller.handle(.released)
        #expect(fixture.audio.muteWrites.isEmpty)
    }

    @Test func releaseWithoutPressDoesNothing() {
        let fixture = Fixture()
        fixture.controller.handle(.released)
        #expect(fixture.audio.muteWrites.isEmpty)
    }

    @Test func resetMidPressPreventsMuteToggle() {
        let fixture = Fixture()
        fixture.controller.handle(.pressed)
        fixture.controller.reset()
        fixture.controller.handle(.released)
        #expect(fixture.audio.muteWrites.isEmpty)
        #expect(fixture.haptics.muteToggles.isEmpty)
    }

    @Test func noHapticConfirmationWhenTheDeviceCannotMute() {
        let fixture = Fixture(audio: FakeAudio(canSetVolume: false, hasHardwareMute: false))
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.released)
        #expect(fixture.haptics.muteToggles.isEmpty)
        #expect(fixture.adjustments.isEmpty)
    }

    @Test func emulatedMuteTogglesThroughVolume() {
        let fixture = Fixture(audio: FakeAudio(hasHardwareMute: false))
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.released)
        #expect(fixture.audio.state?.isMuted == true)
        #expect(fixture.volume() == 0)

        fixture.controller.handle(.pressed)
        fixture.controller.handle(.released)
        #expect(fixture.audio.state?.isMuted == false)
        #expect(abs(fixture.volume() - 0.40) < Self.tolerance)
    }

    // MARK: - Excluded Devices

    private static let excludingFake = ControlSettings(stepPercent: 2, reverseDirection: false, excludedDeviceUIDs: ["fake"])

    @Test func excludedDeviceIgnoresRotation() {
        let fixture = Fixture(settings: Self.excludingFake)
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.audio.volumeWrites.isEmpty)
        #expect(fixture.adjustments.isEmpty)
    }

    @Test func excludedDeviceIgnoresPress() {
        let fixture = Fixture(settings: Self.excludingFake)
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.released)
        #expect(fixture.audio.muteWrites.isEmpty)
        #expect(fixture.haptics.muteToggles.isEmpty)
        #expect(fixture.adjustments.isEmpty)
    }

    @Test func excludedDeviceAtTheEndDoesNotBuzz() {
        let fixture = Fixture(audio: FakeAudio(volume: 1), settings: Self.excludingFake)
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.haptics.endStops == 0)
    }

    @Test func pressAndTurnOnExcludedDeviceStillSuppressesMuteToggle() {
        let audio = FakeAudio()
        var excluded = true
        let fixture = Fixture(
            audio: audio,
            settingsProvider: {
                ControlSettings(stepPercent: 2, reverseDirection: false, excludedDeviceUIDs: excluded ? ["fake"] : [])
            })
        fixture.controller.handle(.pressed)
        fixture.controller.handle(.rotated(detents: 1))
        // Re-included before the release: the turn still counts, so the release must not mute.
        excluded = false
        fixture.controller.handle(.released)
        #expect(fixture.audio.muteWrites.isEmpty)
    }

    @Test func otherDevicesAreUnaffectedByExclusions() {
        let fixture = Fixture(settings: ControlSettings(stepPercent: 2, reverseDirection: false, excludedDeviceUIDs: ["speakers"]))
        fixture.controller.handle(.rotated(detents: 1))
        #expect(abs(fixture.volume() - 0.42) < Self.tolerance)
    }

    // MARK: - End Stop

    @Test("Turning past an end buzzes without writing", arguments: [(Float32(1), 1), (0, -1)])
    func endStop(volume: Float32, detents: Int) {
        let fixture = Fixture(audio: FakeAudio(volume: volume))
        fixture.controller.handle(.rotated(detents: detents))
        #expect(fixture.haptics.endStops == 1)
        #expect(fixture.audio.volumeWrites.isEmpty)
        #expect(fixture.adjustments.count == 1)
    }

    @Test func stepReachingTheEndIsNotAnEndStop() {
        let fixture = Fixture(audio: FakeAudio(volume: 0.99))
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.volume() == 1)
        #expect(fixture.haptics.endStops == 0)
    }

    @Test func continuousSpinPastTheEndBuzzesOnce() {
        let fixture = Fixture(audio: FakeAudio(volume: 1))
        for _ in 0 ..< 10 {
            fixture.controller.handle(.rotated(detents: 1))
            fixture.clock.advance(by: .milliseconds(100))
        }
        #expect(fixture.haptics.endStops == 1)
    }

    @Test func endStopBuzzesAgainAfterAPause() {
        let fixture = Fixture(audio: FakeAudio(volume: 1))
        fixture.controller.handle(.rotated(detents: 1))
        fixture.clock.advance(by: .milliseconds(299))
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.haptics.endStops == 1)
        fixture.clock.advance(by: .milliseconds(300))
        fixture.controller.handle(.rotated(detents: 1))
        #expect(fixture.haptics.endStops == 2)
    }

    @Test func turningAwayFromTheEndWorksImmediately() {
        let fixture = Fixture(audio: FakeAudio(volume: 1))
        fixture.controller.handle(.rotated(detents: 1))
        fixture.controller.handle(.rotated(detents: -1))
        #expect(abs(fixture.volume() - 0.98) < Self.tolerance)
    }
}
