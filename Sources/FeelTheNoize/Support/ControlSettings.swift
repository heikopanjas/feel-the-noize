/// The settings `DialController` reads on every event (Docs/DESIGN.md §7.3, §7.7).
struct ControlSettings: Equatable {
    var stepPercent: Int
    var reverseDirection: Bool
    /// Output devices the Dial must leave alone, by Core Audio UID.
    var excludedDeviceUIDs: Set<String> = []
}
