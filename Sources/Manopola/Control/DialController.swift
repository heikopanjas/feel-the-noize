protocol AudioControlling: AnyObject {
    var state: AudioState? { get }
    func setVolume(_ volume: Float32)
    func setMuted(_ muted: Bool)
}

protocol HapticFeedback: AnyObject {
    func endStop()
    func muteToggled(isMuted: Bool)
}

/// Gesture recognizer and the only place that decides what a Dial event does (docs/DESIGN.md §7.3).
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

    func handle(_ event: DialEvent) {
        switch event {
            case .rotated(let detents):
                rotate(by: detents)
            case .pressed:
                gesture = .pressedStill
            case .released:
                if gesture == .pressedStill {
                    toggleMute()
                }
                gesture = .idle
        }
    }

    /// Called when the Dial disconnects, so an in-flight press never toggles mute.
    func reset() {
        gesture = .idle
    }

    // MARK: - Gestures

    private func rotate(by detents: Int) {
        let isFine = gesture != .idle
        // Turning while pressed suppresses the mute toggle on release, even if the volume cannot change.
        if isFine {
            gesture = .pressedTurned
        }
        let settings = settings()
        guard detents != 0, let state = audio.state, !settings.excludedDeviceUIDs.contains(state.deviceUID) else { return }
        // The device has no volume control and no software volume: buzz so the user knows nothing will change.
        guard state.canSetVolume else {
            hitEndStop()
            return
        }

        let detents = settings.reverseDirection ? -detents : detents
        var step = Float32(settings.stepPercent) / 100
        if isFine {
            step /= Self.fineStepDivisor
        }

        if state.isMuted {
            audio.setMuted(false)
        }
        // Unmuting an emulated mute restores the remembered volume, so step from the state after unmuting.
        let current = audio.state?.volume ?? state.volume
        let target = VolumeStepper.volume(from: current, detents: detents, step: step)
        let isAtEnd = detents > 0 ? current >= 1 : current <= 0
        if target == current, isAtEnd {
            hitEndStop()
        }
        else {
            audio.setVolume(target)
            // Another device owns the output and undid an earlier change: buzz so the user knows nothing changed.
            if audio.state?.isInUseElsewhere == true {
                hitEndStop()
            }
        }

        if let adjusted = audio.state {
            onAdjusted?(adjusted)
        }
    }

    private func toggleMute() {
        guard let state = audio.state, !settings().excludedDeviceUIDs.contains(state.deviceUID) else { return }
        let muted = !state.isMuted
        audio.setMuted(muted)
        // A device with neither mute nor software volume refuses; then there is nothing to confirm.
        guard let adjusted = audio.state, adjusted.isMuted == muted else { return }
        haptics.muteToggled(isMuted: muted)
        onAdjusted?(adjusted)
    }

    private func hitEndStop() {
        let now = now()
        defer { lastEndStopHit = now }
        if let lastEndStopHit, now - lastEndStopHit < Self.endStopQuietPeriod {
            return
        }
        haptics.endStop()
    }
}
