import AppKit
import IOKit.hid

/// Owns the IOKit HID session for the Surface Dial: discovery, input reports, haptics and recovery (docs/DESIGN.md §7.2).
///
/// The manager is scheduled on the main run loop, so every IOKit callback arrives on the main thread.
final class DialDevice: HapticFeedback {
    var onEvent: ((DialEvent) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    var onAccessDenied: (() -> Void)?
    private(set) var isConnected = false

    // The Dial powers down when idle and may come back with its default configuration.
    private static let idleReconfigurationThreshold: Duration = .seconds(15)
    private static let rebuildDelay: Duration = .seconds(1)

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var isPressed = false
    private var lastReportTime: ContinuousClock.Instant?
    private var detentsPerRevolution = 36
    private var hapticsEnabled = true
    private var hasRequestedAccess = false
    private var rebuildTask: Task<Void, Never>?
    private var wakeObserver: (any NSObjectProtocol)?

    func start() {
        guard manager == nil else { return }
        observeWake()
        openManager()
    }

    func stop() {
        rebuildTask?.cancel()
        rebuildTask = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        closeManager()
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
            default:
                Log.dial.error("Opening the HID manager failed: \(Self.describe(result), privacy: .public)")
        }
    }

    private func closeManager() {
        guard let manager else { return }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerRegisterInputReportCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        deviceDidDisappear()
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

        device = matched
        isConnected = true
        isPressed = false
        lastReportTime = ContinuousClock.now

        let transport = IOHIDDeviceGetProperty(matched, kIOHIDTransportKey as CFString) as? String ?? "unknown"
        let maxInputSize = IOHIDDeviceGetProperty(matched, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0
        Log.dial.info("Surface Dial connected, transport \(transport, privacy: .public), max input report \(maxInputSize) bytes")

        sendConfiguration()
        onConnectionChange?(true)
    }

    fileprivate func deviceRemoved(_ removed: IOHIDDevice) {
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
        device = nil
        isPressed = false
        lastReportTime = nil
        guard isConnected else { return }
        isConnected = false
        onConnectionChange?(false)
    }

    private func sendConfiguration() {
        let bytes = DialReport.hapticConfiguration(detentsPerRevolution: detentsPerRevolution, hapticsEnabled: hapticsEnabled)
        sendReport(kIOHIDReportTypeFeature, bytes)
    }

    private func sendReport(_ type: IOHIDReportType, _ bytes: [UInt8]) {
        guard let device else { return }
        // The buffer includes the report ID byte.
        let result = IOHIDDeviceSetReport(device, type, CFIndex(DialReport.reportID), bytes, bytes.count)
        if result == kIOReturnSuccess {
            Log.dial.debug("Sent report \(Self.hex(bytes), privacy: .public)")
        }
        else {
            Log.dial.error("Sending report \(Self.hex(bytes), privacy: .public) failed: \(Self.describe(result), privacy: .public)")
        }
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
