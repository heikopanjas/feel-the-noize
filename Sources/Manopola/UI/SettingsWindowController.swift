import AppKit

/// Non-resizable preferences window, centered on first show (docs/DESIGN.md §7.6).
final class SettingsWindowController: NSWindowController {
    private var hasBeenShown = false

    init(settings: Settings) {
        let window = NSWindow(contentViewController: SettingsViewController(settings: settings))
        window.styleMask = [.titled, .closable]
        window.title = "Manopola Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        if !hasBeenShown {
            window?.center()
            hasBeenShown = true
        }
        // The app is an LSUIElement agent, so it has to activate itself for the window to come to the front.
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
