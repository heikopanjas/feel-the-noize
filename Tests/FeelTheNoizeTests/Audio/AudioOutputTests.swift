import AudioToolbox
import CoreAudio
import Testing

@testable import FeelTheNoize

struct AudioOutputTests {
    private static let speakersID: AudioObjectID = 10
    private static let airPodsID: AudioObjectID = 20
    private static let tolerance: Float32 = 0.000_01

    // MARK: - Fakes

    private final class FakePreferences: SoftwareVolumePreferences {
        var wanted: Set<String> = []
        var levels: [String: Float] = [:]

        func wantsSoftwareVolume(_ uid: String) -> Bool {
            return self.wanted.contains(uid)
        }

        func softwareVolumeLevel(_ uid: String) -> Float {
            return self.levels[uid] ?? 1
        }

        func setSoftwareVolumeLevel(_ uid: String, _ level: Float) -> Void {
            self.levels[uid] = level
        }
    }

    private final class ChangeRecorder {
        var states: [AudioState?] = []
    }

    /// An `AudioOutput` over the fakes, started with `device` as the default output (object ID `speakersID`).
    private struct Fixture {
        let coreAudio = FakeCoreAudio()
        let softwareVolume = FakeSoftwareVolume()
        let preferences = FakePreferences()
        let sleeper = ManualSleeper()
        let clock = TestClock()
        let audio: AudioOutput
        private let recorder = ChangeRecorder()

        var changes: [AudioState?] {
            return self.recorder.states
        }

        init(
            device: FakeCoreAudio.Device, isDefault: Bool = true, softwareVolumeLevel: Float? = nil,
            softwareVolumeStartError: (any Error)? = nil
        ) {
            self.coreAudio.devices[AudioOutputTests.speakersID] = device
            if isDefault == true {
                self.coreAudio.defaultOutputID = AudioOutputTests.speakersID
            }
            if let softwareVolumeLevel = softwareVolumeLevel {
                self.preferences.wanted = [device.uid]
                self.preferences.levels[device.uid] = softwareVolumeLevel
            }
            self.softwareVolume.startError = softwareVolumeStartError
            let clock = self.clock
            let sleeper = self.sleeper
            self.audio = AudioOutput(
                coreAudio: self.coreAudio, softwareVolume: self.softwareVolume, now: { clock.now },
                sleep: { duration in await sleeper.sleep(for: duration) })
            self.audio.preferences = self.preferences
            let recorder = self.recorder
            self.audio.onChange = { recorder.states.append($0) }
            self.audio.start()
        }

        func notifyVolume() -> Void {
            self.coreAudio.notify(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, on: AudioOutputTests.speakersID)
        }

        func notifyDefaultOutput() -> Void {
            self.coreAudio.notify(kAudioHardwarePropertyDefaultOutputDevice, on: FakeCoreAudio.systemObject)
        }

        /// Lets the rejected-write window end: waits until its timer sleeps, if it has not started yet, then releases
        /// it and returns once `finish()` and the refresh have run.
        func finishWriteWindow() async -> Void {
            if self.sleeper.isAsleep == false {
                await self.sleeper.waitUntilAsleep(count: self.sleeper.sleepCount + 1)
            }
            await self.sleeper.releaseAndWait()
        }
    }

    private static func speakers(volume: Float32 = 0.5, isMuted: Bool? = false) -> FakeCoreAudio.Device {
        return FakeCoreAudio.Device(uid: "speakers", name: "Speakers", volume: volume, isMuted: isMuted)
    }

    private static let hdmi = FakeCoreAudio.Device(uid: "hdmi", name: "LG", volume: nil, isMuted: nil)
    private static let tapError = CoreAudioError(status: kAudioHardwareIllegalOperationError, operation: "Creating the process tap")

    // MARK: - Default Output

    @Test func startPublishesTheDefaultOutput() throws -> Void {
        let fixture = Fixture(device: Self.speakers())
        let state = try #require(fixture.audio.state)
        #expect(state.deviceUID == "speakers")
        #expect(state.deviceName == "Speakers")
        #expect(state.volume == 0.5)
        #expect(state.isMuted == false)
        #expect(state.canSetVolume == true)
        #expect(state.hasHardwareMute == true)
        #expect(state.isSoftwareVolume == false)
        #expect(fixture.changes.count == 1)
        #expect(fixture.coreAudio.listenerCount == 4, "One listener on the system object and three on the device")
    }

    @Test func noDefaultOutputPublishesNil() -> Void {
        let fixture = Fixture(device: Self.speakers(), isDefault: false)
        #expect(fixture.audio.state == nil)
        #expect(fixture.changes.count == 0, "The initial nil equals the cached nil and is not news")
    }

    @Test func switchingTheDefaultOutputMovesTheListeners() throws -> Void {
        let fixture = Fixture(device: Self.speakers())
        fixture.coreAudio.devices[Self.airPodsID] = FakeCoreAudio.Device(uid: "airpods", name: "AirPods", volume: 0.3, isMuted: false)
        fixture.coreAudio.defaultOutputID = Self.airPodsID
        fixture.notifyDefaultOutput()
        let state = try #require(fixture.audio.state)
        #expect(state.deviceUID == "airpods")
        #expect(state.volume == 0.3)
        #expect(fixture.coreAudio.listenerCount == 4)
        fixture.audio.stop()
        #expect(fixture.coreAudio.listenerCount == 0)
    }

    // MARK: - External Changes

    @Test func externalChangeIsPublished() -> Void {
        let fixture = Fixture(device: Self.speakers())
        fixture.coreAudio.devices[Self.speakersID]?.volume = 0.7
        fixture.notifyVolume()
        #expect(fixture.audio.state?.volume == 0.7)
        #expect(fixture.changes.count == 2)
    }

    @Test func floatNoiseIsNotPublished() -> Void {
        let fixture = Fixture(device: Self.speakers(volume: 0.58))
        fixture.coreAudio.devices[Self.speakersID]?.volume = 0.580_000_04
        fixture.notifyVolume()
        #expect(fixture.audio.state?.volume == 0.58)
        #expect(fixture.changes.count == 1)
    }

    // MARK: - Writes

    @Test func setVolumeClampsWritesAndPublishesOptimistically() -> Void {
        let fixture = Fixture(device: Self.speakers())
        fixture.audio.setVolume(1.5)
        #expect(fixture.coreAudio.volumeWrites == [1])
        #expect(fixture.audio.state?.volume == 1)
        #expect(fixture.changes.count == 2)
    }

    @Test func hardwareMuteIsWrittenAndPublished() -> Void {
        let fixture = Fixture(device: Self.speakers())
        fixture.audio.setMuted(true)
        #expect(fixture.coreAudio.muteWrites == [true])
        #expect(fixture.audio.state?.isMuted == true)
        fixture.audio.setMuted(true)
        #expect(fixture.coreAudio.muteWrites == [true], "Muting a muted device writes nothing")
    }

    // MARK: - Emulated Mute

    @Test func emulatedMuteRemembersAndRestoresTheVolume() -> Void {
        let fixture = Fixture(device: Self.speakers(volume: 0.4, isMuted: nil))
        #expect(fixture.audio.state?.hasHardwareMute == false)

        fixture.audio.setMuted(true)
        #expect(fixture.coreAudio.volumeWrites == [0])
        #expect(fixture.audio.state?.isMuted == true)
        #expect(fixture.audio.state?.volume == 0)

        fixture.notifyVolume()
        #expect(fixture.audio.state?.isMuted == true, "The listener echo of the zero keeps the device muted")

        fixture.audio.setMuted(false)
        #expect(fixture.coreAudio.volumeWrites == [0, 0.4])
        #expect(fixture.audio.state?.isMuted == false)
        expectClose(fixture.audio.state?.volume ?? -1, 0.4, tolerance: Self.tolerance)
    }

    @Test func volumeSetElsewhereClearsTheEmulatedMute() -> Void {
        let fixture = Fixture(device: Self.speakers(volume: 0.4, isMuted: nil))
        fixture.audio.setMuted(true)
        fixture.coreAudio.devices[Self.speakersID]?.volume = 0.6
        fixture.notifyVolume()
        #expect(fixture.audio.state?.isMuted == false)
        expectClose(fixture.audio.state?.volume ?? -1, 0.6, tolerance: Self.tolerance)
    }

    @Test func turningUpWhileEmulatedMutedUnmutes() -> Void {
        let fixture = Fixture(device: Self.speakers(volume: 0.4, isMuted: nil))
        fixture.audio.setMuted(true)
        fixture.audio.setVolume(0.42)
        #expect(fixture.audio.state?.isMuted == false)
        expectClose(fixture.audio.state?.volume ?? -1, 0.42, tolerance: Self.tolerance)
    }

    @Test func deviceWithoutMuteOrVolumeRefusesMute() throws -> Void {
        let fixture = Fixture(device: Self.hdmi)
        let state = try #require(fixture.audio.state)
        #expect(state.canSetVolume == false)
        #expect(state.volume == 1, "A fixed level shows as full")
        fixture.audio.setMuted(true)
        fixture.audio.setVolume(0.5)
        #expect(fixture.audio.state?.isMuted == false)
        #expect(fixture.coreAudio.muteWrites.isEmpty == true)
        #expect(fixture.coreAudio.volumeWrites.isEmpty == true)
    }

    // MARK: - Software Volume

    @Test func softwareVolumeStartsForAnOptedInDeviceWithoutVolumeControl() throws -> Void {
        let fixture = Fixture(device: Self.hdmi, softwareVolumeLevel: 0.7)
        #expect(fixture.softwareVolume.deviceUID == "hdmi")
        #expect(fixture.softwareVolume.level == 0.7)
        let state = try #require(fixture.audio.state)
        #expect(state.isSoftwareVolume == true)
        #expect(state.canSetVolume == true)
        #expect(state.volume == 0.7)

        fixture.audio.setVolume(0.3)
        #expect(fixture.softwareVolume.level == 0.3)
        #expect(fixture.preferences.levels["hdmi"] == 0.3)
        #expect(fixture.coreAudio.volumeWrites.isEmpty == true, "Software volume never reaches the device")
        #expect(fixture.audio.state?.volume == 0.3)
    }

    @Test func softwareVolumeMutesThroughTheLevel() -> Void {
        let fixture = Fixture(device: Self.hdmi, softwareVolumeLevel: 0.7)
        fixture.audio.setMuted(true)
        #expect(fixture.softwareVolume.level == 0)
        #expect(fixture.audio.state?.isMuted == true)
        fixture.audio.setMuted(false)
        #expect(fixture.softwareVolume.level == 0.7)
        #expect(fixture.audio.state?.isMuted == false)
    }

    @Test func failedSoftwareVolumeIsRetriedOnlyAfterASettingsChange() -> Void {
        let fixture = Fixture(device: Self.hdmi, softwareVolumeLevel: 0.7, softwareVolumeStartError: Self.tapError)
        #expect(fixture.softwareVolume.startCount == 1)
        #expect(fixture.audio.state?.canSetVolume == false)
        #expect(fixture.audio.softwareVolumeError != nil)

        fixture.notifyDefaultOutput()
        #expect(fixture.softwareVolume.startCount == 1, "A refresh does not retry the failed device")

        fixture.audio.refreshSoftwareVolume()
        #expect(fixture.softwareVolume.startCount == 2)

        fixture.softwareVolume.startError = nil
        fixture.audio.refreshSoftwareVolume()
        #expect(fixture.softwareVolume.startCount == 3)
        #expect(fixture.audio.state?.canSetVolume == true)
        #expect(fixture.audio.softwareVolumeError == nil)
    }

    @Test func softwareVolumeStopsWhenTheDeviceGetsNativeVolume() -> Void {
        let fixture = Fixture(device: Self.hdmi, softwareVolumeLevel: 0.7)
        fixture.coreAudio.devices[Self.speakersID]?.volume = 0.5
        fixture.notifyDefaultOutput()
        #expect(fixture.softwareVolume.deviceUID == nil)
        #expect(fixture.softwareVolume.stopCount == 1)
        #expect(fixture.audio.state?.isSoftwareVolume == false)
        #expect(fixture.audio.state?.volume == 0.5)
    }

    // MARK: - Rejected Writes

    @Test func rejectedWritesAreDetectedAndThenProbedOncePerSecond() async -> Void {
        let fixture = Fixture(device: Self.speakers())
        fixture.coreAudio.rejectsVolumeWrites = true

        fixture.audio.setVolume(0.52)
        #expect(fixture.coreAudio.volumeWrites == [0.52])
        expectClose(fixture.audio.state?.volume ?? -1, 0.52, tolerance: Self.tolerance)

        // The device snaps back to the old volume.
        fixture.notifyVolume()
        #expect(fixture.audio.state?.isInUseElsewhere == true)
        #expect(fixture.audio.state?.volume == 0.5)
        await fixture.finishWriteWindow()
        #expect(fixture.audio.state?.isInUseElsewhere == true, "A snap-back inside the window keeps the rejection")

        fixture.audio.setVolume(0.54)
        #expect(fixture.coreAudio.volumeWrites.count == 2, "The first write while rejected is a probe")
        #expect(fixture.audio.state?.volume == 0.5, "A probe is not published")
        fixture.audio.setVolume(0.56)
        #expect(fixture.coreAudio.volumeWrites.count == 2, "No second probe within a second")

        fixture.clock.advance(by: .seconds(1))
        fixture.audio.setVolume(0.56)
        #expect(fixture.coreAudio.volumeWrites.count == 3)
    }

    @Test func anAcceptedProbeClearsTheRejection() async -> Void {
        let fixture = Fixture(device: Self.speakers())
        fixture.coreAudio.rejectsVolumeWrites = true
        fixture.audio.setVolume(0.52)
        fixture.notifyVolume()
        await fixture.finishWriteWindow()
        #expect(fixture.audio.state?.isInUseElsewhere == true)

        fixture.coreAudio.rejectsVolumeWrites = false
        fixture.audio.setVolume(0.54)
        fixture.notifyVolume()
        await fixture.finishWriteWindow()
        #expect(fixture.audio.state?.isInUseElsewhere == false)
        expectClose(fixture.audio.state?.volume ?? -1, 0.54, tolerance: Self.tolerance)
    }

    @Test func switchingTheOutputResetsTheRejection() -> Void {
        let fixture = Fixture(device: Self.speakers())
        fixture.coreAudio.rejectsVolumeWrites = true
        fixture.audio.setVolume(0.52)
        fixture.notifyVolume()
        #expect(fixture.audio.state?.isInUseElsewhere == true)

        fixture.coreAudio.devices[Self.airPodsID] = FakeCoreAudio.Device(uid: "airpods", name: "AirPods", volume: 0.3, isMuted: false)
        fixture.coreAudio.defaultOutputID = Self.airPodsID
        fixture.notifyDefaultOutput()
        #expect(fixture.audio.state?.deviceUID == "airpods")
        #expect(fixture.audio.state?.isInUseElsewhere == false)
    }

    // MARK: - Stop

    @Test func stopDetachesEverything() -> Void {
        let fixture = Fixture(device: Self.hdmi, softwareVolumeLevel: 0.7)
        fixture.audio.stop()
        #expect(fixture.coreAudio.listenerCount == 0)
        #expect(fixture.softwareVolume.deviceUID == nil)
        fixture.notifyDefaultOutput()
        #expect(fixture.changes.count == 1, "No listener fires after stop")
    }
}
