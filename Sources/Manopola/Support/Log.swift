import OSLog

/// Logger categories from docs/DESIGN.md §7.8.
enum Log {
    private static let subsystem = "com.panjas.Manopola"

    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let control = Logger(subsystem: subsystem, category: "control")
    static let dial = Logger(subsystem: subsystem, category: "dial")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
