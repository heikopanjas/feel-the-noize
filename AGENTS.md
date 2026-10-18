# Project Instructions for AI Coding Agents

**Last updated:** 2026-10-18

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
- Concurrency: everything is main-actor isolated. IOKit and Core Audio callbacks run on the main run loop / main queue and enter the actor with `MainActor.assumeIsolated`. No `@unchecked Sendable`, no locks. C callbacks resolve the main-actor owner from the context pointer before entering the actor; a non-Sendable CF argument such as `IOHIDDevice` is handed over through a commented `nonisolated(unsafe) let`, the only permitted unsafe opt-out.
- Logging via `os.Logger(subsystem: "com.panjas.Manopola", category:)` with categories `dial`, `audio`, `control`, `ui`, defined in `Support/Log.swift`. A category is added with the milestone that first uses it.
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
