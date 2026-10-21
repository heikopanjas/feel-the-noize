import CoreAudio
import Testing

@testable import FeelTheNoize

struct InputDeviceKeeperTests {
    private static func withInputs() -> FakeCoreAudio {
        let coreAudio = FakeCoreAudio()
        coreAudio.devices[1] = FakeCoreAudio.Device(uid: "m2", name: "M2", volume: nil, isMuted: nil, hasOutput: false, hasInput: true)
        coreAudio.devices[2] = FakeCoreAudio.Device(uid: "airpods", name: "AirPods", volume: 0.5, isMuted: false, hasInput: true)
        coreAudio.defaultInputID = 2
        return coreAudio
    }

    @Test func switchesTheInputBackWheneverItChanges() -> Void {
        let coreAudio = Self.withInputs()
        let keeper = InputDeviceKeeper(coreAudio: coreAudio)

        keeper.keptUID = "m2"
        #expect(coreAudio.defaultInputWrites == [1], "Turning the keep on switches right away")
        #expect(coreAudio.defaultInputID == 1)
        #expect(coreAudio.listenerCount == 2)

        coreAudio.notify(kAudioHardwarePropertyDefaultInputDevice, on: FakeCoreAudio.systemObject)
        #expect(coreAudio.defaultInputWrites == [1], "The echo of its own write changes nothing")

        coreAudio.defaultInputID = 2
        coreAudio.notify(kAudioHardwarePropertyDefaultInputDevice, on: FakeCoreAudio.systemObject)
        #expect(coreAudio.defaultInputWrites == [1, 1])
        #expect(coreAudio.defaultInputID == 1)
    }

    @Test func disconnectedKeptDeviceIsLeftAlone() -> Void {
        let coreAudio = Self.withInputs()
        let keeper = InputDeviceKeeper(coreAudio: coreAudio)

        keeper.keptUID = "motu"
        #expect(coreAudio.defaultInputWrites.isEmpty == true)
        #expect(coreAudio.defaultInputID == 2)

        // The device list notification of its reconnect switches back.
        coreAudio.devices[3] = FakeCoreAudio.Device(uid: "motu", name: "MOTU M2", volume: nil, isMuted: nil, hasOutput: false, hasInput: true)
        coreAudio.notify(kAudioHardwarePropertyDevices, on: FakeCoreAudio.systemObject)
        #expect(coreAudio.defaultInputWrites == [3])
    }

    @Test func turningTheKeepOffRemovesTheListeners() -> Void {
        let coreAudio = Self.withInputs()
        let keeper = InputDeviceKeeper(coreAudio: coreAudio)
        keeper.keptUID = "m2"
        #expect(coreAudio.listenerCount == 2)

        keeper.keptUID = "m2"
        #expect(coreAudio.listenerCount == 2, "Setting the same device again registers nothing")

        keeper.keptUID = nil
        #expect(coreAudio.listenerCount == 0)
        coreAudio.defaultInputID = 2
        coreAudio.notify(kAudioHardwarePropertyDefaultInputDevice, on: FakeCoreAudio.systemObject)
        #expect(coreAudio.defaultInputWrites == [1], "Nothing is enforced while the keep is off")
    }

    @Test func movingTheKeepSwitchesToTheNewDevice() -> Void {
        let coreAudio = Self.withInputs()
        let keeper = InputDeviceKeeper(coreAudio: coreAudio)
        keeper.keptUID = "m2"
        keeper.keptUID = "airpods"
        #expect(coreAudio.defaultInputWrites == [1, 2])
        #expect(coreAudio.listenerCount == 2)
    }
}
