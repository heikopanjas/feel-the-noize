# Project Instructions for AI Coding Agents

**Last updated:** 2026-10-21

## Mission Statement

Feel the Noize (formerly the working name Manopola) is a macOS menu bar app that turns a Microsoft Surface Dial into a hardware volume knob: turning changes the volume of the default output device, pressing toggles mute, and the Dial's haptic motor clicks on every step.

The full specification is `docs/DESIGN.md`. Read it before writing code; it is the source of truth for architecture, HID report layouts, Core Audio usage, gestures and milestones.

## Technology Stack

- **Language:** Swift 6 language mode, default actor isolation `MainActor`
- **UI:** AppKit only (NSStatusItem, NSMenu, NSPanel, NSWindowController); no SwiftUI, no storyboards or nibs
- **Frameworks:** IOKit HID and power sources, CoreAudio, AudioToolbox, ServiceManagement, OSLog
- **Dependencies:** none (no Swift packages)
- **Platform:** macOS 15.4+
- **Build System:** XcodeGen (`project.yml`); the `.xcodeproj` is generated and not committed
- **Tests:** Swift Testing, target `FeelTheNoizeTests` in `Tests/FeelTheNoizeTests`, hosted in the app
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

`build.sh` wraps the commands below; prefer `./build.sh build`, `test`, `lint`, `format`, `diagrams`, `icon`, `release` and `notarize`. Several commands run in order (`./build.sh lint test`); `./build.sh help` lists them. `TEAM_ID`, `DEVELOPER_ID` and `NOTARY_PROFILE` are overridden through the environment.

```sh
# Generate the Xcode project (after every change to project.yml or added/removed files)
xcodegen generate

# Build (debug)
xcodebuild -scheme FeelTheNoize -configuration Debug build | xcbeautify

# Test
xcodebuild -scheme FeelTheNoize test | xcbeautify

# Format and lint (swift-format ships with the Xcode toolchain)
xcrun swift-format format --in-place --recursive Sources Tests
xcrun swift-format lint --recursive Sources Tests

# Watch the app log, including raw HID reports
log stream --style compact --level debug --predicate 'subsystem == "com.panjas.FeelTheNoize"'

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
- Logging via `os.Logger(subsystem: "com.panjas.FeelTheNoize", category:)` with categories `dial`, `audio`, `control`, `ui`, defined in `Support/Log.swift`. A category is added with the milestone that first uses it.
- Undeclared system APIs are allowed only where their failure degrades a non-essential feature, looked up with `dlsym` and recorded in `docs/DESIGN.md`. Currently only `IOPSCopyPowerSourcesByType` for the battery levels of the Dial and audio accessories (`AccessoryBattery`).
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
- Fixed: the menu kept the volume it showed when it opened while the Dial turned. `StatusItemController.update` now sets every menu line on each state change instead of in `menuNeedsUpdate(_:)`. Reason: the titles were only refreshed on open, although Dial and Core Audio events arrive during menu tracking.
- An app cannot wake a sleeping Dial: the Bluetooth log shows macOS keeping a connection pending until the Dial is touched, so the request from the developer to wake it at launch was dropped. Instead the ready click now also plays on the first connection after launch, unless the Dial was already awake then (`DialDevice.isPresent`). Recorded in DESIGN.md §2.1, §10 and checklist item 19. Reason: chosen by the developer, so the touch after login confirms that the Dial is ready.
- Fixed: a Dial already awake at launch could fall asleep before the first keep-alive, since the timer waits a full interval. It now gets one keep-alive right away through `DialKeepAwake.sendNow()`. Reason: its idle time before the launch is unknown, and it gets no ready click that an immediate Stop trigger could cut short; observed after a restart on 2026-10-19.
- Checklist item 19 passed on the release build: the developer felt the ready click after touching a Dial asleep at launch, and the log shows no click for a Dial awake at launch.
- Dial use counts as user activity (FR-17, DESIGN.md §7.15): `UserActivity` declares activity with `IOPMAssertionDeclareUserActivity` and re-arms a 300 s `PreventUserIdleDisplaySleep` hold, at most once per second, on every Dial report, a touch included. Reason: requested by the developer, since the seized Dial bypasses the HID event system and neither woke the display nor delayed the screen saver; declared activity alone does not reset `HIDIdleTime`, which loginwindow uses for the screen saver. Stopping a running screen saver was rejected, since it needs Accessibility or a private call. Keep-awake during the screen saver stays unchanged for now.
- Fixed: AirPods connected to the Mac while an iPhone owned their audio made the Dial flicker between 49 and 51 percent, because the AirPods undo every volume write. `VolumeWriteCheck` detects a write that snaps back within 250 ms and sets `AudioState.isInUseElsewhere`: icon dimmed, menu and overlay say so, the Dial buzzes, and a probe write once per second notices when the Mac has the AirPods back. Reason: chosen by the developer; Core Audio and public Bluetooth API expose no audio ownership.
- Checklist item 21 passed on hardware: the rejection was detected on the first turn while the iPhone owned the AirPods, and cleared with the first probe after they moved to the Mac.
- Checklist item 20 passed on hardware: with a 60 s screen saver delay, loginwindow refused four times because of the Dial hold and started the screen saver 37 s after the hold timed out. Earlier attempts were invalid because the trackpad was touched or the Dial was not turned during the wait.

### 2026-10-20

- Checklist item 18 marked as passed provisionally by the developer, from the logs of 2026-10-19 rather than a dedicated run: the Dial stayed connected for over 4 hours and the first turn after 17 idle minutes worked without a reconnect. The disconnect after display sleep is still unobserved, because the screen saver kept the displays on.
- Version 1.2.0 build 3, chosen by the developer. Reason: 1.1.0 build 2 was distributed before Dial use counted as user activity and before AirPods owned by another device were detected; both are new features. README download name updated to match.
- App renamed from Manopola to Feel the Noize, chosen by the developer. The app bundle, CFBundleName and display name are `Feel the Noize`; target, scheme, Swift module, Xcode project, folders and the release zip use `FeelTheNoize`, so build paths and identifiers stay free of spaces. The Makefile quotes the app paths. Reason: the space is wanted in the name users see, but not in code and file names.
- Bundle ID, log subsystem and software volume aggregate prefix changed to `com.panjas.FeelTheNoize`, with no migration from `com.panjas.Manopola`. Reason: chosen by the developer over keeping the old ID or importing the old defaults; settings, launch at login and the Input Monitoring, audio recording and Bluetooth permissions are set up once again.
- Notary keychain profile renamed to `feelthenoize-notary`; it has to be stored once with `xcrun notarytool store-credentials` before the next `./build.sh notarize`.
- The test target sets `TEST_HOST` explicitly in `project.yml`. Reason: XcodeGen derives it from the target name, which no longer matches the product name, so `make test` could not find the host app.
- The `Makefile` is replaced by `build.sh` with the same commands and dependencies (`build` and `test` generate first, `run` builds, `release` tests). Several commands run in order and are all validated before the first runs; overrides come from the environment instead of make variables. Reason: requested by the developer. Bash 3.2 compatible, since that is the shell macOS ships.
- Notarization uses the keychain profile `developer-id-notary`, which holds an App Store Connect API key and is shared by all Developer ID apps of the team, instead of the per-app `feelthenoize-notary`. Reason: stored by the developer; a profile is not tied to an app, so one key covers every project.
- `./build.sh notarize` staples a copy unpacked from the submitted zip instead of the app in `.build/Products/Release`, then validates and re-zips it, and fails early when the zip is missing. Reason: requested by the developer after the first notarization was accepted but stapling failed, because the release app had been moved to /Applications.
- Renamed app verified on hardware by the developer: Feel the Noize 1.2.0 build 3 from /Applications works with the Dial under the new bundle ID, with permissions granted again.

### 2026-10-21

- Checklist items 1 to 12 confirmed by the developer on the renamed 1.2.0 build 3 installed in /Applications.
- M6 built: `CoreAudioProperty` reads and writes the default device per scope (`readDefaultDevice(scope:)` replaces `readDefaultOutputDevice()`), looks up a device by UID and checks streams per scope; `AudioDeviceInfo` gains `hasOutput` and `hasInput`; `AudioDeviceList` lists inputs and publishes `defaultOutputUID` and `defaultInputUID`; the Devices tab filters to outputs. `StatusItemController` owns its own device list while the menu is open and shows the Input line and the Output and Input sections; `AppDelegate.selectDefaultDevice(_:scope:)` switches. Reason: FR-19 and FR-20 as designed in DESIGN.md §7.11.
- A menu section without devices is left out. Reason: an empty header carries no information; not covered by the original design.
- Device icons in the menu sections, chosen by the developer over plain symbols with a bold default: `DeviceIcon` draws an SF Symbol in a circle like the macOS Sound menu, accent for the default device, gray for the others. The default device keeps its bold title as well, requested by the developer after seeing the icons. Symbols follow transport, Apple Bluetooth product ID from the model UID, the built-in headphone data source and the built-in name; `AudioDeviceInfo` gains `modelUID` and `outputDataSource`. Size, 26 pt circle with a 13 pt glyph, hierarchical rendering, the `macbook` symbol and the generic symbols for USB and Continuity devices match a screenshot of the Sound menu. Reason: Core Audio exposes no device icons, probed on all connected devices.
- M6 switching verified by the developer on hardware: outputs and inputs switch from the menu. Still open in items 14 and 15: AirPods appearing while the menu is open, alert sounds following the output, and the Input line following a change in System Settings.
- Volume slider in the menu between the separator below the Volume line and the Output section (FR-22, DESIGN.md §5.3, checklist item 22), requested by the developer. It stands at zero while muted, unmutes when moved, is disabled when the volume cannot be set or another device owns the output, and like the menu's Mute gives no haptics or overlay and ignores the Devices tab selection. Reason: behaves like the slider of the system Sound menu; the selection only concerns the Dial.
- The volume slider got a bold Volume heading and the look of the Sound menu slider, requested by the developer: `VolumeSlider` with a nested `NSSliderCell` replaces only the drawing, with a bordered capsule track, white fill and knob, and a headphone or speaker glyph at the left end. Colors are fixed values measured on a screenshot of the Sound menu, and the slider opts out of vibrancy, after the developer found the first version lacking the border and contrast. Reason: subclassing keeps tracking, keyboard control and VoiceOver of the standard slider; vibrancy would wash out the measured colors.
- The Dial battery moved to the right edge of the Dial line as percentage plus a drawn battery symbol, like the AirPods row of the Sound menu, chosen by the developer over a device-style Dial row and a plain percentage. All four status lines became `MenuInfoRow` custom views with the 14 pt inset of the slider row; `BatteryIcon` draws the battery, red at 20 percent and below. Reason: a menu item title cannot align to the right edge of the menu, and SF Symbols has the battery only in quarter steps.
- Offscreen snapshots of text fields rendered through `cacheDisplay` show some rows darker at random; rendering through `dataWithPDF` is reliable. Use PDF when checking UI drawing offscreen.
- M8 built: `keptInputDeviceUID` and `knownInputDevices` in `Settings`, `InputDeviceKeeper` with listeners only while a device is kept, a Keep input device popup in the Devices tab, the keep moved by choosing an input in the menu, and "(kept)" on the Input line. Tests: `SettingsTests` extended, `KeepChoicesTests` new, `StatusItemTitleTests` updated. Reason: FR-21 as designed in DESIGN.md §7.13. Checklist item 17 and R11 are pending on hardware.
- M8 checked on hardware by the developer, from the log: the keep reverts the input to the M2 55 to 65 ms after macOS moves it to the AirPods Max on an output switch, and menu input choices move the keep. A call, unplugging the M2 and R11 not yet observed.
- The keep moves before the menu writes the default input. Reason: the other order lets the keeper revert the user's choice to the old kept device.
- M7 built: `AccessoryBattery` reads the accessory power sources through `dlsym`, matches audio devices by the Bluetooth address in their Core Audio UID, and the menu shows the level after each device name in a shared right tab column, with the battery symbol for single cells. R10 answered for AirPods Max: UID `70-F9-4A-A8-CE-BF:output` matches identifier `70:F9:4A:A8:CE:BF`.
- `DialBattery` and CoreBluetooth removed, together with `NSBluetoothAlwaysUsageDescription`; the Dial level now comes from the same power sources, found by Microsoft vendor ID 1118 and product ID 2331, and is read when the menu opens. Reason: chosen by the developer after the probe showed the Dial among the sources; no Bluetooth permission prompt and one source for all levels, at the cost of no live push and a dependency on the undeclared call.
- Device batteries moved from a tab stop in the regular menu font to the small font and the right-edge column of the Dial battery, requested by the developer. Device items became `MenuDeviceRow` custom views that draw a rounded gray highlight like the Sound menu and send the item action on mouse up; `BatteryIcon.attributedText(_:level:)` builds the battery text for Dial and device rows. Reason: a menu item title cannot align with the right edge of the menu; sharing the text builder keeps both rows identical.
- The Volume heading became a system section header like Output and Input, requested by the developer. The Mute checkmark was replaced by a speaker symbol at the right edge in a `MenuMuteRow` custom view, chosen by the developer over a Mute/Unmute title. Reason: a checkmark makes macOS add a state column that shifted all standard items right of the custom rows while muted.
- The Mute item title switches to Unmute while muted, in addition to the speaker symbol, requested by the developer. The row is sized for the longer title, so the menu width stays the same.
