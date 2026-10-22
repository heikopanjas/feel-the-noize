import Testing

@testable import FeelTheNoize

struct StatusItemTitleTests {
    @Test(
        "Dial status line",
        arguments: [
            (DialConnection.connected, "Surface Dial: Connected"),
            (.notConnected, "Surface Dial: Not Connected"),
            (.inUseElsewhere, "Surface Dial: In Use by Another App")
        ] as [(DialConnection, String)])
    func dialTitle(connection: DialConnection, expected: String) -> Void {
        #expect(StatusItemController.title(for: connection) == expected)
    }

    @Test(
        "Input line",
        arguments: [
            (String?.some("MOTU M2"), false, "Input: MOTU M2"), ("MOTU M2", true, "Input: MOTU M2 (kept)"), (nil, false, "Input: None")
        ] as [(String?, Bool, String)])
    func inputTitle(name: String?, isKept: Bool, expected: String) -> Void {
        #expect(StatusItemController.inputTitle(name, isKept: isKept) == expected)
    }

    @Test("Device sections split by direction and sort by name")
    func deviceSections() -> Void {
        let devices = [
            Self.device("MOTU M2", output: true, input: true),
            Self.device("MacBook Pro Speakers", output: true, input: false),
            Self.device("AirPods Pro", output: true, input: true),
            Self.device("MacBook Pro Microphone", output: false, input: true),
            Self.device("Device 10", output: true, input: false),
            Self.device("Device 9", output: true, input: false)
        ]
        let sections = StatusItemController.deviceSections(devices)
        #expect(sections.outputs.map(\.name) == ["AirPods Pro", "Device 9", "Device 10", "MacBook Pro Speakers", "MOTU M2"])
        #expect(sections.inputs.map(\.name) == ["AirPods Pro", "MacBook Pro Microphone", "MOTU M2"])
    }

    @Test("Input rows leave out the batteries of devices that are outputs as well")
    func batteryAddressesOfOutputs() -> Void {
        let outputs = [
            Self.device("AirPods Pro", uid: "70-F9-4A-A8-CE-BF:output", output: true, input: false),
            Self.device("MOTU M2", uid: "AppleUSBAudioEngine:MOTU:M2:M2MA1307XA:1,2", output: true, input: true)
        ]
        let hidden = StatusItemController.batteryAddresses(of: outputs)
        #expect(hidden == ["70F94AA8CEBF"])
        #expect(hidden.contains(AccessoryBattery.address(in: "70-F9-4A-A8-CE-BF:input") ?? "") == true)
        #expect(hidden.contains(AccessoryBattery.address(in: "11-22-33-44-55-66:input") ?? "") == false)
    }

    @Test func muteTitleFollowsTheState() -> Void {
        #expect(MenuMuteRow.title(isMuted: false) == "Mute")
        #expect(MenuMuteRow.title(isMuted: true) == "Unmute")
    }

    /// `uid` defaults to the name, which carries no Bluetooth address.
    private static func device(_ name: String, uid: String? = nil, output: Bool, input: Bool) -> AudioDeviceInfo {
        return AudioDeviceInfo(
            uid: uid ?? name, name: name, transport: .usb, modelUID: nil, outputDataSource: nil, hasOutput: output, hasInput: input,
            canSetVolume: output, hasHardwareMute: false)
    }
}
