import Foundation
import Testing

/// `UserDefaults` suites for tests that never touch `~/Library/Preferences`. A domain named by an absolute path is stored
/// as a plist at that path, so every suite lives in one temporary directory that the first use in a test run clears and
/// recreates. A suite with a plain name cannot be cleaned up: `removePersistentDomain` leaves an empty plist, and
/// `cfprefsd` writes a deleted one back later.
enum TemporaryUserDefaults {
    private static let directory: URL = {
        let directory = FileManager.default.temporaryDirectory.appending(path: "FeelTheNoizeTests.UserDefaults", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    /// A fresh, empty domain.
    static func make() throws -> UserDefaults {
        return try #require(UserDefaults(suiteName: Self.directory.appending(path: UUID().uuidString).path))
    }
}
