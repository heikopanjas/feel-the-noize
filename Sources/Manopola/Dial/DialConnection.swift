/// Whether Manopola can use the Dial.
enum DialConnection: Equatable {
    case notConnected
    case connected
    /// Present, but another process holds it exclusively, for example another Dial utility or a second Manopola.
    case inUseElsewhere
}
