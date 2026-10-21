import CoreAudio
import Testing

@testable import FeelTheNoize

struct AudioDeviceListTests {
    private static func populated() -> FakeCoreAudio {
        let coreAudio = FakeCoreAudio()
        coreAudio.devices[1] = FakeCoreAudio.Device(
            uid: "speakers", name: "MacBook Pro Speakers", volume: 0.5, isMuted: nil, transportType: kAudioDeviceTransportTypeBuiltIn,
            outputDataSource: 0x6973_706B)
        coreAudio.devices[2] = FakeCoreAudio.Device(
            uid: "mic", name: "MacBook Pro Microphone", volume: nil, isMuted: nil, hasOutput: false, hasInput: true)
        coreAudio.devices[3] = FakeCoreAudio.Device(uid: "hidden", name: "Hidden", volume: 0.5, isMuted: false, isHidden: true)
        coreAudio.devices[4] = FakeCoreAudio.Device(
            uid: SoftwareVolume.aggregateUIDPrefix + "x", name: "Software Volume", volume: nil, isMuted: nil)
        coreAudio.devices[5] = FakeCoreAudio.Device(
            uid: "nostreams", name: "No Streams", volume: nil, isMuted: nil, hasOutput: false, hasInput: false)
        coreAudio.devices[6] = FakeCoreAudio.Device(
            uid: "airpods", name: "AirPods Max", volume: 0.7, isMuted: true, hasInput: true, transportType: kAudioDeviceTransportTypeBluetooth,
            modelUID: "201f 4c")
        coreAudio.defaultOutputID = 1
        coreAudio.defaultInputID = 2
        return coreAudio
    }

    @Test func listsVisibleDevicesWithStreamsAndTheDefaults() throws {
        let coreAudio = Self.populated()
        let list = AudioDeviceList(coreAudio: coreAudio)
        var changes = 0
        list.onChange = { changes += 1 }
        list.start()

        #expect(list.devices.map(\.uid) == ["speakers", "mic", "airpods"], "Hidden, private aggregate and streamless devices are left out")
        #expect(list.defaultOutputUID == "speakers")
        #expect(list.defaultInputUID == "mic")
        #expect(changes == 1)
        #expect(coreAudio.listenerCount == 3)

        let speakers = try #require(list.devices.first)
        #expect(speakers.transport == .builtIn)
        #expect(speakers.outputDataSource == 0x6973_706B)
        #expect(speakers.hasOutput == true)
        #expect(speakers.hasInput == false)
        #expect(speakers.canSetVolume == true)
        #expect(speakers.hasHardwareMute == false)
        #expect(speakers.modelUID == nil)

        let airPods = try #require(list.devices.last)
        #expect(airPods.transport == .bluetooth)
        #expect(airPods.modelUID == "201f 4c")
        #expect(airPods.hasInput == true)
        #expect(airPods.hasHardwareMute == true)

        let mic = list.devices[1]
        #expect(mic.canSetVolume == false, "Volume and mute describe the output, so an input-only device has neither")
        #expect(mic.outputDataSource == nil)
    }

    @Test func reloadsOnEveryObservedChangeAndStopsCleanly() {
        let coreAudio = Self.populated()
        let list = AudioDeviceList(coreAudio: coreAudio)
        var changes = 0
        list.onChange = { changes += 1 }
        list.start()

        coreAudio.devices[7] = FakeCoreAudio.Device(uid: "m2", name: "M2", volume: nil, isMuted: nil, hasInput: true)
        coreAudio.notify(kAudioHardwarePropertyDevices, on: FakeCoreAudio.systemObject)
        #expect(list.devices.map(\.uid) == ["speakers", "mic", "airpods", "m2"])
        #expect(changes == 2)

        coreAudio.defaultOutputID = 6
        coreAudio.notify(kAudioHardwarePropertyDefaultOutputDevice, on: FakeCoreAudio.systemObject)
        #expect(list.defaultOutputUID == "airpods")
        coreAudio.defaultInputID = 7
        coreAudio.notify(kAudioHardwarePropertyDefaultInputDevice, on: FakeCoreAudio.systemObject)
        #expect(list.defaultInputUID == "m2")
        #expect(changes == 4)

        list.stop()
        #expect(coreAudio.listenerCount == 0)
        coreAudio.notify(kAudioHardwarePropertyDevices, on: FakeCoreAudio.systemObject)
        #expect(changes == 4)
    }

    @Test func startTwiceRegistersOnce() {
        let coreAudio = Self.populated()
        let list = AudioDeviceList(coreAudio: coreAudio)
        list.start()
        list.start()
        #expect(coreAudio.listenerCount == 3)
    }
}
