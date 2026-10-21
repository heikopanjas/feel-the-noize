import AppKit

/// Non-resizable settings window with General and Devices tabs, centered on first show (Docs/DESIGN.md §7.6).
final class SettingsWindowController: NSWindowController {
    private var hasBeenShown = false

    init(settings: Settings) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let viewControllers: [(NSViewController, String)] = [
            (GeneralSettingsViewController(settings: settings), "gearshape"),
            (DeviceSettingsViewController(settings: settings), "hifispeaker.2")
        ]
        for (viewController, symbol) in viewControllers {
            let item = NSTabViewItem(viewController: viewController)
            item.label = viewController.title ?? ""
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.label)
            tabs.addTabViewItem(item)
        }

        // The window title follows the selected tab, as in macOS Settings.
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func show() -> Void {
        if self.hasBeenShown == false {
            self.window?.center()
            self.hasBeenShown = true
        }
        // The app is an LSUIElement agent, so it has to activate itself for the window to come to the front.
        NSApp.activate()
        self.showWindow(nil)
        self.window?.makeKeyAndOrderFront(nil)
    }
}
