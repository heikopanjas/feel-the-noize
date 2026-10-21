import AppKit
import Foundation

// No storyboard: the app delegate is created and installed by hand.
// NSApplication.delegate is weak, so the global constant keeps it alive.
let appDelegate = AppDelegate()

// Unit tests run inside the app as their host. Without the delegate the host neither seizes the Dial nor touches audio,
// so a test run cannot interfere with a running instance of the app. Swift Testing under xcodebuild still launches the
// host through the XCTest harness, which sets this variable; should an Xcode release stop doing so, the first symptom
// is a test run that seizes the Dial (Docs/DESIGN.md §11.1).
let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
if !isTestHost {
    NSApplication.shared.delegate = appDelegate
}
NSApplication.shared.run()
