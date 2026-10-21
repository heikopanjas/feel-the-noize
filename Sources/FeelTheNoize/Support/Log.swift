import OSLog

/// Logger categories from Docs/DESIGN.md §7.8.
enum Log {
    private static let subsystem = "com.panjas.FeelTheNoize"

    // The type name rather than `Self`: a static stored property initializer cannot refer to `Self`.
    static let audio = Logger(subsystem: Log.subsystem, category: "audio")
    static let control = Logger(subsystem: Log.subsystem, category: "control")
    static let dial = Logger(subsystem: Log.subsystem, category: "dial")
    static let ui = Logger(subsystem: Log.subsystem, category: "ui")
}
