import Testing

@testable import FeelTheNoize

struct KeepChoicesTests {
    private static let inputs = [input("m2", "M2"), input("airpods", "AirPods Max"), input("mic", "MacBook Pro Microphone")]

    @Test func connectedInputsSortedByName() {
        let choices = DeviceSettingsViewController.keepChoices(inputs: Self.inputs, keptUID: "m2", knownNames: [:])
        #expect(choices.map(\.title) == ["AirPods Max", "M2", "MacBook Pro Microphone"])
        #expect(choices.map(\.uid) == ["airpods", "m2", "mic"])
    }

    @Test func absentKeptDeviceIsListedAsNotConnected() {
        let choices = DeviceSettingsViewController.keepChoices(inputs: Self.inputs, keptUID: "motu", knownNames: ["motu": "MOTU M2"])
        #expect(choices.last?.uid == "motu")
        #expect(choices.last?.title == "MOTU M2 (not connected)")
    }

    @Test func absentKeptDeviceWithoutNameShowsItsUID() {
        let choices = DeviceSettingsViewController.keepChoices(inputs: [], keptUID: "motu", knownNames: [:])
        #expect(choices.map(\.title) == ["motu (not connected)"])
    }

    private static func input(_ uid: String, _ name: String) -> AudioDeviceInfo {
        AudioDeviceInfo(
            uid: uid, name: name, transport: .usb, modelUID: nil, outputDataSource: nil, hasOutput: false, hasInput: true,
            canSetVolume: false, hasHardwareMute: false)
    }
}
