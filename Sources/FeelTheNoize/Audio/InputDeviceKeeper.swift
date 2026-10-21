import CoreAudio

/// Keeps one input device as the default input while it is connected (Docs/DESIGN.md §7.13).
///
/// Every change of the default input is reverted, whoever made it; the user moves the keep through the menu instead.
/// Listeners are registered only while a device is kept, so a keep that is off adds no work.
final class InputDeviceKeeper {
    private static let observedAddresses = [CoreAudioProperty.devicesAddress, CoreAudioProperty.defaultInputDeviceAddress]
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// Core Audio UID of the kept device; `nil` turns the keep off.
    var keptUID: String? {
        didSet {
            guard self.keptUID != oldValue else {
                return
            }
            if self.keptUID == nil {
                self.stop()
            }
            else {
                self.start()
                self.enforce()
            }
        }
    }

    private let coreAudio: any CoreAudioAccess
    private var listener: CoreAudioProperty.ListenerBlock?

    init(coreAudio: any CoreAudioAccess = CoreAudioHAL()) {
        self.coreAudio = coreAudio
    }

    private func start() -> Void {
        guard self.listener == nil else {
            return
        }
        let listener: CoreAudioProperty.ListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.enforce()
            }
        }
        self.listener = listener
        for address in Self.observedAddresses {
            let status = self.coreAudio.addListener(listener, for: address, on: Self.systemObject)
            if status != noErr {
                Log.audio.error("\(CoreAudioError(status: status, operation: "Observing the default input"), privacy: .public)")
            }
        }
        Log.audio.info("Keeping input device \(self.keptUID ?? "", privacy: .public)")
    }

    private func stop() -> Void {
        guard let listener = self.listener else {
            return
        }
        for address in Self.observedAddresses {
            self.coreAudio.removeListener(listener, for: address, on: Self.systemObject)
        }
        self.listener = nil
        Log.audio.info("Stopped keeping an input device")
    }

    private func enforce() -> Void {
        guard let keptUID = self.keptUID else {
            return
        }
        do {
            try self.switchBack(to: keptUID)
        }
        catch {
            Log.audio.error("\(error, privacy: .public)")
        }
    }

    /// A disconnected kept device is left alone: macOS picks another input, and the device list notification of the
    /// reconnect switches back.
    private func switchBack(to keptUID: String) throws -> Void {
        guard let keptID = try self.coreAudio.readDevice(uid: keptUID) else {
            return
        }
        let currentID = try self.coreAudio.readDefaultDevice(scope: kAudioDevicePropertyScopeInput)
        if currentID == keptID {
            return
        }
        try self.coreAudio.writeDefaultDevice(keptID, scope: kAudioDevicePropertyScopeInput)
        let replaced = currentID.flatMap { try? self.coreAudio.readString(kAudioObjectPropertyName, of: $0) } ?? "none"
        Log.audio.notice("Switched the input back to \(keptUID, privacy: .public) from \(replaced, privacy: .public)")
    }
}
