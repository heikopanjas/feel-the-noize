import Testing

@testable import FeelTheNoize

struct StatusItemTitleTests {
    @Test(
        "Dial status line",
        arguments: [
            (DialConnection.connected, Int?.some(85), "Surface Dial: Connected, battery 85 %"),
            (.connected, nil, "Surface Dial: Connected"),
            (.notConnected, 85, "Surface Dial: Not Connected"),
            (.inUseElsewhere, 85, "Surface Dial: In Use by Another App")
        ] as [(DialConnection, Int?, String)])
    func dialTitle(connection: DialConnection, battery: Int?, expected: String) {
        #expect(StatusItemController.title(for: connection, batteryLevel: battery) == expected)
    }

    @Test("Input line", arguments: [(String?.some("MOTU M2"), "Input: MOTU M2"), (nil, "Input: None")] as [(String?, String)])
    func inputTitle(name: String?, expected: String) {
        #expect(StatusItemController.inputTitle(name) == expected)
    }

    @Test("Device sections split by direction and sort by name")
    func deviceSections() {
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

    private static func device(_ name: String, output: Bool, input: Bool) -> AudioDeviceInfo {
        AudioDeviceInfo(
            uid: name, name: name, transport: .usb, modelUID: nil, outputDataSource: nil, hasOutput: output, hasInput: input, canSetVolume: output,
            hasHardwareMute: false)
    }
}
