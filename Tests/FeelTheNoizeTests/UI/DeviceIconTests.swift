import AppKit
import Testing

@testable import FeelTheNoize

struct DeviceIconTests {
    @Test(
        "Symbol per device and direction",
        arguments: [
            (device("MacBook Pro Speakers", .builtIn, source: 0x6973_706B), DeviceIcon.Direction.output, "macbook"),
            (device("MacBook Pro Microphone", .builtIn), .input, "macbook"),
            (device("External Headphones", .builtIn, source: 0x6864_706E), .output, "headphones"),
            (device("iMac Speakers", .builtIn), .output, "desktopcomputer"),
            (device("Mac mini Speakers", .builtIn), .output, "speaker.wave.2.fill"),
            (device("AirPods Max", .bluetooth, model: "201f 4c"), .output, "airpods.max"),
            (device("Living Room", .bluetooth, model: "2024 4c"), .input, "airpods.pro"),
            (device("Some Apple Device", .bluetooth, model: "2fff 4c"), .output, "headphones"),
            (device("Headset", .bluetooth, model: "201f 5d"), .output, "headphones"),
            (device("M2", .usb, model: "M2:07FD:000B"), .output, "speaker.wave.2.fill"),
            (device("M2", .usb, model: "M2:07FD:000B"), .input, "mic.fill"),
            (device("LG", .hdmi), .output, "display"),
            (device("Studio", .displayPort), .output, "display"),
            (device("HomePod", .airPlay), .output, "airplayaudio"),
            (device("iPhone 18 Pro Microphone", .other), .input, "mic.fill"),
            (device("Loopback", .virtual), .output, "speaker.wave.2.fill"),
            (device("Loopback", .virtual), .input, "mic.fill")
        ] as [(AudioDeviceInfo, DeviceIcon.Direction, String)])
    func symbol(device: AudioDeviceInfo, direction: DeviceIcon.Direction, expected: String) -> Void {
        #expect(DeviceIcon.symbolName(for: device, direction: direction) == expected)
    }

    @Test(
        "Slider shows headphones for headphones, a speaker otherwise",
        arguments: [
            (Optional(device("AirPods Max", .bluetooth, model: "201f 4c")), "airpods.max"),
            (device("Headset", .bluetooth), "headphones"),
            (device("External Headphones", .builtIn, source: 0x6864_706E), "headphones"),
            (device("MacBook Pro Speakers", .builtIn), "speaker.wave.2.fill"),
            (device("M2", .usb), "speaker.wave.2.fill"),
            (nil, "speaker.wave.2.fill")
        ] as [(AudioDeviceInfo?, String)])
    func sliderSymbol(output: AudioDeviceInfo?, expected: String) -> Void {
        #expect(DeviceIcon.sliderSymbolName(for: output) == expected)
    }

    @Test(
        "Apple product ID from the Bluetooth model UID",
        arguments: [("201f 4c", Int?.some(0x201F)), ("201F 004C", 0x201F), ("201f 5d", nil), ("M2:07FD:000B", nil), ("", nil)]
            as [(String, Int?)])
    func productID(modelUID: String, expected: Int?) -> Void {
        #expect(DeviceIcon.appleProductID(fromModelUID: modelUID) == expected)
    }

    @Test("Every symbol exists")
    func symbolsExist() -> Void {
        let names = Set(Self.symbolArguments.map { DeviceIcon.symbolName(for: $0.0, direction: $0.1) })
        for name in names {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
        }
    }

    @Test("Draws a circle of the menu size", arguments: [true, false])
    func image(isDefault: Bool) throws -> Void {
        let image = DeviceIcon.image(symbolName: "airpods.max", isDefault: isDefault, accessibilityDescription: "current output")
        #expect(image.isTemplate == false)
        #expect(image.size == NSSize(width: DeviceIcon.diameter, height: DeviceIcon.diameter))
        #expect(image.accessibilityDescription == "current output")
        let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let center = try #require(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2))
        let corner = try #require(rep.colorAt(x: 0, y: 0))
        #expect(center.alphaComponent > 0)
        #expect(corner.alphaComponent < 0.1)
    }

    /// Every transport with and without a model and data source, in both directions. The type name rather than `Self`:
    /// a static stored property initializer cannot refer to `Self`.
    private nonisolated static let symbolArguments: [(AudioDeviceInfo, DeviceIcon.Direction)] = [
        AudioDeviceInfo.Transport.builtIn, .bluetooth, .usb, .hdmi, .displayPort, .airPlay, .thunderbolt, .virtual, .aggregate, .other
    ]
    .flatMap { transport in
        let devices = [
            DeviceIconTests.device("MacBook Pro Speakers", transport, model: "201f 4c", source: 0x6864_706E),
            DeviceIconTests.device("Other", transport)
        ]
        return devices.flatMap { [($0, DeviceIcon.Direction.output), ($0, DeviceIcon.Direction.input)] }
    }

    private nonisolated static func device(
        _ name: String, _ transport: AudioDeviceInfo.Transport, model: String? = nil, source: UInt32? = nil
    ) -> AudioDeviceInfo {
        return AudioDeviceInfo(
            uid: name, name: name, transport: transport, modelUID: model, outputDataSource: source, hasOutput: true, hasInput: true,
            canSetVolume: true, hasHardwareMute: false)
    }
}
