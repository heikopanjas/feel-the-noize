import IOKit.pwr_mgt

/// Tells macOS that the user is active while the Dial is in use, as the mouse does (docs/DESIGN.md §7.15).
///
/// Manopola seizes the Dial, so its reports never reach the HID event system. Without this, a sleeping display would not
/// wake when the Dial turns, and the screen saver would start while the user adjusts the volume.
///
/// Two assertions are needed. Declared user activity wakes the display and resets powerd's idle timer, but not the HID
/// idle time that loginwindow uses to start the screen saver (measured 2026-10-19). A display sleep hold covers that:
/// loginwindow does not start the screen saver while display sleep is blocked.
final class UserActivity {
    /// A fast spin delivers about 50 reports per second; powerd needs to hear about it far less often.
    static let minimumInterval: Duration = .seconds(1)
    /// The macOS default screen saver delay, so the screen saver starts about as long after the last Dial use as after
    /// the last mouse use. powerd ends the hold on its own, so no timer runs in the app.
    static let screenSaverHoldSeconds: CFTimeInterval = 300
    private static let assertionName = "Surface Dial in use" as CFString

    private let minimumInterval: Duration
    private let declareActivity: () -> IOReturn
    private var lastDeclaration: ContinuousClock.Instant?
    private var hasLoggedFailure = false

    convenience init() {
        // Passing the same ID again updates the activity assertion instead of creating a new one.
        var activityID = IOPMAssertionID(kIOPMNullAssertionID)
        // The hold turns off at its timeout but keeps its ID; setting the timeout again re-arms or extends it.
        var holdID = IOPMAssertionID(kIOPMNullAssertionID)
        self.init {
            let activity = IOPMAssertionDeclareUserActivity(UserActivity.assertionName, kIOPMUserActiveLocal, &activityID)
            let hold =
                holdID == kIOPMNullAssertionID
                ? IOPMAssertionCreateWithDescription(
                    kIOPMAssertPreventUserIdleDisplaySleep as CFString, UserActivity.assertionName, nil, nil, nil,
                    UserActivity.screenSaverHoldSeconds, kIOPMAssertionTimeoutActionTurnOff as CFString, &holdID
                )
                : IOPMAssertionSetProperty(holdID, kIOPMAssertionTimeoutKey as CFString, UserActivity.screenSaverHoldSeconds as CFNumber)
            return activity != kIOReturnSuccess ? activity : hold
        }
    }

    init(minimumInterval: Duration = UserActivity.minimumInterval, declare: @escaping () -> IOReturn) {
        self.minimumInterval = minimumInterval
        declareActivity = declare
    }

    func declare() {
        let now = ContinuousClock.now
        if let lastDeclaration, now - lastDeclaration < minimumInterval {
            return
        }
        lastDeclaration = now
        let result = declareActivity()
        guard result != kIOReturnSuccess, !hasLoggedFailure else { return }
        hasLoggedFailure = true
        Log.control.error("Declaring user activity failed: 0x\(String(UInt32(bitPattern: result), radix: 16), privacy: .public)")
    }
}
