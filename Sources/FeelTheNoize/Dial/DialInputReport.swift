/// Decoded payload of input report 1 (Docs/DESIGN.md §7.1).
struct DialInputReport: Equatable {
    let isPressed: Bool
    let delta: Int16
}
