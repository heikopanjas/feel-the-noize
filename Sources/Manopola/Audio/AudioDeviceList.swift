import CoreAudio

/// Live list of the visible output devices and the current default output (docs/DESIGN.md §7.4).
///
/// Only the Devices settings tab uses it, and only while the tab is visible, so it adds no work while idle.
final class AudioDeviceList {
    private static let observedAddresses = [CoreAudioProperty.devicesAddress, CoreAudioProperty.defaultOutputDeviceAddress]

    private(set) var devices: [AudioDeviceInfo] = []
    private(set) var defaultDeviceUID: String?
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
        Log.audio.info("Observing the output device list")
        reload()
    }

    func stop() {
        guard let listener else { return }
        for var address in Self.observedAddresses {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        self.listener = nil
        Log.audio.info("Stopped observing the output device list")
    }

    private func reload() {
        do {
            devices = try CoreAudioProperty.readDeviceIDs()
                .filter { CoreAudioProperty.hasOutputStreams($0) && !CoreAudioProperty.isHidden($0) }
                .compactMap(Self.describe)
        }
        catch {
            Log.audio.error("\(error, privacy: .public)")
            devices = []
        }
        let defaultID = try? CoreAudioProperty.readDefaultOutputDevice()
        defaultDeviceUID = defaultID.flatMap { $0 }.flatMap { try? CoreAudioProperty.readString(kAudioDevicePropertyDeviceUID, of: $0) }
        onChange?()
    }

    /// Devices that vanish between listing and reading are skipped.
    private static func describe(_ deviceID: AudioObjectID) -> AudioDeviceInfo? {
        guard let uid = try? CoreAudioProperty.readString(kAudioDevicePropertyDeviceUID, of: deviceID),
            let name = try? CoreAudioProperty.readString(kAudioObjectPropertyName, of: deviceID)
        else { return nil }
        return AudioDeviceInfo(
            uid: uid, name: name, transport: .init(coreAudioTransportType: CoreAudioProperty.readTransportType(of: deviceID)),
            canSetVolume: CoreAudioProperty.isSettable(CoreAudioProperty.virtualMainVolumeAddress, of: deviceID),
            hasHardwareMute: CoreAudioProperty.isSettable(CoreAudioProperty.muteAddress, of: deviceID))
    }
}
