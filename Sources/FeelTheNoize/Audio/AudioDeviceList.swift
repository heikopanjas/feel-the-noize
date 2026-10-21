import CoreAudio

/// Live list of the visible output and input devices and the current defaults (docs/DESIGN.md §7.4, §7.11).
///
/// The Devices settings tab and the status menu each own one and observe only while they are visible, so it adds no work
/// while idle.
final class AudioDeviceList {
    private static let observedAddresses = [
        CoreAudioProperty.devicesAddress, CoreAudioProperty.defaultOutputDeviceAddress, CoreAudioProperty.defaultInputDeviceAddress
    ]

    private(set) var devices: [AudioDeviceInfo] = []
    private(set) var defaultOutputUID: String?
    private(set) var defaultInputUID: String?
    var onChange: (() -> Void)?

    private var listener: CoreAudioProperty.ListenerBlock?

    func start() {
        guard listener == nil else { return }
        let listener: CoreAudioProperty.ListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
        self.listener = listener
        for var address in Self.observedAddresses {
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
            if status != noErr {
                Log.audio.error("\(CoreAudioError(status: status, operation: "Observing the device list"), privacy: .public)")
            }
        }
        Log.audio.info("Observing the device list")
        reload()
    }

    func stop() {
        guard let listener else { return }
        for var address in Self.observedAddresses {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        self.listener = nil
        Log.audio.info("Stopped observing the device list")
    }

    private func reload() {
        do {
            devices = try CoreAudioProperty.readDeviceIDs()
                .filter { !CoreAudioProperty.isHidden($0) }
                .compactMap(Self.describe)
                // A private aggregate is visible to the process that made it; the software volume one is internal.
                .filter { !$0.uid.hasPrefix(SoftwareVolume.aggregateUIDPrefix) }
        }
        catch {
            Log.audio.error("\(error, privacy: .public)")
            devices = []
        }
        defaultOutputUID = Self.readDefaultUID(scope: kAudioDevicePropertyScopeOutput)
        defaultInputUID = Self.readDefaultUID(scope: kAudioDevicePropertyScopeInput)
        onChange?()
    }

    private static func readDefaultUID(scope: AudioObjectPropertyScope) -> String? {
        guard let deviceID = try? CoreAudioProperty.readDefaultDevice(scope: scope) else { return nil }
        return try? CoreAudioProperty.readString(kAudioDevicePropertyDeviceUID, of: deviceID)
    }

    /// Devices without streams and devices that vanish between listing and reading are skipped.
    private static func describe(_ deviceID: AudioObjectID) -> AudioDeviceInfo? {
        let hasOutput = CoreAudioProperty.hasStreams(deviceID, scope: kAudioDevicePropertyScopeOutput)
        let hasInput = CoreAudioProperty.hasStreams(deviceID, scope: kAudioDevicePropertyScopeInput)
        guard hasOutput || hasInput,
            let uid = try? CoreAudioProperty.readString(kAudioDevicePropertyDeviceUID, of: deviceID),
            let name = try? CoreAudioProperty.readString(kAudioObjectPropertyName, of: deviceID)
        else { return nil }
        return AudioDeviceInfo(
            uid: uid, name: name, transport: .init(coreAudioTransportType: CoreAudioProperty.readTransportType(of: deviceID)),
            hasOutput: hasOutput, hasInput: hasInput,
            canSetVolume: hasOutput && CoreAudioProperty.isSettable(CoreAudioProperty.virtualMainVolumeAddress, of: deviceID),
            hasHardwareMute: hasOutput && CoreAudioProperty.isSettable(CoreAudioProperty.muteAddress, of: deviceID))
    }
}
