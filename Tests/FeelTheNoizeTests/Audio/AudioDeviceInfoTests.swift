import CoreAudio
import Testing

@testable import FeelTheNoize

struct AudioDeviceInfoTests {
    @Test(
        "Maps Core Audio transport types",
        arguments: [
            (kAudioDeviceTransportTypeBuiltIn, AudioDeviceInfo.Transport.builtIn),
            (kAudioDeviceTransportTypeBluetooth, .bluetooth),
            (kAudioDeviceTransportTypeBluetoothLE, .bluetooth),
            (kAudioDeviceTransportTypeUSB, .usb),
            (kAudioDeviceTransportTypeHDMI, .hdmi),
            (kAudioDeviceTransportTypeDisplayPort, .displayPort),
            (kAudioDeviceTransportTypeAirPlay, .airPlay),
            (kAudioDeviceTransportTypeThunderbolt, .thunderbolt),
            (kAudioDeviceTransportTypeVirtual, .virtual),
            (kAudioDeviceTransportTypeAggregate, .aggregate),
            (kAudioDeviceTransportTypeAutoAggregate, .aggregate),
            (kAudioDeviceTransportTypeContinuityCaptureWired, .other),
            (kAudioDeviceTransportTypePCI, .other),
            (0, .other)
        ] as [(UInt32, AudioDeviceInfo.Transport)])
    func transport(coreAudio: UInt32, expected: AudioDeviceInfo.Transport) {
        #expect(AudioDeviceInfo.Transport(coreAudioTransportType: coreAudio) == expected)
    }

    @Test(
        "Transport labels for the Devices tab",
        arguments: [
            (AudioDeviceInfo.Transport.builtIn, "Built-in"), (.bluetooth, "Bluetooth"), (.usb, "USB"), (.hdmi, "HDMI"),
            (.displayPort, "DisplayPort"), (.airPlay, "AirPlay"), (.thunderbolt, "Thunderbolt"), (.virtual, "Virtual"),
            (.aggregate, "Aggregate"), (.other, "Other")
        ] as [(AudioDeviceInfo.Transport, String)])
    func label(transport: AudioDeviceInfo.Transport, expected: String) {
        #expect(transport.label == expected)
    }
}
