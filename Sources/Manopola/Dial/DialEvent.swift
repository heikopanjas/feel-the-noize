/// Device-independent vocabulary for what happened on the Dial.
enum DialEvent: Equatable {
    /// Positive is clockwise, before the reverse-direction preference is applied.
    case rotated(detents: Int)
    case pressed
    case released
}
