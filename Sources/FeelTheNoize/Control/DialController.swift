/// Gesture recognizer and the only place that decides what a Dial event does (Docs/DESIGN.md §7.3).
final class DialController {
    private enum Gesture {
        case idle
        case pressedStill
        case pressedTurned
    }

    // A continuous spin past 0 % or 100 % buzzes once; the next buzz needs a pause of this length between end-stop hits.
    private static let endStopQuietPeriod: Duration = .milliseconds(300)
    private static let fineStepDivisor: Float32 = 4

    var onAdjusted: ((AudioState) -> Void)?

    private let audio: any AudioControlling
    private let haptics: any HapticFeedback
    private let settings: () -> ControlSettings
    private let now: () -> ContinuousClock.Instant
    private var gesture = Gesture.idle
    private var lastEndStopHit: ContinuousClock.Instant?

    init(
        audio: any AudioControlling, haptics: any HapticFeedback, settings: @escaping () -> ControlSettings,
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.audio = audio
        self.haptics = haptics
        self.settings = settings
        self.now = now
    }

    func handle(_ event: DialEvent) -> Void {
        switch event {
            case .rotated(let detents):
                self.rotate(by: detents)
            case .pressed:
                self.gesture = .pressedStill
            case .released:
                if self.gesture == .pressedStill {
                    self.toggleMute()
                }
                self.gesture = .idle
        }
    }

    /// Called when the Dial disconnects, so an in-flight press never toggles mute.
    func reset() -> Void {
        self.gesture = .idle
    }

    // MARK: - Gestures

    private func rotate(by detents: Int) -> Void {
        let isFine = self.gesture != .idle
        // Turning while pressed suppresses the mute toggle on release, even if the volume cannot change.
        if isFine == true {
            self.gesture = .pressedTurned
        }
        self.step(by: detents, isFine: isFine)
    }

    private func step(by detents: Int, isFine: Bool) -> Void {
        guard detents != 0 else {
            return
        }
        guard let state = self.audio.state else {
            return
        }
        let settings = self.settings()
        if settings.excludedDeviceUIDs.contains(state.deviceUID) == true {
            return
        }
        // The device has no volume control and no software volume: buzz so the user knows nothing will change.
        if state.canSetVolume == false {
            self.hitEndStop()
            return
        }

        let signedDetents = settings.reverseDirection == true ? -detents : detents
        var step = Float32(settings.stepPercent) / 100
        if isFine == true {
            step /= Self.fineStepDivisor
        }

        if state.isMuted == true {
            self.audio.setMuted(false)
        }
        // Unmuting an emulated mute restores the remembered volume, so step from the state after unmuting.
        let current = self.audio.state?.volume ?? state.volume
        let target = VolumeStepper.volume(from: current, detents: signedDetents, step: step)
        self.apply(target: target, from: current, detents: signedDetents)

        if let adjusted = self.audio.state {
            self.onAdjusted?(adjusted)
        }
    }

    /// Writes the target, or buzzes when the Dial is already at the end of the range or the device undid the change.
    private func apply(target: Float32, from current: Float32, detents: Int) -> Void {
        let isAtEnd = detents > 0 ? current >= 1 : current <= 0
        if target == current {
            if isAtEnd == true {
                self.hitEndStop()
                return
            }
        }
        self.audio.setVolume(target)
        // Another device owns the output and undid an earlier change: buzz so the user knows nothing changed.
        if self.audio.state?.isInUseElsewhere == true {
            self.hitEndStop()
        }
    }

    private func toggleMute() -> Void {
        guard let state = self.audio.state else {
            return
        }
        guard self.settings().excludedDeviceUIDs.contains(state.deviceUID) == false else {
            return
        }
        let muted = state.isMuted == false
        self.audio.setMuted(muted)
        // A device with neither mute nor software volume refuses; then there is nothing to confirm.
        if let adjusted = self.audio.state {
            if adjusted.isMuted == muted {
                self.haptics.muteToggled(isMuted: muted)
                self.onAdjusted?(adjusted)
            }
        }
    }

    private func hitEndStop() -> Void {
        let now = self.now()
        defer { self.lastEndStopHit = now }
        if let lastEndStopHit = self.lastEndStopHit {
            if now - lastEndStopHit < Self.endStopQuietPeriod {
                return
            }
        }
        self.haptics.endStop()
    }
}
