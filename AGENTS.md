# Project Instructions for AI Coding Agents

**Last updated:** 2026-10-19

## Mission Statement

Manopola (working name) is a macOS menu bar app that turns a Microsoft Surface Dial into a hardware volume knob: turning changes the volume of the default output device, pressing toggles mute, and the Dial's haptic motor clicks on every step.

The full specification is `docs/DESIGN.md`. Read it before writing code; it is the source of truth for architecture, HID report layouts, Core Audio usage, gestures and milestones.

## Technology Stack

- **Language:** Swift 6 language mode, default actor isolation `MainActor`
- **UI:** AppKit only (NSStatusItem, NSMenu, NSPanel, NSWindowController); no SwiftUI, no storyboards or nibs
- **Frameworks:** IOKit HID, CoreAudio, AudioToolbox, ServiceManagement, OSLog
- **Dependencies:** none (no Swift packages)
- **Platform:** macOS 15.4+
- **Build System:** XcodeGen (`project.yml`); the `.xcodeproj` is generated and not committed
- **Tests:** Swift Testing, target `ManopolaTests` in `Tests/ManopolaTests`, hosted in the app
- **Distribution:** Developer ID, notarized, not sandboxed, Hardened Runtime
- **License:** MIT

## Primary Instructions

- Avoid making assumptions. If you need additional context, ask for it and be specific about what is missing.
- Always name the file a piece of code belongs to.
- Follow the module layout in `docs/DESIGN.md` §12; one primary type per file, file name matches the type.
- Write only the code needed for the current milestone (`docs/DESIGN.md` §13). No speculative abstractions.
- Hardware facts that M1 verifies (§14) must be written back into `docs/DESIGN.md` when confirmed or corrected.

### Working Together

This file (`AGENTS.md`) is the primary instructions file for AI coding assistants working on this project. Agent-specific files (`CLAUDE.md`, `.github/copilot-instructions.md`) reference it.

### Update Protocol (CRITICAL)

Update this file whenever a technology, convention, directory structure, architecture or build decision is made, in the same response:

- maintain the "Last updated" timestamp at the top,
- add the decision to the relevant section,
- add an entry with date, description and reasoning to "Recent Updates & Decisions" at the bottom.

Architecture and behavior changes go into `docs/DESIGN.md` as well.

## Build Commands

The `Makefile` wraps the commands below; prefer `make build`, `make test`, `make lint`, `make diagrams`, `make icon`, `make release` and `make notarize`.

```sh
# Generate the Xcode project (after every change to project.yml or added/removed files)
xcodegen generate

# Build (debug)
xcodebuild -scheme Manopola -configuration Debug build | xcbeautify

# Test
xcodebuild -scheme Manopola test | xcbeautify

# Format and lint (swift-format ships with the Xcode toolchain)
xcrun swift-format format --in-place --recursive Sources Tests
xcrun swift-format lint --recursive Sources Tests

# Watch the app log, including raw HID reports
log stream --style compact --level debug --predicate 'subsystem == "com.panjas.Manopola"'

# Render diagrams
plantuml -tsvg docs/diagrams/*.puml
```

## Coding Conventions

- Formatting is defined by `.swift-format` (4 spaces, 147 columns) and `.editorconfig`.
- No force unwrapping, no force `try`, no implicitly unwrapped optionals.
- `private` by default; widen access only when needed.
- Imports ordered alphabetically.
- Comments explain why, not what. `///` for documentation comments, `// MARK: -` to group sections.
- Concurrency: everything is main-actor isolated. IOKit and Core Audio callbacks run on the main run loop / main queue and enter the actor with `MainActor.assumeIsolated`. No `@unchecked Sendable`, no locks. The single exception to main-actor isolation is the software volume IO block (`SoftwareVolume`), which runs on the HAL IO thread and shares only the gain through `Synchronization.Atomic` in a `nonisolated final class`; it must not allocate, lock or log. C callbacks resolve the main-actor owner from the context pointer before entering the actor; a non-Sendable CF argument such as `IOHIDDevice` is handed over through a commented `nonisolated(unsafe) let`, the only permitted unsafe opt-out.
- Logging via `os.Logger(subsystem: "com.panjas.Manopola", category:)` with categories `dial`, `audio`, `control`, `ui`, defined in `Support/Log.swift`. A category is added with the milestone that first uses it.
- Undeclared system APIs are allowed only where their failure degrades a non-essential feature, looked up with `dlsym` and recorded in `docs/DESIGN.md`. Currently only `IOPSCopyPowerSourcesByType` for battery levels (planned in M7).
- Milestone spike code that must not ship is wrapped in `#if DEBUG` and named in `docs/DESIGN.md` §13 together with the milestone that removes it.
- Diagrams are PlantUML in `docs/diagrams/`, styled with the shared `visio2003.iuml` include.

## Commit Protocol (CRITICAL)

- **NEVER commit automatically** — always wait for explicit confirmation.
- When asked to commit: stage the changes, write a conventional commit message, commit.
- Subject line max 50 characters, imperative mood, no trailing period; body wrapped at 72 characters; total under 500 characters.
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `build`, `ci`, `perf`.
- No special shell characters, quotes, emoji or unicode in commit messages.

## Versioning

Semantic versioning via `MARKETING_VERSION` in `project.yml`; bump `CURRENT_PROJECT_VERSION` for every distributed build. Include version changes in the commit that causes them.

---

## Recent Updates & Decisions

### 2026-10-17

- Project created: XcodeGen spec, AppKit entry point without storyboard, status item skeleton.
- Decided AppKit over SwiftUI, no third-party dependencies, no sandbox, Core Audio instead of synthetic media keys.
- Reason: smallest possible menu bar utility; raw HID access to the Dial; no Accessibility permission needed.
- Software design document written: `docs/DESIGN.md`.

### 2026-10-18

- M1 implemented: `Log`, `DialEvent`, `DialReport`, `DialDevice`, AppDelegate wiring that logs Dial events, Input Monitoring fallback from DESIGN §9.2.
- Added the debug-only `DialDiagnosticsMenu` to switch detents and haptics and to play every haptic pattern. Reason: answering R3 and R4 on hardware needs these controls before the Settings window exists in M4.
- Allowed `nonisolated(unsafe) let` for non-Sendable CF arguments in IOKit callbacks. Reason: Swift 6 region checking rejects passing `IOHIDDevice` into `MainActor.assumeIsolated`, and the callback provably runs on the main thread.
- swift-format is run through `xcrun`, since Xcode bundles it. Added the `log stream` command for M1 hardware checks.
- M2 implemented: `AudioState`, `CoreAudioError`, `AudioOutput`, `VolumeStepper`, test target `ManopolaTests` with `DialReportTests` and `VolumeStepperTests`.
- Virtual main volume is read and written with `AudioObjectGetPropertyData` and `AudioObjectSetPropertyData`, not the AudioHardwareService API from the original design. Reason: AudioHardwareService is deprecated since macOS 10.11, and the HAL serves the property directly; verified against AirPods.
- The app does not install `AppDelegate` when hosting unit tests. Reason: a test run must not seize the Dial or touch the audio device.
- `DialDiagnosticsMenu` renamed to `DiagnosticsMenu` and given volume and mute actions. Reason: M2 needs a manual way to set volume and mute before `DialController` exists.
- Diagrams rendered to SVG and aligned with the M1 and M2 code: `playHaptic` signature, `onAccessDenied`, `VolumeStepper.volume(from:detents:step:)`, `AudioState.deviceID`, AudioObject volume calls, seize with shared fallback. Reason: DESIGN.md embeds the SVGs, so they must match the implementation.
- M3 implemented: `DialController` with `AudioControlling` and `HapticFeedback`, `ControlSettings`, `DialControllerTests`, AppDelegate wiring. `DialDevice` and `AudioOutput` adopt the protocols. Until M4, AppDelegate passes the default settings of 2 percent step and no reversal.
- End-stop buzz is debounced instead of rate-limited: it plays only when the previous end-stop detent is at least 300 ms old. Reason: the gesture table and checklist item 5 conflicted; a continuous spin now buzzes once and still satisfies both.
- First hardware session with the Surface Dial: BLE transport, seized open without an Input Monitoring prompt, ±1 delta per detent at 36 detents, haptic configuration accepted. Written into DESIGN.md §2.1 and §14 as required for M1 facts. R1, R4 and the 18 and 72 detent checks remain open.
- AudioOutput ignores volume read-back noise below 0.0001 on the same device. Reason: Core Audio returned 0.58 as 0.58000004, which fired about 25 duplicate change notifications in the first hardware session.
- M4 implemented: `Settings`, `LoginItem`, `StatusItemController`, `VolumeOverlay`, `VolumePresentation`, `SettingsWindowController`, `SettingsViewController`, `SettingsTests`, full AppDelegate wiring. `DiagnosticsMenu` removed as planned; the Settings window now switches detents and haptics.
- Added `VolumePresentation` for symbol choice and percentage and accessibility text. Reason: the status item and the overlay need identical rules.
- Menu Mute bypasses `DialController`, so it gives no haptics and no overlay. Reason: those belong to Dial gestures.
- `LoginItem` is a caseless enum; launch at login shows on while approval is pending. Reason: the app is registered in that state, and the approval hint explains the rest.
- M5 prepared: version 1.0.0, app icon rendered by `scripts/render-icon.swift`, README rewritten for users, `Makefile` modeled on the Voltaic one with `release` and `notarize` split. Reason: notarization uploads to Apple with stored credentials, so it is a separate step the developer runs.
- Release builds pass `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` and `make release` fails if `get-task-allow` is present. Reason: the first signed build carried that entitlement, which the notary service rejects.
- Checklist item 13 measured: no measurable CPU time over 60 s while idle.
- Release build verified running on its own. A second instance cannot open the seized Dial in either mode but still reports it connected; recorded in DESIGN.md §14 R2, fix not yet decided.
- Fixed: a Dial held exclusively by another process was reported connected. `DialDevice` now adopts a Dial only after it accepts the haptic configuration and publishes a three-state `DialConnection` with `inUseElsewhere`. Retries run when the menu opens or the app becomes active, since IOKit gives no release notification and polling is ruled out. The status menu shows In Use by Another App.
- Connection fix verified on hardware with two instances: in use elsewhere detected, retry on menu open connected after the holder quit.
- Debug capture on hardware answered R1 (9 bytes with report ID) and R4 (clicks with repeat work; Buzz Continuous never stops on its own, end stop fix pending). Also found a vendor report ID 50 on every press and the touch bit set in normal use; written into DESIGN.md §7.1 and §14.
- End stop is a 100 ms buzz followed by a Stop trigger, chosen by the developer over the three-click fallback. Reason: Buzz Continuous never ends on its own, and the sluggish click feel of the Dial makes rapid click patterns hard to distinguish. Verified on hardware: the buzz ends by itself.
- Devices settings tab: the window became a toolbar-style `NSTabViewController` with General and Devices. Devices lists connected and remembered outputs with connection, volume control and mute, and lets the user select the devices the Dial works with. Decided with the developer: unselected default output means the Dial does nothing, new devices are selected, remembered devices stay listed, devices without volume are selectable for mute only. Stored as `excludedOutputDevices` and `knownOutputDevices`.
- Core Audio property helpers moved from `AudioOutput` into `CoreAudioProperty`, shared with the new `AudioDeviceList`. Reason: both read the same properties; no behavior change.
- `SettingsViewController` renamed to `GeneralSettingsViewController`. The General tab sets `preferredContentSize` to its fitting size, because the tab view otherwise stretches the grid.
- Devices tab verified on hardware by the developer: grid rows, excluding and re-including the current output, AirPods disconnect and reconnect. The device list stops observing when the tab is left; the stop on window close was not captured because the window stayed open.
- R3 fully answered: a debug capture shows only ±1 deltas at 18, 36 and 72 detents, so no accumulator is needed.
- Software volume for devices without volume control, chosen with the developer over a virtual driver, tap mute only, DDC/CI and feedback only: a Core Audio process tap with `muteBehavior = .muted`, a private aggregate device and an IO block applying a 50 dB gain law. Opt-in per device in the Devices tab. Reason: public API since macOS 14.2, no driver install, full volume and mute.
- Turning the Dial on a device it cannot control now plays the debounced end-stop buzz. Reason: chosen with the developer so the user knows nothing will change.
- `project.yml` generates `Configuration/Manopola-Info.plist` for `NSAudioCaptureUsageDescription`. Reason: Xcode has no `INFOPLIST_KEY_` build setting for that key, so the setting was silently ignored.
- Software volume hardware checkpoint with the MOTU M2: S1 audio path, mute and level, S5 clean quit with level restore, S6 even level all pass. Permission denial, latency, sample-rate change, unplug, sleep and Logic Pro (S2 to S4, S7, S8) not yet observed.
- Software volume S5 completed: a force-quit returns the audio to full level, so macOS cleans up the tap. S2 to S4, S7 and S8 deferred by the developer; the permission-denied warning, a restart on format changes and the Logic Pro bypass wait for those results.
- Dial wake-up analysis: the Dial sleeps 4 min 57 s after the last touch, and macOS needs about 1.6 s to reconnect, which an app cannot shorten. Decided with the developer: a ready click on reconnection, and an opt-in keep-awake while the Mac is in use if a harmless report keeps the Dial awake.
- Keep-awake spike succeeded with all three candidate reports sent together every 4 minutes; the responsible report is not yet isolated. The spike timer is debug-only and reads the `keepAliveSpike` user default. Ready click added in `AppDelegate`; built and unit-tested code paths unchanged, hardware feel not yet confirmed.
- Status menu: the three status lines use a smaller font and the secondary label color, set through `attributedTitle`. The Dial line shows the battery level from the Bluetooth Battery Service via CoreBluetooth (`DialBattery`), with `NSBluetoothAlwaysUsageDescription` in the generated Info.plist. Reason: requested by the developer; the I/O registry has no battery value for the Dial, and parsing System Information would be slow and brittle. Verified: 100 % read about 2 s after connecting.
- Menu bar icon and overlay show a knob instead of a speaker, so Manopola is not confused with the system Sound item. A quick test with the SF Symbols `dial.*` positions confirmed the idea; the final `KnobIcon` draws three vector template styles (Arc default, Ring, Dots), selectable in Settings as `iconStyle`. Reason: chosen by the developer after comparing rendered mockups; continuous pointer and a real mute state, which the five SF Symbols lack.
- Roadmap M6 to M8 added to DESIGN.md as FR-19 to FR-21 with sections 7.11 to 7.13, checklist items 14 to 17 and risks R9 to R11: device menu with outputs, inputs and switching, an Input line between output and volume, accessory battery levels, and a kept input device. Reason: requested by the developer; macOS moves the input to newly connected AirPods during calls on the MOTU M2.
- Decided with the developer: battery levels come from `IOPSCopyPowerSourcesByType(4)` through `dlsym`, as validated in Voltaic; clicking a device in the menu makes it the default; the kept input reverts every change while it is connected, and selecting an input in the menu moves the keep. Reason: CoreBluetooth misses AirPods and system_profiler is too slow for a menu; timing heuristics to tell automatic from manual switches are unreliable.

### 2026-10-19

- Version 1.1.0 build 2 for the first distributed build after 1.0.0, chosen by the developer. Reason: the Devices tab, software volume, ready click, knob icon and Dial battery level are new features since 1.0.0. README download name updated to match.
- Keep-awake ships in 1.1.0 as `DialKeepAwake` with the setting `keepDialAwake`, on by default, and the debug-only spike is removed. It sends all three spike reports every 3 minutes while the Dial is connected and the displays are awake (DESIGN.md §7.14, FR-16). Reason: the developer found that the release build lacked the fix, because the spike only existed in debug builds. All three reports chosen by the developer, since the responsible one is not isolated. Displays awake instead of recent input, so the Dial stays ready during a video. NFR-2 gains this timer as its second exception.
