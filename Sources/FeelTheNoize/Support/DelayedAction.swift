/// A main-actor timer for one pending action: `schedule` replaces any pending action, `cancel` drops it
/// (Docs/DESIGN.md §8). The end-stop Stop trigger, the HID session rebuild, the rejected-write window and the overlay
/// fade all share it instead of each rolling its own task.
final class DelayedAction {
    /// Waits for the delay; `Task.sleep` in the app, `ManualSleeper` in the tests.
    private let sleep: (Duration) async -> Void
    private var task: Task<Void, Never>?

    var isPending: Bool {
        return self.task != nil
    }

    init(sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    /// Runs `action` after `delay`, unless `schedule` or `cancel` is called again first.
    func schedule(after delay: Duration, _ action: @escaping () -> Void) -> Void {
        self.task?.cancel()
        self.task = Task { [weak self, sleep = self.sleep] in
            await sleep(delay)
            guard Task.isCancelled == false, let self else {
                return
            }
            self.task = nil
            action()
        }
    }

    func cancel() -> Void {
        self.task?.cancel()
        self.task = nil
    }
}
