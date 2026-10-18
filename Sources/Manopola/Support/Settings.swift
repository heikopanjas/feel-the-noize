import Foundation

/// The settings `DialController` reads on every event.
struct ControlSettings: Equatable {
    var stepPercent: Int
    var reverseDirection: Bool
    /// Output devices the Dial must leave alone, by Core Audio UID.
    var excludedDeviceUIDs: Set<String> = []
}

/// Typed wrapper around `UserDefaults` (docs/DESIGN.md §7.7). Out-of-range stored values fall back to the default.
final class Settings {
    static let detentChoices = [18, 24, 36, 48, 72]
    static let stepPercentChoices = [1, 2, 3, 5]

    private enum Key {
        static let detentsPerRevolution = "detentsPerRevolution"
        static let volumeStepPercent = "volumeStepPercent"
        static let reverseDirection = "reverseDirection"
        static let hapticDetents = "hapticDetents"
        static let showOverlay = "showOverlay"
        static let iconStyle = "iconStyle"
        static let excludedOutputDevices = "excludedOutputDevices"
        static let knownOutputDevices = "knownOutputDevices"
        static let softwareVolumeDevices = "softwareVolumeDevices"
        static let softwareVolumeLevels = "softwareVolumeLevels"
    }

    private static let defaultDetents = 36
    private static let defaultStepPercent = 2

    /// Called after every write.
    var onChange: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.detentsPerRevolution: Self.defaultDetents,
            Key.volumeStepPercent: Self.defaultStepPercent,
            Key.reverseDirection: false,
            Key.hapticDetents: true,
            Key.showOverlay: true,
            Key.iconStyle: KnobIcon.Style.arc.rawValue
        ])
    }

    var detentsPerRevolution: Int {
        get { Self.validated(defaults.integer(forKey: Key.detentsPerRevolution), in: Self.detentChoices, fallback: Self.defaultDetents) }
        set { write(newValue, forKey: Key.detentsPerRevolution) }
    }

    var volumeStepPercent: Int {
        get { Self.validated(defaults.integer(forKey: Key.volumeStepPercent), in: Self.stepPercentChoices, fallback: Self.defaultStepPercent) }
        set { write(newValue, forKey: Key.volumeStepPercent) }
    }

    var reverseDirection: Bool {
        get { defaults.bool(forKey: Key.reverseDirection) }
        set { write(newValue, forKey: Key.reverseDirection) }
    }

    var hapticDetents: Bool {
        get { defaults.bool(forKey: Key.hapticDetents) }
        set { write(newValue, forKey: Key.hapticDetents) }
    }

    var showOverlay: Bool {
        get { defaults.bool(forKey: Key.showOverlay) }
        set { write(newValue, forKey: Key.showOverlay) }
    }

    /// The knob drawn in the menu bar and the overlay; unknown stored values fall back to the arc.
    var iconStyle: KnobIcon.Style {
        get { defaults.string(forKey: Key.iconStyle).flatMap(KnobIcon.Style.init(rawValue:)) ?? .arc }
        set { write(newValue.rawValue, forKey: Key.iconStyle) }
    }

    var controlSettings: ControlSettings {
        ControlSettings(stepPercent: volumeStepPercent, reverseDirection: reverseDirection, excludedDeviceUIDs: excludedDeviceUIDs)
    }

    // MARK: - Output Devices

    /// Stored as exclusions, so devices the app has never seen are enabled and it works out of the box.
    var excludedDeviceUIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.excludedOutputDevices) ?? []) }
        set { write(newValue.sorted(), forKey: Key.excludedOutputDevices) }
    }

    func isDeviceEnabled(_ uid: String) -> Bool {
        !excludedDeviceUIDs.contains(uid)
    }

    func setDevice(_ uid: String, enabled: Bool) {
        var excluded = excludedDeviceUIDs
        if enabled {
            excluded.remove(uid)
        }
        else {
            excluded.insert(uid)
        }
        guard excluded != excludedDeviceUIDs else { return }
        excludedDeviceUIDs = excluded
    }

    /// Names of every output device seen so far, by UID, so absent devices can still be listed and configured.
    var knownDevices: [String: String] {
        defaults.dictionary(forKey: Key.knownOutputDevices) as? [String: String] ?? [:]
    }

    // MARK: - Software Volume

    /// Devices without volume control on which the user turned on software volume (docs/DESIGN.md §7.9).
    var softwareVolumeDeviceUIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.softwareVolumeDevices) ?? []) }
        set { write(newValue.sorted(), forKey: Key.softwareVolumeDevices) }
    }

    func setSoftwareVolume(_ uid: String, enabled: Bool) {
        var uids = softwareVolumeDeviceUIDs
        if enabled {
            uids.insert(uid)
        }
        else {
            uids.remove(uid)
        }
        guard uids != softwareVolumeDeviceUIDs else { return }
        softwareVolumeDeviceUIDs = uids
    }

    /// Writes, and so calls `onChange`, only when a device or name is new.
    func rememberDevices(_ names: [String: String]) {
        let known = knownDevices
        let merged = known.merging(names) { _, new in new }
        guard merged != known else { return }
        write(merged, forKey: Key.knownOutputDevices)
    }

    private func write(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }

    private static func validated(_ value: Int, in choices: [Int], fallback: Int) -> Int {
        choices.contains(value) ? value : fallback
    }
}

// MARK: - Software Volume Preferences

extension Settings: SoftwareVolumePreferences {
    /// An excluded device is left alone entirely, software volume included.
    func wantsSoftwareVolume(_ uid: String) -> Bool {
        softwareVolumeDeviceUIDs.contains(uid) && isDeviceEnabled(uid)
    }

    /// Starts at full level, so turning software volume on changes nothing audible.
    func softwareVolumeLevel(_ uid: String) -> Float {
        let levels = defaults.dictionary(forKey: Key.softwareVolumeLevels) as? [String: Double] ?? [:]
        return Float(min(max(levels[uid] ?? 1, 0), 1))
    }

    /// Written on every Dial step, so it bypasses `onChange` to avoid a settings refresh per detent.
    func setSoftwareVolumeLevel(_ uid: String, _ level: Float) {
        var levels = defaults.dictionary(forKey: Key.softwareVolumeLevels) as? [String: Double] ?? [:]
        levels[uid] = Double(level)
        defaults.set(levels, forKey: Key.softwareVolumeLevels)
    }
}
