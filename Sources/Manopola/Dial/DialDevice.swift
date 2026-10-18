import AppKit
import IOKit.hid

/// Owns the IOKit HID session for the Surface Dial: discovery, input reports, haptics and recovery (docs/DESIGN.md §7.2).
///
/// The manager is scheduled on the main run loop, so every IOKit callback arrives on the main thread.
final class DialDevice: HapticFeedback {
    var onEvent: ((DialEvent) -> Void)?
    var onConnectionChange: ((DialConnection) -> Void)?
    var onAccessDenied: (() -> Void)?
    private(set) var connection = DialConnection.notConnected

    var isConnected: Bool {
        connection == .connected
    }

    // The Dial powers down when idle and may come back with its default configuration.
    private static let idleReconfigurationThreshold: Duration = .seconds(15)
    private static let rebuildDelay: Duration = .seconds(1)
    // The Dial's buzz waveform is continuous and never ends on its own (docs/DESIGN.md §7.1), so the end stop is cut
    // to a short pulse with an explicit Stop trigger.
    private static let endStopBuzzDuration: Duration = .milliseconds(100)

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    /// A matched Dial that another process holds exclusively.
    private var blockedDevice: IOHIDDevice?
    private var isPressed = false
    private var lastReportTime: ContinuousClock.Instant?
    private var detentsPerRevolution = 36
    private var hapticsEnabled = true
    private var hasRequestedAccess = false
    private var rebuildTask: Task<Void, Never>?
    private var buzzStopTask: Task<Void, Never>?
    private var wakeObserver: (any NSObjectProtocol)?

    func start() {
        guard manager == nil else { return }
        observeWake()
        openManager()
    }

    func stop() {
        rebuildTask?.cancel()
        rebuildTask = nil
        buzzStopTask?.cancel()
        buzzStopTask = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        closeManager()
    }

    /// Another process may have released the Dial. IOKit sends no notification for that, so the app retries on occasions
    /// the user causes (menu opened, app activated) instead of polling.
    func retryIfInUseElsewhere() {
        guard connection == .inUseElsewhere, manager != nil else { return }
        Log.dial.info("Retrying a Surface Dial held by another process")
        closeManager(keepingConnection: true)
        openManager()
        // Matching callbacks arrive asynchronously; if the Dial vanished meanwhile, none will, so check right away.
        if let manager, let devices = IOHIDManagerCopyDevices(manager), CFSetGetCount(devices) > 0 {
            return
        }
        blockedDevice = nil
        setConnection(.notConnected)
    }

    /// Stored while disconnected and applied on the next match.
    func configure(detentsPerRevolution: Int, hapticsEnabled: Bool) {
        self.detentsPerRevolution = detentsPerRevolution
        self.hapticsEnabled = hapticsEnabled
        sendConfiguration()
    }

    // MARK: - Haptic Feedback

    func endStop() {
        playHaptic(.buzz)
        buzzStopTask = Task { [weak self] in
            try? await Task.sleep(for: Self.endStopBuzzDuration)
            guard !Task.isCancelled, let self else { return }
            buzzStopTask = nil
            sendTrigger(.stop, repeatCount: 0, retriggerMilliseconds: 0)
        }
    }

    func muteToggled(isMuted: Bool) {
        if isMuted {
            playHaptic(.click, repeatCount: 1, retriggerMilliseconds: 120)
        }
        else {
            playHaptic(.click)
        }
    }

    /// Calls while disconnected are ignored.
    func playHaptic(_ waveform: HapticWaveform, repeatCount: UInt8 = 0, retriggerMilliseconds: UInt16 = 0) {
        // A new waveform replaces a running buzz, so a pending Stop would only cut the new one short.
        buzzStopTask?.cancel()
        buzzStopTask = nil
        sendTrigger(waveform, repeatCount: repeatCount, retriggerMilliseconds: retriggerMilliseconds)
    }

    private func sendTrigger(_ waveform: HapticWaveform, repeatCount: UInt8, retriggerMilliseconds: UInt16) {
        let bytes = DialReport.manualTrigger(waveform: waveform, repeatCount: repeatCount, retriggerMilliseconds: retriggerMilliseconds)
        sendReport(kIOHIDReportTypeOutput, bytes)
    }

    // MARK: - Session

    private func openManager() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = [kIOHIDVendorIDKey: DialReport.vendorID, kIOHIDProductIDKey: DialReport.productID] as CFDictionary
        IOHIDManagerSetDeviceMatching(manager, matching)

        // DialDevice lives for the whole app lifetime and unregisters in closeManager(), so an unretained context is safe.
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, dialDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, dialDeviceRemoved, context)
        IOHIDManagerRegisterInputReportCallback(manager, dialInputReportReceived, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.manager = manager

        Log.dial.info("Input Monitoring access: \(Self.describe(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)), privacy: .public)")

        // Seizing stops macOS from turning the Dial's reports into stray pointer events.
        var result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        var mode = "seized"
        if result == kIOReturnExclusiveAccess {
            Log.dial.notice("Seizing the Dial was refused, falling back to shared mode")
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            mode = "shared"
        }

        switch result {
            case kIOReturnSuccess:
                Log.dial.info("HID manager opened in \(mode, privacy: .public) mode")
            case kIOReturnNotPermitted:
                handleAccessDenied()
            case kIOReturnExclusiveAccess:
                // The matching callback still fires for the held device and marks it as in use elsewhere.
                Log.dial.notice("Another process holds the Surface Dial exclusively")
            default:
                Log.dial.error("Opening the HID manager failed: \(Self.describe(result), privacy: .public)")
        }
    }

    /// `keepingConnection` leaves the published state alone during a retry, so the menu does not flicker to "Not Connected".
    private func closeManager(keepingConnection: Bool = false) {
        guard let manager else { return }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerRegisterInputReportCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        if keepingConnection {
            resetDeviceState()
        }
        else {
            deviceDidDisappear()
        }
    }

    private func handleAccessDenied() {
        Log.dial.error("Opening the HID manager is not permitted")
        if !hasRequestedAccess {
            hasRequestedAccess = true
            // Shows the system Input Monitoring prompt once per launch.
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        onAccessDenied?()
    }

    // MARK: - Recovery

    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRebuild(reason: "Mac woke from sleep")
            }
        }
    }

    /// A pending rebuild is cancelled and rescheduled if another trigger arrives.
    private func scheduleRebuild(reason: String) {
        Log.dial.notice("Rebuilding the HID session shortly: \(reason, privacy: .public)")
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: Self.rebuildDelay)
            guard !Task.isCancelled, let self else { return }
            self.rebuildTask = nil
            self.closeManager()
            self.openManager()
        }
    }

    // MARK: - Device Callbacks

    fileprivate func deviceMatched(_ matched: IOHIDDevice) {
        if let device {
            if !CFEqual(device, matched) {
                Log.dial.notice("Ignoring an additional Surface Dial")
            }
            return
        }

        // A match alone does not mean the Dial is usable: when another process has seized it, IOKit still reports the
        // match but refuses every report. The haptic configuration is the first report, so its result decides.
        let result = sendReport(kIOHIDReportTypeFeature, configurationReport(), to: matched)
        switch result {
            case kIOReturnExclusiveAccess:
                Log.dial.notice("Surface Dial found, but another process holds it exclusively")
                blockedDevice = matched
                setConnection(.inUseElsewhere)
                return
            case kIOReturnNotOpen, kIOReturnNotPermitted:
                Log.dial.error("Surface Dial found, but it could not be opened: \(Self.describe(result), privacy: .public)")
                return
            default:
                // Other failures, such as a Bluetooth timeout, are logged by sendReport; the Dial is still usable.
                break
        }

        blockedDevice = nil
        device = matched
        isPressed = false
        lastReportTime = ContinuousClock.now

        let transport = IOHIDDeviceGetProperty(matched, kIOHIDTransportKey as CFString) as? String ?? "unknown"
        let maxInputSize = IOHIDDeviceGetProperty(matched, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0
        Log.dial.info("Surface Dial connected, transport \(transport, privacy: .public), max input report \(maxInputSize) bytes")
        setConnection(.connected)
    }

    fileprivate func deviceRemoved(_ removed: IOHIDDevice) {
        if let blockedDevice, CFEqual(blockedDevice, removed) {
            Log.dial.info("Surface Dial held by another process disappeared")
            deviceDidDisappear()
            return
        }
        guard let device, CFEqual(device, removed) else { return }
        Log.dial.info("Surface Dial disconnected")
        deviceDidDisappear()
    }

    fileprivate func inputReportReceived(result: IOReturn, senderAddress: UInt, reportID: UInt32, bytes: [UInt8]) {
        guard result == kIOReturnSuccess else {
            scheduleRebuild(reason: "input report error \(Self.describe(result))")
            return
        }
        // The manager reports for every matched device; only the first Dial is used.
        guard let device, senderAddress == UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()) else { return }

        Log.dial.debug("Input report ID \(reportID), \(bytes.count) bytes: \(Self.hex(bytes), privacy: .public)")

        let now = ContinuousClock.now
        if let lastReportTime, now - lastReportTime >= Self.idleReconfigurationThreshold {
            Log.dial.info("First report after idle, re-sending the haptic configuration")
            sendConfiguration()
        }
        lastReportTime = now

        guard let report = DialReport.parseInput(reportID: reportID, bytes: bytes) else {
            Log.dial.debug("Ignoring unrecognized input report")
            return
        }

        if report.isPressed != isPressed {
            isPressed = report.isPressed
            onEvent?(isPressed ? .pressed : .released)
        }
        if report.delta != 0 {
            onEvent?(.rotated(detents: Int(report.delta)))
        }
    }

    // MARK: - Reports

    private func deviceDidDisappear() {
        resetDeviceState()
        setConnection(.notConnected)
    }

    private func resetDeviceState() {
        device = nil
        blockedDevice = nil
        isPressed = false
        lastReportTime = nil
    }

    private func setConnection(_ newConnection: DialConnection) {
        guard newConnection != connection else { return }
        connection = newConnection
        onConnectionChange?(newConnection)
    }

    private func sendConfiguration() {
        guard let device else { return }
        sendReport(kIOHIDReportTypeFeature, configurationReport(), to: device)
    }

    private func configurationReport() -> [UInt8] {
        DialReport.hapticConfiguration(detentsPerRevolution: detentsPerRevolution, hapticsEnabled: hapticsEnabled)
    }

    private func sendReport(_ type: IOHIDReportType, _ bytes: [UInt8]) {
        guard let device else { return }
        sendReport(type, bytes, to: device)
    }

    @discardableResult
    private func sendReport(_ type: IOHIDReportType, _ bytes: [UInt8], to device: IOHIDDevice) -> IOReturn {
        // The buffer includes the report ID byte.
        let result = IOHIDDeviceSetReport(device, type, CFIndex(DialReport.reportID), bytes, bytes.count)
        switch result {
            case kIOReturnSuccess:
                Log.dial.debug("Sent report \(Self.hex(bytes), privacy: .public)")
            case kIOReturnExclusiveAccess:
                // Expected while another process holds the Dial; the caller decides what it means.
                Log.dial.debug("Report \(Self.hex(bytes), privacy: .public) refused: exclusive access")
            default:
                Log.dial.error("Sending report \(Self.hex(bytes), privacy: .public) failed: \(Self.describe(result), privacy: .public)")
        }
        return result
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { byte in
            let digits = String(byte, radix: 16, uppercase: true)
            return byte < 0x10 ? "0" + digits : digits
        }
        .joined(separator: " ")
    }

    private static func describe(_ result: IOReturn) -> String {
        "0x" + String(UInt32(bitPattern: result), radix: 16)
    }

    private static func describe(_ access: IOHIDAccessType) -> String {
        switch access {
            case kIOHIDAccessTypeGranted: "granted"
            case kIOHIDAccessTypeDenied: "denied"
            default: "unknown"
        }
    }
}

// MARK: - IOKit Callbacks

// C callbacks cannot capture context, so they recover the DialDevice from the context pointer. DialDevice is main-actor
// isolated and therefore Sendable. The manager is scheduled on the main run loop, which makes entering the main actor
// synchronously safe.

nonisolated private func dialDeviceMatched(
    context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice
) {
    guard let context else { return }
    let dialDevice = Unmanaged<DialDevice>.fromOpaque(context).takeUnretainedValue()
    // IOHIDDevice is not Sendable, but it never leaves the main thread: this callback runs on the main run loop.
    nonisolated(unsafe) let device = device
    MainActor.assumeIsolated {
        dialDevice.deviceMatched(device)
    }
}

nonisolated private func dialDeviceRemoved(
    context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice
) {
    guard let context else { return }
    let dialDevice = Unmanaged<DialDevice>.fromOpaque(context).takeUnretainedValue()
    // See dialDeviceMatched.
    nonisolated(unsafe) let device = device
    MainActor.assumeIsolated {
        dialDevice.deviceRemoved(device)
    }
}

nonisolated private func dialInputReportReceived(
    context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, type: IOHIDReportType,
    reportID: UInt32, report: UnsafeMutablePointer<UInt8>, reportLength: CFIndex
) {
    guard let context else { return }
    let dialDevice = Unmanaged<DialDevice>.fromOpaque(context).takeUnretainedValue()
    // Copy the bytes out; the buffer belongs to IOKit and is only valid during the callback.
    let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
    let senderAddress = UInt(bitPattern: sender)
    MainActor.assumeIsolated {
        dialDevice.inputReportReceived(result: result, senderAddress: senderAddress, reportID: reportID, bytes: bytes)
    }
}
