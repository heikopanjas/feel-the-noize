import CoreAudio
import Testing

@testable import Manopola

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
            (kAudioDeviceTransportTypePCI, .other),
            (0, .other)
        ] as [(UInt32, AudioDeviceInfo.Transport)])
    func transport(coreAudio: UInt32, expected: AudioDeviceInfo.Transport) {
        #expect(AudioDeviceInfo.Transport(coreAudioTransportType: coreAudio) == expected)
    }

    @Test(
        "Controllable with volume or mute",
        arguments: [(true, true, true), (true, false, true), (false, true, true), (false, false, false)])
    func controllable(canSetVolume: Bool, hasHardwareMute: Bool, expected: Bool) {
        let device = AudioDeviceInfo(uid: "x", name: "X", transport: .usb, canSetVolume: canSetVolume, hasHardwareMute: hasHardwareMute)
        #expect(device.isControllable == expected)
    }
}
