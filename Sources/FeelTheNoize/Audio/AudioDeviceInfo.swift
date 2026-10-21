import CoreAudio

/// An audio device as listed in the Devices settings tab and the status menu (Docs/DESIGN.md §7.6, §7.11).
struct AudioDeviceInfo: Equatable {
    enum Transport: Equatable {
        case builtIn
        case bluetooth
        case usb
        case hdmi
        case displayPort
        case airPlay
        case thunderbolt
        case virtual
        case aggregate
        case other

        init(coreAudioTransportType: UInt32) {
            switch coreAudioTransportType {
                case kAudioDeviceTransportTypeBuiltIn:
                    self = .builtIn
                case kAudioDeviceTransportTypeBluetooth:
                    self = .bluetooth
                case kAudioDeviceTransportTypeBluetoothLE:
                    self = .bluetooth
                case kAudioDeviceTransportTypeUSB:
                    self = .usb
                case kAudioDeviceTransportTypeHDMI:
                    self = .hdmi
                case kAudioDeviceTransportTypeDisplayPort:
                    self = .displayPort
                case kAudioDeviceTransportTypeAirPlay:
                    self = .airPlay
                case kAudioDeviceTransportTypeThunderbolt:
                    self = .thunderbolt
                case kAudioDeviceTransportTypeVirtual:
                    self = .virtual
                case kAudioDeviceTransportTypeAggregate:
                    self = .aggregate
                case kAudioDeviceTransportTypeAutoAggregate:
                    self = .aggregate
                default:
                    self = .other
            }
        }

        var label: String {
            switch self {
                case .builtIn:
                    return "Built-in"
                case .bluetooth:
                    return "Bluetooth"
                case .usb:
                    return "USB"
                case .hdmi:
                    return "HDMI"
                case .displayPort:
                    return "DisplayPort"
                case .airPlay:
                    return "AirPlay"
                case .thunderbolt:
                    return "Thunderbolt"
                case .virtual:
                    return "Virtual"
                case .aggregate:
                    return "Aggregate"
                case .other:
                    return "Other"
            }
        }
    }

    let uid: String
    let name: String
    let transport: Transport
    /// Bluetooth devices report product and vendor ID in hex, for example `201f 4c` for AirPods Max; `nil` if unreadable.
    let modelUID: String?
    /// `hdpn` marks the built-in headphone jack; `nil` without a data source.
    let outputDataSource: UInt32?
    let hasOutput: Bool
    let hasInput: Bool
    /// Volume and mute describe the output; they are false for an input-only device.
    let canSetVolume: Bool
    let hasHardwareMute: Bool
}
