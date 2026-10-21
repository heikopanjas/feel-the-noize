import AppKit

/// Keeps the Surface Dial out of its 5-minute idle sleep while the Mac is in use, so the first turn is not lost to the
/// 1.6 s reconnect (Docs/DESIGN.md §7.14).
///
/// The Mac counts as in use while its displays are awake. That also covers watching a video without touching the Mac,
/// where adjusting the volume matters most. The timer runs only while keep-awake is on, the Dial is connected and the
/// displays are awake, so once the user leaves, the displays sleep, the Dial sleeps 5 minutes later and nothing ticks.
final class DialKeepAwake {
    /// The Dial sleeps 4 min 57 s after its last report. macOS delayed a 4-minute timer of this background app by 15 s,
    /// so the interval keeps a wide margin.
    static let interval: Duration = .seconds(180)

    var isEnabled = false {
        didSet {
            self.update()
        }
    }

    var isDialConnected = false {
        didSet {
            self.update()
        }
    }

    var areDisplaysAwake = true {
        didSet {
            self.update()
        }
    }

    var isRunning: Bool {
        return self.task != nil
    }

    private let interval: Duration
    /// Waits one interval; `Task.sleep` in the app, a hand-driven stand-in in the tests, so no test waits on the clock.
    private let sleep: (Duration) async -> Void
    private let send: () -> Void
    private var task: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    init(
        interval: Duration = DialKeepAwake.interval, sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        send: @escaping () -> Void
    ) {
        self.interval = interval
        self.sleep = sleep
        self.send = send
    }

    func start() -> Void {
        guard self.observers.isEmpty == true else {
            return
        }
        let center = NSWorkspace.shared.notificationCenter
        let changes = [(NSWorkspace.screensDidSleepNotification, false), (NSWorkspace.screensDidWakeNotification, true)]
        self.observers = changes.map { name, isAwake in
            return center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.areDisplaysAwake = isAwake
                }
            }
        }
    }

    /// Sends one report right away, only while the timer runs. A Dial that was already awake at launch may have been idle
    /// for minutes, so its first report cannot wait a full interval.
    func sendNow() -> Void {
        guard self.isRunning == true else {
            return
        }
        self.send()
    }

    func stop() -> Void {
        for observer in self.observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        self.observers = []
        self.task?.cancel()
        self.task = nil
    }

    // MARK: - Timer

    private func update() -> Void {
        let shouldRun = self.isEnabled == true && self.isDialConnected == true && self.areDisplaysAwake == true
        if shouldRun == self.isRunning {
            return
        }
        if shouldRun == false {
            Log.dial.info("Keep-awake paused")
            self.task?.cancel()
            self.task = nil
            return
        }
        Log.dial.info("Keep-awake running")
        // The first report waits a full interval: the Dial has just connected or been in use, and an immediate Stop
        // trigger would cut the ready click short. A Dial awake at launch gets its first report through sendNow().
        self.task = Task { [weak self, interval = self.interval, sleep = self.sleep] in
            while Task.isCancelled == false {
                await sleep(interval)
                if Task.isCancelled == true {
                    return
                }
                if let self = self {
                    self.send()
                }
                else {
                    return
                }
            }
        }
    }
}
