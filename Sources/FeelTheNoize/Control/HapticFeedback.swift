/// The haptic patterns `DialController` asks for (Docs/DESIGN.md §7.1, §7.3); `DialDevice` conforms, the tests use a fake.
protocol HapticFeedback: AnyObject {
    func endStop() -> Void
    func muteToggled(isMuted: Bool) -> Void
}
