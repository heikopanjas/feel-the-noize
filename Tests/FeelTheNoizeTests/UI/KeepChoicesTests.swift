import Testing

@testable import FeelTheNoize

struct KeepChoicesTests {
    // The type name rather than `Self`: a static stored property initializer cannot refer to `Self`.
    private static let inputs = [
        KeepChoicesTests.input("m2", "M2"), KeepChoicesTests.input("airpods", "AirPods Max"),
        KeepChoicesTests.input("mic", "MacBook Pro Microphone")
    ]

    @Test func connectedInputsSortedByName() -> Void {
        let choices = DeviceSettingsViewController.keepChoices(inputs: Self.inputs, keptUID: "m2", knownNames: [:])
        #expect(choices.map(\.title) == ["AirPods Max", "M2", "MacBook Pro Microphone"])
        #expect(choices.map(\.uid) == ["airpods", "m2", "mic"])
    }

    @Test func absentKeptDeviceIsListedAsNotConnected() -> Void {
        let choices = DeviceSettingsViewController.keepChoices(inputs: Self.inputs, keptUID: "motu", knownNames: ["motu": "MOTU M2"])
        #expect(choices.last?.uid == "motu")
        #expect(choices.last?.title == "MOTU M2 (not connected)")
    }

    @Test func absentKeptDeviceWithoutNameShowsItsUID() -> Void {
        let choices = DeviceSettingsViewController.keepChoices(inputs: [], keptUID: "motu", knownNames: [:])
        #expect(choices.map(\.title) == ["motu (not connected)"])
    }

    @Test func noKeptDeviceListsOnlyTheConnectedInputs() -> Void {
        let choices = DeviceSettingsViewController.keepChoices(inputs: Self.inputs, keptUID: nil, knownNames: ["motu": "MOTU M2"])
        #expect(choices.map(\.uid) == ["airpods", "m2", "mic"])
    }

    private static func input(_ uid: String, _ name: String) -> AudioDeviceInfo {
        return AudioDeviceInfo(
            uid: uid, name: name, transport: .usb, modelUID: nil, outputDataSource: nil, hasOutput: false, hasInput: true,
            canSetVolume: false, hasHardwareMute: false)
    }
}
