/// Whether Feel the Noize can use the Dial.
enum DialConnection: Equatable {
    case notConnected
    case connected
    /// Present, but another process holds it exclusively, for example another Dial utility or a second instance of Feel the Noize.
    case inUseElsewhere
}
