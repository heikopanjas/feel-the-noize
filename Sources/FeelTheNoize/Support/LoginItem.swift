import ServiceManagement

/// Launch at login through `SMAppService.mainApp`. Not stored in Settings: the service status is the source of truth.
enum LoginItem {
    static var status: SMAppService.Status {
        return SMAppService.mainApp.status
    }

    /// Registered counts as enabled even while it waits for approval in System Settings.
    static var isEnabled: Bool {
        let status = Self.status
        if status == .enabled {
            return true
        }
        return status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) -> Void {
        do {
            if enabled == true {
                try SMAppService.mainApp.register()
            }
            else {
                try SMAppService.mainApp.unregister()
            }
        }
        catch {
            Log.ui.error("Changing launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func openSystemSettings() -> Void {
        SMAppService.openSystemSettingsLoginItems()
    }
}
