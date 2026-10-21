import CoreAudio

/// Live list of the visible output and input devices and the current defaults (Docs/DESIGN.md §7.4, §7.11).
///
/// The Devices settings tab and the status menu each own one and observe only while they are visible, so it adds no work
/// while idle.
final class AudioDeviceList {
    private static let observedAddresses = [
        CoreAudioProperty.devicesAddress, CoreAudioProperty.defaultOutputDeviceAddress, CoreAudioProperty.defaultInputDeviceAddress
    ]
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private(set) var devices: [AudioDeviceInfo] = []
    private(set) var defaultOutputUID: String?
    private(set) var defaultInputUID: String?
    var onChange: (() -> Void)?

    private let coreAudio: any CoreAudioAccess
    private var listener: CoreAudioProperty.ListenerBlock?

    init(coreAudio: any CoreAudioAccess = CoreAudioHAL()) {
        self.coreAudio = coreAudio
    }

    func start() -> Void {
        guard self.listener == nil else {
            return
        }
        let listener: CoreAudioProperty.ListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
        self.listener = listener
        for address in Self.observedAddresses {
            let status = self.coreAudio.addListener(listener, for: address, on: Self.systemObject)
            if status != noErr {
                Log.audio.error("\(CoreAudioError(status: status, operation: "Observing the device list"), privacy: .public)")
            }
        }
        Log.audio.info("Observing the device list")
        self.reload()
    }

    func stop() -> Void {
        guard let listener = self.listener else {
            return
        }
        for address in Self.observedAddresses {
            self.coreAudio.removeListener(listener, for: address, on: Self.systemObject)
        }
        self.listener = nil
        Log.audio.info("Stopped observing the device list")
    }

    private func reload() -> Void {
        do {
            self.devices = try self.coreAudio.readDeviceIDs()
                .filter { self.coreAudio.isHidden($0) == false }
                .compactMap { self.describe($0) }
                // A private aggregate is visible to the process that made it; the software volume one is internal.
                .filter { $0.uid.hasPrefix(SoftwareVolume.aggregateUIDPrefix) == false }
        }
        catch {
            Log.audio.error("\(error, privacy: .public)")
            self.devices = []
        }
        self.defaultOutputUID = self.readDefaultUID(scope: kAudioDevicePropertyScopeOutput)
        self.defaultInputUID = self.readDefaultUID(scope: kAudioDevicePropertyScopeInput)
        self.onChange?()
    }

    private func readDefaultUID(scope: AudioObjectPropertyScope) -> String? {
        guard let deviceID = try? self.coreAudio.readDefaultDevice(scope: scope) else {
            return nil
        }
        return try? self.coreAudio.readString(kAudioDevicePropertyDeviceUID, of: deviceID)
    }

    /// Devices without streams and devices that vanish between listing and reading are skipped.
    private func describe(_ deviceID: AudioObjectID) -> AudioDeviceInfo? {
        guard let names = self.readNames(of: deviceID) else {
            return nil
        }
        let hasOutput = self.coreAudio.hasStreams(deviceID, scope: kAudioDevicePropertyScopeOutput)
        let hasInput = self.coreAudio.hasStreams(deviceID, scope: kAudioDevicePropertyScopeInput)
        if hasOutput == false {
            if hasInput == false {
                return nil
            }
        }
        var outputDataSource: UInt32?
        var canSetVolume = false
        var hasHardwareMute = false
        if hasOutput == true {
            outputDataSource = self.coreAudio.readOutputDataSource(of: deviceID)
            canSetVolume = self.coreAudio.isSettable(CoreAudioProperty.virtualMainVolumeAddress, of: deviceID)
            hasHardwareMute = self.coreAudio.isSettable(CoreAudioProperty.muteAddress, of: deviceID)
        }
        return AudioDeviceInfo(
            uid: names.uid, name: names.name,
            transport: AudioDeviceInfo.Transport(coreAudioTransportType: self.coreAudio.readTransportType(of: deviceID)),
            modelUID: try? self.coreAudio.readString(kAudioDevicePropertyModelUID, of: deviceID), outputDataSource: outputDataSource,
            hasOutput: hasOutput, hasInput: hasInput, canSetVolume: canSetVolume, hasHardwareMute: hasHardwareMute)
    }

    private func readNames(of deviceID: AudioObjectID) -> (uid: String, name: String)? {
        guard let uid = try? self.coreAudio.readString(kAudioDevicePropertyDeviceUID, of: deviceID) else {
            return nil
        }
        guard let name = try? self.coreAudio.readString(kAudioObjectPropertyName, of: deviceID) else {
            return nil
        }
        return (uid: uid, name: name)
    }
}
