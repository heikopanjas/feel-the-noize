import AppKit
import Foundation

// No storyboard: the app delegate is created and installed by hand.
// NSApplication.delegate is weak, so the global constant keeps it alive.
let appDelegate = AppDelegate()

// Unit tests run inside the app as their host. Without the delegate the host neither seizes the Dial nor touches audio,
// so a test run cannot interfere with a running Manopola.
let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
if !isTestHost {
    NSApplication.shared.delegate = appDelegate
}
NSApplication.shared.run()
