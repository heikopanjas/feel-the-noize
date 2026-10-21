# Feel the Noize — Code Review and Fix Plan

**Reviewed:** 2026-10-21, commit `0351e66` on `main` (v1.2.0 build 3)
**Scope:** every file under `Sources/FeelTheNoize` (37 files, ~4 200 lines) and `Tests/FeelTheNoizeTests` (15 suites, ~1 200 lines), plus `project.yml`, `.swift-format`, `build.sh` and `Scripts/render-icon.swift`
**Lenses:** the `swift-coding-conventions`, `swift-concurrency-pro` and `swift-testing-pro` skills, with `AGENTS.md` and `Docs/DESIGN.md` §8, §11 and §12 as the project rules they apply to

---

## 1. Summary

The code base is in good shape where it matters most. The concurrency model described in DESIGN.md §8 is implemented as written: everything is main-actor isolated, the three IOKit C callbacks and every Core Audio listener block enter the actor through `MainActor.assumeIsolated` on the main run loop or main queue, the one off-actor piece (`SoftwareVolume`'s IO block) shares a single value through `Synchronization.Atomic` in a `nonisolated final class`, and there is no `@unchecked Sendable`, no lock, no `DispatchQueue.async`, no `Task.detached`, no continuation and no force unwrap or `try!` in the app target. The unit tests are idiomatic Swift Testing (structs, no `@Suite` noise, parameterized where it helps, `#require` for preconditions, private `UserDefaults` suites) and cover the pure logic well.

What the review found falls into three groups, in decreasing order of importance:

1. **A handful of genuine defects and fragilities** (§2): two implicitly unwrapped IOKit results that can trap, one timing-based unit test, a synchronous callback cycle `AudioOutput → AppDelegate → Settings → AudioOutput` that works today only because of ordering inside `publish(_:)`, five hand-rolled copies of the same "cancel, sleep, act" debounce task, and some dead API.
2. **A systematic gap between the code and the `swift-coding-conventions` skill** (§3). The code was written in idiomatic Swift before the skill was adopted on 2026-10-22 ("Existing code is not yet refactored to the Swift skill", UPDATES.md). The skill's special rules (`== true` / `== false` in conditions, explicit `self.` and `Self.`, explicit `return`, `-> Void`, one condition per `guard`/`if`, one pattern per `case`, guards only at the top of a function, no nested ternaries, one type per file) are violated on most lines of most files. None of this is a bug; all of it is mechanical, and it is by far the largest body of work in this plan.
3. **Testing improvements** (§4): the `#expect(!x)` form that defeats the macro's diagnostics, a slow timing test, logic in `AudioOutput` that is untested because its Core Audio access is a static hidden dependency, and a few cheap pure functions without tests.

The fix plan (§5) orders the work so that behavior-affecting fixes land first in small, individually verifiable commits, the mechanical convention sweep comes next file by file with the formatter and tests as the safety net, and the testability refactor of `AudioOutput` comes last because it is the only item that changes structure.

---

## 2. Correctness and Concurrency Findings

Ordered by impact. Each item names the rule, the location and the fix.

### 2.1 Implicitly unwrapped IOKit results can trap — `AccessoryBattery.swift:85`

**Rule:** `swift-coding-conventions` › Force Unwrapping; `.swift-format` `NeverUseImplicitlyUnwrappedOptionals`.

`IOPSCopyPowerSourcesList(_:)` returns `Unmanaged<CFArray>!`. Calling `.takeRetainedValue()` on it force-unwraps the implicitly unwrapped optional; a `nil` from powerd (observed on some machines during login/logout and after a powerd restart) would crash the app when the menu opens.

```swift
// Before
let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]

// After
guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return Readings() }
```

The same pattern does not occur elsewhere: `IOPSGetPowerSourceDescription` is already optional-chained on line 86.

### 2.2 `DialKeepAwakeTests.sendsAfterEachInterval` is a timing test — `DialKeepAwakeTests.swift:51-64`

**Rule:** `swift-concurrency-pro` › testing › Avoid timing-based tests; `swift-testing-pro` › async tests.

The test polls `sendCount` with `Task.sleep(for: .milliseconds(10))` in a loop under a two-second deadline. It passes today, but it is the one test in the suite that can fail under load, and it costs 20–40 ms per run for no reason.

Fix: give `DialKeepAwake` an injected clock and sleep through it, so the test drives time.

```swift
// DialKeepAwake.swift
init(interval: Duration = DialKeepAwake.interval, clock: any Clock<Duration> = ContinuousClock(), send: @escaping () -> Void)
…
task = Task { [weak self, interval, clock] in
    while Task.isCancelled == false {
        try? await clock.sleep(for: interval)
        …
```

In the test, a small `ManualClock: Clock` (fixture in the test target) whose `sleep` suspends on a continuation that `advance(by:)` resumes gives a deterministic "two intervals → two sends" assertion, and `confirmation(expectedCount: 2)` replaces the polling loop. (`ContinuousClock` is used in `UserActivity` and `DialController` too, but those already inject `now` as a closure and are tested deterministically; only the sleeping timer needs the clock.)

### 2.3 Synchronous callback re-entrancy around `AudioOutput.publish(_:)` — `AudioOutput.swift:277-296`, `AppDelegate.swift:57-67, 96-104`

**Rule:** `swift-concurrency-pro` › bug patterns (check-then-act; state mutated under a caller's feet). No actor hop is involved, but the same hazard exists synchronously.

The chain is: `AudioOutput.publish` → `onChange` → `AppDelegate` → `settings.rememberDevices` → `Settings.onChange` → `AppDelegate` → `audio.refreshSoftwareVolume()` → `AudioOutput.refresh()` → `publish` again, while the outer `publish` is still on the stack. It is correct today only because `state = newState` is assigned *before* `onChange?(newState)` is called, so the inner `publish` sees no difference and returns. A future edit that logs or compares after the callback, or that makes `rememberDevices` write more often, re-enters with stale locals (`newState`, `state`) and publishes twice or out of order.

Fix (small): break the cycle at its cheapest link. `rememberDevices` from `audio.onChange` is bookkeeping; it must not trigger a full settings refresh. Either give `Settings` a `remember…` path that does not call `onChange` (the software-volume level setter already has that precedent, `Settings.swift:200-205`), or have `AppDelegate` defer the remember with `Task { @MainActor in … }`. The first is simpler and keeps `onChange` meaning "a user-visible setting changed". Add a one-line reentrancy guard to `publish` (`isPublishing` flag with an `assert`) so a regression is caught in Debug.

### 2.4 Five copies of the same debounce task — `DialDevice.swift:90-95, 221-227`, `AudioOutput.swift:171-176`, `VolumeOverlay.swift:51-55`, `DialKeepAwake.swift:83-89`

**Rule:** `swift-concurrency-pro` › unstructured (a `Task {}` whose only job is "sleep then act" is a timer, not concurrency); AGENTS.md › DRY.

Each site hand-rolls: cancel the previous task, store a new `Task { try? await Task.sleep(for:); guard !Task.isCancelled, let self else { return }; … }`. The pattern is right (main-actor inheritance, cancellation checked after the sleep, weak self), but five copies invite the drift that `VolumeOverlay.scheduleFadeOut` already shows (it never clears `hideTask`, and checks cancellation but not `self` before the `self?.fadeOut()`). Extract one `MainActor`-isolated helper, e.g. `Support/DelayedAction.swift`:

```swift
/// A main-actor timer: `schedule` replaces any pending action, `cancel` drops it.
final class DelayedAction {
    private var task: Task<Void, Never>?
    var isPending: Bool { return self.task != nil }

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> Void {
        self.task?.cancel()
        self.task = Task {
            try? await Task.sleep(for: delay)
            guard Task.isCancelled == false else { return }
            self.task = nil
            action()
        }
    }

    func cancel() -> Void {
        self.task?.cancel()
        self.task = nil
    }
}
```

`DialKeepAwake`'s repeating loop stays a loop but uses the injected clock from 2.2. Net effect: about 30 lines deleted and one place to get the pattern right.

### 2.5 `AudioOutput.readState(of:)` is a read with side effects — `AudioOutput.swift:298-335`

**Rule:** `swift-concurrency-pro` › actors / bug patterns (functions that mutate state as part of a "read" are the ones that bite under re-entrancy, see 2.3).

`readState` starts or stops software volume (`reconcileSoftwareVolume`), feeds `volumeCheck.didRead`, and clears `emulatedMuteVolumes[uid]`. Together with 2.3 this means a nested `refresh()` can start/stop the tap or clear the emulated mute while an outer refresh is still computing. Move the three side effects into `refresh()` around a pure `readState`, so the order "reconcile → read → publish" is explicit in one place. Low risk; no behavior change intended.

### 2.6 Main-thread IPC on every device-list change while the menu is open — `StatusItemController.swift:191`

**Rule:** `swift-concurrency-pro` › bug patterns › blocking the main actor.

`AccessoryBattery.read()` talks to powerd synchronously (`IOPSCopyPowerSourcesByType` is an XPC round trip) and is called from `deviceListChanged()`, which fires on every `kAudioHardwarePropertyDevices` and default-device notification while the menu is open. Measured cost is small (single-digit milliseconds), and the menu is the only time it runs, so this is acceptable as designed (§7.12). Record the decision in DESIGN.md §7.12 and leave the code. If it ever shows up in a trace, the fix is `@concurrent` on a `nonisolated static func read()` plus an `await` in a `Task` that re-applies the readings.

### 2.7 Dead or test-only API

- `DialDevice.isConnected` (`DialDevice.swift:15-17`) — no callers. Remove.
- `AudioDeviceInfo.isControllable` (`AudioDeviceInfo.swift:61-64`) — used only by its own test. Either remove it with the test or use it in `DeviceSettingsViewController` where the "Yes/No/Emulated" labels are derived (`muteLabel`). Removing is in keeping with "no speculative abstractions" (AGENTS.md).
- `VolumeWriteCheck.isPending` is used by `finish()` and the tests — keep.
- `Scripts/render-icon.swift` uses `!` and `try!` nine times. It is a build-time script outside `swift-format lint`'s paths, so it is exempt from `.swift-format`, but not from the skill. Low priority; convert to `guard … else { exit(1) }` when the script is next touched (Phase 4).

### 2.8 Smaller items

- `DialDevice.swift:131` is 149 columns, over the `.swift-format` `lineLength` of 147 (the skill's 187 is not what the linter enforces). Wrap the interpolation.
- `MenuDeviceRow.mouseUp` (`MenuDeviceRow.swift:80`) does not check `item.isEnabled` while `MenuMuteRow.mouseUp` (`MenuMuteRow.swift:76`) does. Device items are always enabled today; add the check for symmetry so a future disabled row cannot be clicked.
- `VolumeOverlay.scheduleFadeOut` keeps `hideTask` after it fires. Harmless; goes away with 2.4.
- `Settings.init` calls `defaults.register(defaults:)`. The registration domain is process-wide, so a test's private suite registers the same defaults into `.standard` as well. Harmless in the test host (no `AppDelegate`), but worth one comment in `SettingsTests.withSettings`, because it is why `defaultsMatchTheDesign` cannot distinguish "registered on this suite" from "registered anywhere".
- `main.swift:10` detects the test host through `XCTestConfigurationFilePath`. Swift Testing under `xcodebuild test` still runs inside the XCTest harness and sets it, confirmed by the hosted test runs so far; note the dependency in DESIGN.md §11.1 so a future Xcode change that drops the variable is diagnosed quickly (symptom: a test run seizes the Dial).

### 2.9 Confirmed sound (no action)

Listed so the next reviewer does not re-derive them.

- IOKit callbacks (`DialDevice.swift:388-424`): `Unmanaged.passUnretained(self)` is safe because `closeManager()` unregisters every callback before the manager is released and `DialDevice` lives for the process; the `nonisolated(unsafe) let device = device` hand-over is the single permitted opt-out and is commented as AGENTS.md requires; the report bytes are copied out before entering the actor.
- Core Audio listener blocks are registered and removed with the *same* `@convention(block)` instance (`CoreAudioProperty.ListenerBlock`), so removal works; all are on `.main`.
- `Gain` (`SoftwareVolume.swift:169-187`): two independent single-word atomics with `.relaxed` ordering are correct here because no other memory is published through them; the IO block allocates nothing, takes no lock and does not log; `AudioDeviceStop` and `AudioDeviceDestroyIOProcID` synchronize with the IO thread before the block is released.
- Every `Task {}` inherits main-actor isolation; every one checks `Task.isCancelled` after its sleep; none swallows an error it should surface (`try? await Task.sleep` is the only `try?`).
- `NSWorkspace` notification observers use `queue: .main` and `MainActor.assumeIsolated`, matching DESIGN.md §8; `for await` over `notifications(named:)` would be the structured alternative but adds nothing here.
- `UserActivity`'s convenience init captures two `var` assertion IDs in a closure stored on a main-actor class — single-threaded by isolation, fine.
- `InputDeviceKeeper.enforce()` cannot loop: the write it makes re-fires the listener, which finds `currentID == keptID` and returns.
- No actor re-entrancy across `await` exists, because no isolated method awaits anything except `Task.sleep` inside the debounce tasks.

---

## 3. Coding Convention Findings (`swift-coding-conventions`)

These are style rules, not bugs, but AGENTS.md makes the skill binding ("the skill wins where they disagree"). The table gives the rule, a count from a grep over `Sources` (tests are listed separately in §4), and representative locations. Counts are approximate and meant to size the work.

| # | Rule | Approx. occurrences | Examples |
|---|---|---|---|
| C1 | Boolean literals in conditions (`if x == true`, `while x == false`); no `!x` | ~40 negations plus most positive conditions | `DialController.swift:67` `if isFine {`; `DialDevice.swift:196` `if !hasRequestedAccess`; `DialKeepAwake.swift:84` `while !Task.isCancelled`; `main.swift:11` `if !isTestHost` |
| C2 | Explicit `self.` for instance members, `Self.` for statics | nearly every member access (44 `self.` in ~4 200 lines) | `AppDelegate.swift:30` `controller = DialController(…)`; `VolumeStepper.swift:12` `epsilon`; `DialReport.swift:28` `inputPayloadLength`; `KnobIcon.swift:32` `startDegrees` |
| C3 | No implicit returns (functions, computed properties, multi-line closures) | ~56 single-expression bodies plus multi-line closures | `Settings.swift:91`, `LoginItem.swift:6`, `CoreAudioError.swift:9`; multi-line closure `AccessoryBattery.swift:63-71` (`map { cell in switch … }`) |
| C4 | Explicit `-> Void` on non-returning functions | ~150 functions | every `func start()`, `func stop()`, `@objc` action, delegate method |
| C5 | One condition per `guard` / `if`; no comma chains | 47 | `DialController.swift:71`; `AudioOutput.swift:279`; `AccessoryBattery.swift:102-105`; `DeviceSettingsViewController.swift:215` |
| C6 | `guard` only at the top of a function, before other code | ~30 | `DialController.swift:71,73` (after `let settings`); `AudioOutput.swift:100` (`guard !state.isInUseElsewhere`); `UserActivity.swift:54`; `StatusItemController.swift:75` |
| C7 | One pattern per `case` | 6 | `AudioDeviceInfo.swift:20,27`; `DeviceIcon.swift:42,47`; `DialDevice.swift:249`; `AccessoryBattery.swift:22` |
| C8 | No nested ternary | 2 | `MenuMuteRow.swift:58,63` |
| C9 | One primary type per file, file name matches | 5 files | `DialReport.swift` (`HapticWaveform`, `DialInputReport`); `DialController.swift` (`AudioControlling`, `HapticFeedback`); `Settings.swift` (`ControlSettings`); `AudioOutput.swift` (`SoftwareVolumePreferences`); `SoftwareVolume.swift` (`Gain`) and `VolumeOverlay.swift` (`LevelBar`) hold private helpers, which the skill allows "sparingly" |
| C10 | Explicit nil checks when the binding is unused | 0 | already compliant (`main.swift:10`, `Settings.swift:155`) |
| C11 | Force unwrap / `try!` | 0 in `Sources` and `Tests`; 9 in `Scripts/render-icon.swift` | see 2.7 |
| C12 | `else` / `catch` on their own line | 0 | compliant; enforced by `.swift-format` |
| C13 | Return empty collections, never `nil`, for "no data" | 0 | compliant |
| C14 | Line length | 1 line over the linter's 147 | `DialDevice.swift:131` |
| C15 | Access control: `private` by default, explicit otherwise | mostly compliant | a few internal members only tests use (`AudioDeviceInfo.isControllable`), see 2.7 |

Notes on how to apply them:

- **C1 and C3 interact with `.swift-format`.** The config already has `OmitExplicitReturns: false`, `UseExplicitNilCheckInConditions: false` and `NoVoidReturnOnFunctionSignature: false`, so the formatter will not undo explicit `return`, `== true` or `-> Void`. `UseEarlyExits: false` means it will not push `if` back into `guard` either. No `.swift-format` change is needed; run `./build.sh format lint` after every file.
- **C2 is the largest diff by far** and touches every closure. Do it file by file, in the same commit as C1/C3/C4 for that file, so each file is converted once and reviewed once. Inside closures that already bind `let self` (the debounce tasks), `self.` becomes mandatory; the compiler will flag nothing either way, so this is a review item, not a build item.
- **C5 and C6 change control flow shape**, not meaning, but they are the two rules most likely to introduce a mistake when applied by hand (a dropped early return, an inverted condition). Convert each comma chain into nested `if let` / `if` blocks, and each mid-function `guard` into an `if … { return }` or restructure so the guard moves to the top. Keep `guard` where it is already first in the function. Run the full test suite after each file; `DialController`, `AudioOutput`, `VolumeWriteCheck` and `Settings` have the coverage to catch a slip; the UI files do not, so for those use the manual checklist items in DESIGN.md §11.2 that exercise the touched code (items 5–8 for the menu, 9 for settings).
- **C7:** multi-pattern cases become one `case` per line that assign the same value; for `Transport.init` that is two extra lines per pair. The `default:` stays.
- **C9:** new files `Dial/HapticWaveform.swift`, `Dial/DialInputReport.swift`, `Control/AudioControlling.swift`, `Control/HapticFeedback.swift`, `Support/ControlSettings.swift`, `Audio/SoftwareVolumePreferences.swift`. `Gain` and `LevelBar` can stay as private helpers; if they move, `Gain` must stay `nonisolated` (`Audio/SoftwareGainState.swift`, say — `SoftwareGain` is taken). Update DESIGN.md §12, which currently states the co-locations as intended, and `project.yml` needs no change (sources are by path), but run `./build.sh gen`.
- **C8:** replace with an `if` / `else if` / `else` that assigns a `let`.

---

## 4. Test Findings (`swift-testing-pro`, `swift-concurrency-pro` › testing)

### 4.1 `#expect(!x)` defeats the macro — 15 occurrences

**Rule:** core rules › never negate with `!` inside `#expect` / `#require`.

`DialKeepAwakeTests.swift:8,11,17,23,27,35`, `VolumeWriteCheckTests.swift:11,12,43,67`, `SettingsTests.swift:61,96,101`, `DeviceIconTests.swift:65`, `BatteryIconTests.swift:31`. On failure these print "Expectation failed: !check.isRejected" with no captured value. Replace with `== false`. This also satisfies C1 for the test target.

### 4.2 Timing-based test

`DialKeepAwakeTests.sendsAfterEachInterval` — see 2.2.

### 4.3 Hidden dependency makes `AudioOutput` untestable

**Rule:** writing better tests › expose hidden dependencies.

`AudioOutput` carries real logic — emulated mute with volume memory, the volume-tolerance publish, software-volume reconciliation with a failed-device latch, the one-second probe while another device owns the output — and none of it has a unit test, because every Core Audio call goes through the static `CoreAudioProperty` enum. DESIGN.md §11.1 calls `AudioOutput` a "thin adapter", which was true in M2 and is not true after M6–M8.

Fix: introduce a protocol for the handful of device-level calls `AudioOutput` makes (`readString`, `isSettable`, `readVolume`, `writeVolume`, `readMute`, `writeMute`, `readDefaultDevice`, add/remove listener), with `CoreAudioProperty` as the production conformance and a `FakeCoreAudio` in the test target that records writes and lets the test fire listener callbacks. Inject it through `AudioOutput.init(coreAudio: any CoreAudioAccess = CoreAudioProperty.shared)` so `AppDelegate` does not change. `SoftwareVolume` gets the same treatment one level down only if the tests need it; initially it can be injected as a protocol with a no-op fake. The `AudioControlling` protocol that `DialController` already depends on shows the pattern works in this code base.

Tests that this unlocks (each a bug class that has already shipped or been debugged by hand per UPDATES.md): emulated mute round trip and "non-zero volume set elsewhere clears the emulated mute"; publish tolerance (`0.58` read back as `0.58000004` does not fire `onChange`); software volume starts for an opted-in device without volume control and is not retried after a failure until `refreshSoftwareVolume()`; probe rate limiting while `isInUseElsewhere`; `stop()` detaches listeners.

### 4.4 Cheap pure functions without tests

- `VolumePresentation.percent(_:)` and `accessibilityDescription(for:)` (`VolumePresentation.swift:19-29`) — four branches, string output that the menu bar and VoiceOver depend on. One parameterized test.
- `CoreAudioError.description` / `fourCharCode` (`CoreAudioError.swift:8-18`) — `'who?'` vs numeric fallback. One parameterized test.
- `DialReport.hapticConfiguration` with a negative detent count (clamps to 0) — one argument added to the existing clamp test.

### 4.5 Smaller items

- `KnobIconTests.drawsInk` loops over `isMuted in [false, true]` inside one test. Parameterize over `zip`/product of styles and mute states so a failure names the case.
- The `abs(a - b) < tolerance` comparisons (`DialControllerTests`, `VolumeStepperTests`, `SoftwareGainTests`, `BatteryIconTests`, `KnobIconTests`) could share one helper `expectClose(_:_:tolerance:sourceLocation: #_sourceLocation)` so failures print both values and point at the calling line. Optional; no external package (swift-numerics is out by the no-dependency rule).
- Tests are flat in one folder while production code is grouped (`Audio/`, `Dial/`, …). The skill says not to reorganize existing tests without permission; listed here as a question for the developer, not as a task.
- `KeepChoicesTests` tests a static on `DeviceSettingsViewController`. Fine, but when 4.3 lands, `keepChoices` is a candidate to move to a small `Support/KeepChoices.swift` enum so the view controller file has no test-reachable logic.
- The test target inherits `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` from `settings.base` in `project.yml`, which is why no test needs `@MainActor` and why closures capturing `var sendCount` compile. Add one sentence to DESIGN.md §11.1 so nobody "fixes" it by adding annotations.

---

## 5. Fix Plan

Four phases. Each milestone is a commit (or a few) that leaves `./build.sh lint test` green and the manual checklist items named in it passing. Version bumps follow the `semantic-versioning` skill: behavior fixes are PATCH, the testability refactor is PATCH (no user-visible change), the convention sweep is PATCH; nothing here is MINOR. Every milestone that changes a design fact updates DESIGN.md in the same commit, and every convention or structure decision gets an UPDATES.md entry.

### Phase 1 — Defects and fragilities (behavior-affecting, small, first)

| Milestone | Work | Exit criterion |
|---|---|---|
| **1.1 Crash guard** | 2.1: optional-chain `IOPSCopyPowerSourcesList` in `AccessoryBattery.read()`. | `AccessoryBatteryTests` green; menu still shows AirPods and Dial batteries (checklist 16). |
| **1.2 Deterministic keep-awake test** | 2.2: inject `any Clock<Duration>` into `DialKeepAwake`; add `ManualClock` test fixture; rewrite `sendsAfterEachInterval` with `confirmation(expectedCount: 2)` and no sleeps; convert the six `#expect(!…)` in that file. | Test runs in < 5 ms, passes 100 consecutive runs (`for i in {1..100}; do ./build.sh test; done` or Xcode's repeat-until-failure). |
| **1.3 Break the publish cycle** | 2.3 and 2.5: `Settings.rememberDevices`/`rememberInputDevices` stop calling `onChange` (document in `Settings` doc comment and DESIGN.md §7.7; the Devices tab already reloads from its own device list, verify it still lists newly seen devices); move side effects out of `AudioOutput.readState` into `refresh()`; add `assert(isPublishing == false)` guard in `publish`. Adjust `SettingsTests.rememberDevicesMergesAndWritesOnlyWhatIsNew` and `rememberInputDevicesIsSeparateFromOutputs`, which currently count `onChange` calls. | Tests green; checklist 5–9 and 14–17 pass; a Debug run with `log stream` shows one "Audio state" line per real change when switching outputs. |
| **1.4 One delayed-action helper** | 2.4: add `Support/DelayedAction.swift`; replace the four one-shot tasks (`DialDevice.buzzStopTask`, `DialDevice.rebuildTask`, `AudioOutput.volumeCheckTask`, `VolumeOverlay.hideTask`); add `DelayedActionTests` using the clock from 1.2 if the helper takes one (recommended, so the end-stop buzz cut and the overlay fade are testable). | Tests green; checklist 3 (end stop buzz is a short pulse), 10 (overlay fades), sleep/wake rebuild (edge case list §10) pass. |
| **1.5 Dead code and small items** | 2.7 and 2.8: remove `DialDevice.isConnected` and `AudioDeviceInfo.isControllable` (+ its test); wrap `DialDevice.swift:131`; add `isEnabled` check to `MenuDeviceRow.mouseUp`; comments for the registration-domain and `XCTestConfigurationFilePath` facts; DESIGN.md §7.12 note on the synchronous battery read. | `./build.sh lint` clean; DESIGN.md §11.1 and §12 updated. |

Phase 1 touches `AccessoryBattery`, `DialKeepAwake`, `Settings`, `AudioOutput`, `AppDelegate`, `DialDevice`, `VolumeOverlay`, `MenuDeviceRow` and three test files. Estimated size: ~250 lines changed. Do it before Phase 2 so the convention sweep does not have to be redone on these files.

### Phase 2 — Test hygiene and coverage of pure code

| Milestone | Work | Exit criterion |
|---|---|---|
| **2.1 Macro-friendly expectations** | 4.1: remaining `#expect(!…)` → `== false` in `VolumeWriteCheckTests`, `SettingsTests`, `DeviceIconTests`, `BatteryIconTests`. | No `#expect(!` in `Tests` (`grep` in CI step or a lint note in AGENTS.md). |
| **2.2 New pure tests** | 4.4: `VolumePresentationTests`, `CoreAudioErrorTests`, negative-detent argument in `DialReportTests`. | DESIGN.md §11.1 table lists the two suites. |
| **2.3 Parameterize and helper** | 4.5: split `KnobIconTests.drawsInk`; optional `expectClose` helper with `#_sourceLocation`. | Failures in image tests name style and mute state. |

Small and independent; can be interleaved with Phase 1 or done in one commit.

### Phase 3 — Convention sweep (`swift-coding-conventions`)

One commit per file or per small group of related files, each applying **C1–C8 and C14** to that file in full, followed by `./build.sh format lint test`. Doing all rules per file (rather than one rule across all files) means each line is rewritten once and each diff is reviewable against one file's logic. Order from most-tested to least-tested so the habit forms on files where a slip is caught:

| Milestone | Files | Safety net |
|---|---|---|
| **3.1 Pure logic** | `VolumeStepper`, `DialReport`, `VolumeWriteCheck`, `SoftwareGain`, `AccessoryBattery`, `AudioDeviceInfo`, `CoreAudioError`, `KnobIcon`, `DeviceIcon`, `BatteryIcon`, `VolumePresentation` | unit tests |
| **3.2 Control and support** | `DialController`, `Settings`, `UserActivity`, `DialKeepAwake`, `LoginItem`, `Log`, `DelayedAction` | unit tests |
| **3.3 Audio adapters** | `AudioOutput`, `AudioDeviceList`, `InputDeviceKeeper`, `CoreAudioProperty`, `SoftwareVolume`, `AudioState` | Phase 4 tests if done first (see below), else checklist 1–4, 14–17 and the software-volume items |
| **3.4 Dial** | `DialDevice`, `DialEvent`, `DialConnection` | checklist 1–4, 11–13, sleep/wake |
| **3.5 UI and app** | `StatusItemController`, `VolumeOverlay`, `SettingsWindowController`, `GeneralSettingsViewController`, `DeviceSettingsViewController`, `VolumeSlider`, `MenuInfoRow`, `MenuMuteRow`, `MenuDeviceRow`, `AppDelegate`, `main` | checklist 5–10 |
| **3.6 File split (C9)** | new files for `HapticWaveform`, `DialInputReport`, `AudioControlling`, `HapticFeedback`, `ControlSettings`, `SoftwareVolumePreferences`; DESIGN.md §12 tree and the sentence under it; `./build.sh gen` | build green; §12 matches `find Sources -name '*.swift'` |
| **3.7 Tests (C1–C5)** | apply the same rules to `Tests/FeelTheNoizeTests` (mostly `== false`, explicit `return` in multi-line closures, `self.`/`Self.` in fixtures) | lint green |
| **3.8 Script** | `Scripts/render-icon.swift`: replace `!`/`try!` with `guard … else { exit(1) }`; `./build.sh icon` reproduces byte-identical PNGs | `git status` shows no asset change |

Per-file checklist for the sweep (paste into the commit body or PR description):

- [ ] every `if`/`guard`/`while` on a Bool compares `== true` / `== false`; no `!x`
- [ ] every instance member access reads `self.`, every static `Self.` (or the concrete type from outside it)
- [ ] every function, computed property and multi-line value closure has an explicit `return`
- [ ] every non-returning function declares `-> Void`
- [ ] no comma-chained conditions; `guard` only before any other statement in the function
- [ ] one pattern per `case`; no nested ternary
- [ ] `./build.sh format lint test` green; manual checklist items named in the milestone pass

Mechanical aids: the `== true` / `== false`, `-> Void` and implicit-return rewrites are regular enough that a one-off script (or careful editor regex) handles 80 % of them; `self.` qualification is not regex-safe (local shadowing, closure parameters, key paths) and must be done by reading each function. Budget the sweep at roughly the size of the code base itself in diff lines.

Decision needed before 3.1 starts (ask the developer): C6 (`guard` only at the top of a function) is the one rule whose literal application makes some functions worse (`DialController.rotate`, `AudioOutput.setVolume`). The options are (a) apply literally, converting mid-function guards to `if … { return }`, (b) record an exception in AGENTS.md for guards that follow only `let` bindings. The plan assumes (a) because AGENTS.md says the skill wins; (b) needs an UPDATES.md entry.

### Phase 4 — Testability of `AudioOutput`

| Milestone | Work | Exit criterion |
|---|---|---|
| **4.1 Protocol seam** | 4.3: `Audio/CoreAudioAccess.swift` protocol covering the calls `AudioOutput` makes; `CoreAudioProperty` conforms (an instance, e.g. `static let shared`, or a `struct CoreAudioHAL: CoreAudioAccess` whose methods forward to the existing statics); `AudioOutput.init(coreAudio:)` with the production default; no change in `AppDelegate`. | Build green; app behavior unchanged (checklist 1–4, 14–17). |
| **4.2 Fake and tests** | `Tests/…/FakeCoreAudio.swift` recording writes and exposing `fireListener(address:)`; `AudioOutputTests` for the five behaviors listed in 4.3. | Tests green; DESIGN.md §11.1 table and the "thin adapters" sentence updated. |
| **4.3 (optional) `AudioDeviceList` and `InputDeviceKeeper`** | Same seam; tests for "hidden and private aggregate devices filtered", "default UIDs read", "enforce switches back once and not in a loop". | Tests green. |

Phase 4 is last because it restructures the audio layer; doing it after the convention sweep means the new files are written to the skill from the start. If the developer prefers, 4.1–4.2 can precede 3.3 so the `AudioOutput` convention rewrite is covered by unit tests instead of the manual checklist — that is the safer order and costs nothing but sequencing.

---

## 6. What Not to Change

- The main-actor-everything model, `MainActor.assumeIsolated` in callbacks and the `nonisolated(unsafe) let` hand-over of `IOHIDDevice` (DESIGN.md §8). The `swift-concurrency-pro` skill's general preference for structured concurrency and `for await` streams does not apply: there is no concurrency to structure, and the callback style is the project's documented choice.
- The `Gain` atomics and the IO block. Any "improvement" that introduces an actor, a lock or an allocation on the IO thread is a regression.
- `.swift-format`. It is already configured not to fight the skill (`OmitExplicitReturns`, `NoVoidReturnOnFunctionSignature`, `UseExplicitNilCheckInConditions` all off; `lineBreakBeforeControlFlowKeywords` on).
- The `dlsym` lookup in `AccessoryBattery` — permitted and documented per AGENTS.md; only its nil-handling changes (2.1).
- `UserActivity`'s `IOPMAssertion` dance and the measured timings; the tests already pin the rate limiting.

---

## 7. Appendix — Counts Used to Size the Plan

Grep over `Sources/FeelTheNoize` at `0351e66`:

| Measure | Value |
|---|---|
| Swift files / lines | 37 / 4 180 (`Sources`), 15 / 1 228 (`Tests`) |
| `!bool` negations in conditions | 40 (`Sources`), 15 (`Tests`, all inside `#expect`) |
| Comma-chained `if` / `guard` | 47 |
| Functions without `-> Void` | ~150 |
| Explicit `self.` | 44 |
| Single-expression bodies with implicit return | ~56 (+ multi-line closures) |
| Multi-pattern `case` | 6 |
| Nested ternary | 2 |
| Files with more than one top-level type | 5 (+2 with private helpers) |
| Lines > 147 columns | 1 |
| Force unwrap / `try!` / `@unchecked Sendable` / `Task.detached` / `DispatchQueue` / continuations | 0 in `Sources` and `Tests` |
| `Task {}` sites | 5 (all main-actor, all cancellation-checked) |
| `MainActor.assumeIsolated` sites | 10 (3 C callbacks, 4 Core Audio listeners, 2 NSWorkspace observers, 1 animation completion) |
