import CoreAudio

/// Keeps one input device as the default input while it is connected (docs/DESIGN.md §7.13).
///
/// Every change of the default input is reverted, whoever made it; the user moves the keep through the menu instead.
/// Listeners are registered only while a device is kept, so a keep that is off adds no work.
final class InputDeviceKeeper {
    private static let observedAddresses = [CoreAudioProperty.devicesAddress, CoreAudioProperty.defaultInputDeviceAddress]

    /// Core Audio UID of the kept device; `nil` turns the keep off.
    var keptUID: String? {
        didSet {
            guard keptUID != oldValue else { return }
            if keptUID == nil {
                stop()
            }
            else {
                start()
                enforce()
            }
        }
    }

    private var listener: CoreAudioProperty.ListenerBlock?

    private func start() {
        guard listener == nil else { return }
        let listener: CoreAudioProperty.ListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.enforce()
            }
        }
        self.listener = listener
        for var address in Self.observedAddresses {
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
            if status != noErr {
                Log.audio.error("\(CoreAudioError(status: status, operation: "Observing the default input"), privacy: .public)")
            }
        }
        Log.audio.info("Keeping input device \(self.keptUID ?? "", privacy: .public)")
    }

    private func stop() {
        guard let listener else { return }
        for var address in Self.observedAddresses {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        self.listener = nil
        Log.audio.info("Stopped keeping an input device")
    }

    /// A disconnected kept device is left alone: macOS picks another input, and the device list notification of the
    /// reconnect switches back.
    private func enforce() {
        guard let keptUID else { return }
        do {
            guard let keptID = try CoreAudioProperty.readDevice(uid: keptUID) else { return }
            let currentID = try CoreAudioProperty.readDefaultDevice(scope: kAudioDevicePropertyScopeInput)
            guard currentID != keptID else { return }
            try CoreAudioProperty.writeDefaultDevice(keptID, scope: kAudioDevicePropertyScopeInput)
            let replaced = currentID.flatMap { try? CoreAudioProperty.readString(kAudioObjectPropertyName, of: $0) } ?? "none"
            Log.audio.notice("Switched the input back to \(keptUID, privacy: .public) from \(replaced, privacy: .public)")
        }
        catch {
            Log.audio.error("\(error, privacy: .public)")
        }
    }
}
