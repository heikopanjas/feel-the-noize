import Foundation

/// The settings `DialController` reads on every event.
struct ControlSettings: Equatable {
    var stepPercent: Int
    var reverseDirection: Bool
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
            Key.showOverlay: true
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

    var controlSettings: ControlSettings {
        ControlSettings(stepPercent: volumeStepPercent, reverseDirection: reverseDirection)
    }

    private func write(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }

    private static func validated(_ value: Int, in choices: [Int], fallback: Int) -> Int {
        choices.contains(value) ? value : fallback
    }
}
