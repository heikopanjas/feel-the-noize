import AppKit

/// Keeps the Surface Dial out of its 5-minute idle sleep while the Mac is in use, so the first turn is not lost to the
/// 1.6 s reconnect (docs/DESIGN.md §7.14).
///
/// The Mac counts as in use while its displays are awake. That also covers watching a video without touching the Mac,
/// where adjusting the volume matters most. The timer runs only while keep-awake is on, the Dial is connected and the
/// displays are awake, so once the user leaves, the displays sleep, the Dial sleeps 5 minutes later and nothing ticks.
final class DialKeepAwake {
    /// The Dial sleeps 4 min 57 s after its last report. macOS delayed a 4-minute timer of this background app by 15 s,
    /// so the interval keeps a wide margin.
    static let interval: Duration = .seconds(180)

    var isEnabled = false {
        didSet { update() }
    }

    var isDialConnected = false {
        didSet { update() }
    }

    var areDisplaysAwake = true {
        didSet { update() }
    }

    var isRunning: Bool {
        task != nil
    }

    private let interval: Duration
    private let send: () -> Void
    private var task: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    init(interval: Duration = DialKeepAwake.interval, send: @escaping () -> Void) {
        self.interval = interval
        self.send = send
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let changes = [(NSWorkspace.screensDidSleepNotification, false), (NSWorkspace.screensDidWakeNotification, true)]
        observers = changes.map { name, isAwake in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.areDisplaysAwake = isAwake
                }
            }
        }
    }

    /// Sends one report right away, only while the timer runs. A Dial that was already awake at launch may have been idle
    /// for minutes, so its first report cannot wait a full interval.
    func sendNow() {
        guard isRunning else { return }
        send()
    }

    func stop() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers = []
        task?.cancel()
        task = nil
    }

    // MARK: - Timer

    private func update() {
        let shouldRun = isEnabled && isDialConnected && areDisplaysAwake
        guard shouldRun != isRunning else { return }
        guard shouldRun else {
            Log.dial.info("Keep-awake paused")
            task?.cancel()
            task = nil
            return
        }
        Log.dial.info("Keep-awake running")
        // The first report waits a full interval: the Dial has just connected or been in use, and an immediate Stop
        // trigger would cut the ready click short. A Dial awake at launch gets its first report through sendNow().
        task = Task { [weak self, interval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                send()
            }
        }
    }
}
