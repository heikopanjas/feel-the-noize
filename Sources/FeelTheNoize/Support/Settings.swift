import Foundation

/// Typed wrapper around `UserDefaults` (Docs/DESIGN.md §7.7). Out-of-range stored values fall back to the default.
final class Settings {
    static let detentChoices = [18, 24, 36, 48, 72]
    static let stepPercentChoices = [1, 2, 3, 5]

    private enum Key {
        static let detentsPerRevolution = "detentsPerRevolution"
        static let volumeStepPercent = "volumeStepPercent"
        static let reverseDirection = "reverseDirection"
        static let hapticDetents = "hapticDetents"
        static let showOverlay = "showOverlay"
        static let keepDialAwake = "keepDialAwake"
        static let iconStyle = "iconStyle"
        static let excludedOutputDevices = "excludedOutputDevices"
        static let knownOutputDevices = "knownOutputDevices"
        static let softwareVolumeDevices = "softwareVolumeDevices"
        static let softwareVolumeLevels = "softwareVolumeLevels"
        static let keptInputDevice = "keptInputDevice"
        static let knownInputDevices = "knownInputDevices"
    }

    private static let defaultDetents = 36
    private static let defaultStepPercent = 2

    /// Called after every write of a setting. Bookkeeping writes bypass it: the remembered device names, which arrive from
    /// `AudioOutput.onChange` and would otherwise refresh the audio output from inside its own callback, and the software
    /// volume levels, written on every Dial step.
    var onChange: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.defaults.register(defaults: [
            Key.detentsPerRevolution: Self.defaultDetents,
            Key.volumeStepPercent: Self.defaultStepPercent,
            Key.reverseDirection: false,
            Key.hapticDetents: true,
            Key.showOverlay: true,
            Key.keepDialAwake: true,
            Key.iconStyle: KnobIcon.Style.arc.rawValue
        ])
    }

    var detentsPerRevolution: Int {
        get {
            return Self.validated(self.defaults.integer(forKey: Key.detentsPerRevolution), in: Self.detentChoices, fallback: Self.defaultDetents)
        }
        set {
            self.write(newValue, forKey: Key.detentsPerRevolution)
        }
    }

    var volumeStepPercent: Int {
        get {
            let stored = self.defaults.integer(forKey: Key.volumeStepPercent)
            return Self.validated(stored, in: Self.stepPercentChoices, fallback: Self.defaultStepPercent)
        }
        set {
            self.write(newValue, forKey: Key.volumeStepPercent)
        }
    }

    var reverseDirection: Bool {
        get {
            return self.defaults.bool(forKey: Key.reverseDirection)
        }
        set {
            self.write(newValue, forKey: Key.reverseDirection)
        }
    }

    var hapticDetents: Bool {
        get {
            return self.defaults.bool(forKey: Key.hapticDetents)
        }
        set {
            self.write(newValue, forKey: Key.hapticDetents)
        }
    }

    var showOverlay: Bool {
        get {
            return self.defaults.bool(forKey: Key.showOverlay)
        }
        set {
            self.write(newValue, forKey: Key.showOverlay)
        }
    }

    /// Keeps the Dial out of its idle sleep while the displays are awake (Docs/DESIGN.md §7.14).
    var keepDialAwake: Bool {
        get {
            return self.defaults.bool(forKey: Key.keepDialAwake)
        }
        set {
            self.write(newValue, forKey: Key.keepDialAwake)
        }
    }

    /// The knob drawn in the menu bar and the overlay; unknown stored values fall back to the arc.
    var iconStyle: KnobIcon.Style {
        get {
            return self.defaults.string(forKey: Key.iconStyle).flatMap(KnobIcon.Style.init(rawValue:)) ?? .arc
        }
        set {
            self.write(newValue.rawValue, forKey: Key.iconStyle)
        }
    }

    var controlSettings: ControlSettings {
        return ControlSettings(
            stepPercent: self.volumeStepPercent, reverseDirection: self.reverseDirection, excludedDeviceUIDs: self.excludedDeviceUIDs)
    }

    // MARK: - Output Devices

    /// Stored as exclusions, so devices the app has never seen are enabled and it works out of the box.
    var excludedDeviceUIDs: Set<String> {
        get {
            return Set(self.defaults.stringArray(forKey: Key.excludedOutputDevices) ?? [])
        }
        set {
            self.write(newValue.sorted(), forKey: Key.excludedOutputDevices)
        }
    }

    func isDeviceEnabled(_ uid: String) -> Bool {
        return self.excludedDeviceUIDs.contains(uid) == false
    }

    func setDevice(_ uid: String, enabled: Bool) -> Void {
        var excluded = self.excludedDeviceUIDs
        if enabled == true {
            excluded.remove(uid)
        }
        else {
            excluded.insert(uid)
        }
        if excluded == self.excludedDeviceUIDs {
            return
        }
        self.excludedDeviceUIDs = excluded
    }

    /// Names of every output device seen so far, by UID, so absent devices can still be listed and configured.
    var knownDevices: [String: String] {
        return self.defaults.dictionary(forKey: Key.knownOutputDevices) as? [String: String] ?? [:]
    }

    // MARK: - Software Volume

    /// Devices without volume control on which the user turned on software volume (Docs/DESIGN.md §7.9).
    var softwareVolumeDeviceUIDs: Set<String> {
        get {
            return Set(self.defaults.stringArray(forKey: Key.softwareVolumeDevices) ?? [])
        }
        set {
            self.write(newValue.sorted(), forKey: Key.softwareVolumeDevices)
        }
    }

    func setSoftwareVolume(_ uid: String, enabled: Bool) -> Void {
        var uids = self.softwareVolumeDeviceUIDs
        if enabled == true {
            uids.insert(uid)
        }
        else {
            uids.remove(uid)
        }
        if uids == self.softwareVolumeDeviceUIDs {
            return
        }
        self.softwareVolumeDeviceUIDs = uids
    }

    /// Writes only when a device or name is new, and never calls `onChange`.
    func rememberDevices(_ names: [String: String]) -> Void {
        self.remember(names, known: self.knownDevices, forKey: Key.knownOutputDevices)
    }

    // MARK: - Input Devices

    /// The input device kept as default while it is connected (Docs/DESIGN.md §7.13); `nil` when the keep is off. Stored as
    /// an empty string for off.
    var keptInputDeviceUID: String? {
        get {
            return self.defaults.string(forKey: Key.keptInputDevice).flatMap { $0.isEmpty == true ? nil : $0 }
        }
        set {
            guard newValue != self.keptInputDeviceUID else {
                return
            }
            self.write(newValue ?? "", forKey: Key.keptInputDevice)
        }
    }

    /// Names of every input device seen so far, by UID, so a kept device can be named while it is disconnected.
    var knownInputDevices: [String: String] {
        return self.defaults.dictionary(forKey: Key.knownInputDevices) as? [String: String] ?? [:]
    }

    /// Writes only when a device or name is new, and never calls `onChange`.
    func rememberInputDevices(_ names: [String: String]) -> Void {
        self.remember(names, known: self.knownInputDevices, forKey: Key.knownInputDevices)
    }

    private func remember(_ names: [String: String], known: [String: String], forKey key: String) -> Void {
        let merged = known.merging(names) { _, new in new }
        if merged == known {
            return
        }
        self.defaults.set(merged, forKey: key)
    }

    private func write(_ value: Any, forKey key: String) -> Void {
        self.defaults.set(value, forKey: key)
        self.onChange?()
    }

    private static func validated(_ value: Int, in choices: [Int], fallback: Int) -> Int {
        return choices.contains(value) == true ? value : fallback
    }
}

// MARK: - Software Volume Preferences

extension Settings: SoftwareVolumePreferences {
    /// An excluded device is left alone entirely, software volume included.
    func wantsSoftwareVolume(_ uid: String) -> Bool {
        guard self.softwareVolumeDeviceUIDs.contains(uid) == true else {
            return false
        }
        return self.isDeviceEnabled(uid)
    }

    /// Starts at full level, so turning software volume on changes nothing audible.
    func softwareVolumeLevel(_ uid: String) -> Float {
        let levels = self.defaults.dictionary(forKey: Key.softwareVolumeLevels) as? [String: Double] ?? [:]
        return Float(min(max(levels[uid] ?? 1, 0), 1))
    }

    /// Written on every Dial step, so it bypasses `onChange` to avoid a settings refresh per detent.
    func setSoftwareVolumeLevel(_ uid: String, _ level: Float) -> Void {
        var levels = self.defaults.dictionary(forKey: Key.softwareVolumeLevels) as? [String: Double] ?? [:]
        levels[uid] = Double(level)
        self.defaults.set(levels, forKey: Key.softwareVolumeLevels)
    }
}
