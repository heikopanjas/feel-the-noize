# Manopola — Software Design Document

| | |
|---|---|
| **Status** | Draft 0.1 |
| **Date** | 2026-10-17 |
| **Author** | Heiko Panjas |
| **Product** | Manopola (working name), macOS menu bar app |
| **Bundle ID** | `com.panjas.Manopola` |

> *Manopola* is Italian for "knob". The name is a placeholder; renaming touches `project.yml`, the source folder and this document only.

---

## 1. Purpose and Scope

Manopola turns a Microsoft Surface Dial into a hardware volume knob for the Mac:

- turning the Dial changes the volume of the current default output device,
- pressing the Dial toggles mute,
- the Dial's built-in haptic motor gives a detent click per step.

The app is a native AppKit menu bar utility with no third-party dependencies. This document is the hand-off specification for implementation: it records what is known about the hardware, the decisions taken, the architecture, and the open points that must be verified on real hardware first.

## 2. Background: The Surface Dial on macOS

### 2.1 Hardware

| Property | Value |
|---|---|
| Vendor / Product ID | `0x045E` / `0x091B` |
| Transport | Bluetooth LE (HID over GATT), requires Bluetooth 4.0. Verified 2026-10-18: IOKit reports transport "Bluetooth Low Energy", primary usage Generic Desktop `0x0E`, max input / output / feature report sizes 73 / 73 / 53 bytes (the vendor collections are larger than report 1) |
| Power | 2 × AAA |
| Controls | rotation (relative, up to 3600 steps per revolution), one push button |
| Feedback | haptic motor, controllable via HID haptics usage page `0x0E` |
| Availability | discontinued; buy used or open-box |

The Dial pairs with macOS like any Bluetooth input device, but macOS has no driver logic for it: the generic HID path turns its reports into invalid mouse input. Every working macOS solution therefore opens the device directly through IOKit HID and interprets the raw reports itself. That is what Manopola does.

### 2.2 Prior Art

| Project | Approach | Taken over | Avoided |
|---|---|---|---|
| **Mac Dial** (`andreasjhkarlsson/mac-dial`, fork `drashna/mac-dial`) | hidapi fork read on a dedicated blocking thread; synthesizes media keys via `CGEvent`; "scroll" and "playback" modes | report layout, haptic feature report | extra thread and retry loop for discovery; Accessibility permission for synthetic keys; step size fixed by macOS (1/64 with Shift+Option); unsigned builds, so macOS drops the Accessibility grant after every update |
| **OrbitLauncher** Surface Dial preview (`S7venYoung/RingLauncher`, tag `v0.2.0-dial.1`) | `IOHIDManager` on the main run loop; reads the resolution multiplier; configures haptic detents | event-driven HID session, haptic re-configuration after Dial idle sleep, HID session rebuild after Mac wake | — |
| **surface-dial-linux** (`daniel5151/surface-dial-linux`) | Linux user-space daemon | the dumped HID report descriptor (`notes/HID_Report_Descriptor.txt`) and haptics report encoding — the authoritative layout source for §7.1 | — |

Mac Dial's playback mode does volume plus play/pause, but has no mute and goes through synthetic media keys. Manopola talks to Core Audio directly instead, which needs no Accessibility permission, allows arbitrary step sizes, and makes mute a first-class action.

## 3. Goals and Non-Goals

### Goals

1. Control output volume and mute with the Dial, with haptic detents.
2. Follow whatever device is the current default output, including changes while running (AirPods connecting, display audio, USB interface).
3. Stay in sync with volume and mute changes made elsewhere (keyboard, Control Center, other apps).
4. Survive Dial idle sleep, Bluetooth reconnects, and Mac sleep/wake without user action.
5. Zero idle CPU: fully event-driven, no polling.
6. No Accessibility permission, no third-party dependencies, no network access.

### Non-Goals (v1)

- Scroll mode, media transport (play/pause/next), or per-app volume.
- Radial on-screen menus as on the Surface Studio.
- Multiple Dials at once (the first one matched is used).
- Mac App Store distribution.
- Dial battery level (not part of the HID descriptor; see §15).

## 4. Requirements

### Functional

| ID | Requirement |
|---|---|
| FR-1 | Detect a paired and connected Surface Dial automatically; reconnect automatically after it disappears. |
| FR-2 | Each rotation detent changes the default output volume by the configured step (default 2 %). |
| FR-3 | A short press (press and release without rotation) toggles mute of the default output device. |
| FR-4 | Rotating while the button is held adjusts by a quarter step (fine mode) and suppresses the mute toggle on release. |
| FR-5 | Any rotation while muted unmutes first, as the macOS volume keys do. |
| FR-6 | Track the default output device live. |
| FR-7 | Reflect external volume and mute changes in the menu bar icon and menu. |
| FR-8 | Haptic detents can be switched off; end-stop and mute toggles produce distinct haptic feedback. |
| FR-9 | Menu bar icon shows volume level, mute state, and whether the Dial is connected. |
| FR-10 | Optional on-screen overlay for Dial-initiated changes. |
| FR-11 | Settings window for all options in §7.7. |
| FR-12 | Launch at login. |

### Non-Functional

| ID | Requirement |
|---|---|
| NFR-1 | Latency from HID report to Core Audio call under 5 ms on the main thread. |
| NFR-2 | No timers or polling while idle; idle CPU is 0 %. |
| NFR-3 | Builds clean in Swift 6 language mode with complete concurrency checking. |
| NFR-4 | Passes `swift-format lint` with the repository `.swift-format`. |
| NFR-5 | No third-party packages. Frameworks: AppKit, IOKit, CoreAudio, AudioToolbox, ServiceManagement, OSLog. |
| NFR-6 | Signed with a stable Developer ID so privacy grants survive updates. |

## 5. Interaction Design

### 5.1 Gestures

| Gesture | Action | Haptics |
|---|---|---|
| Turn clockwise | volume up one step per detent | detent click (device-generated) |
| Turn counter-clockwise | volume down one step per detent | detent click |
| Turn while muted | unmute, then step | detent click |
| Short press | toggle mute | mute: double click; unmute: single click |
| Press and turn | fine adjust, quarter step per detent; no mute toggle on release | detent click |
| Turn past 0 % or 100 % | nothing changes | short end-stop buzz (100 ms) once; it repeats only after a pause of at least 300 ms between end-stop detents |

"Reverse direction" in Settings swaps the meaning of clockwise and counter-clockwise.

### 5.2 Menu Bar Icon

The icon is an SF Symbol rendered as a template image:

| State | Symbol |
|---|---|
| Volume > 0, not muted | `speaker.wave.3.fill` with `variableValue` = volume (0…1) |
| Volume = 0 or muted | `speaker.slash.fill` |
| Output device without software volume | `speaker.fill`, button `appearsDisabled = true` |
| No output device | `speaker.fill`, button `appearsDisabled = true` |
| Dial not connected, or in use by another app | current symbol, button `appearsDisabled = true` |

### 5.3 Menu

```
Surface Dial: Connected            (disabled info item; or Not Connected, or In Use by Another App)
Output: MacBook Pro Speakers       (disabled info item)
Volume: 42 %                       (disabled info item)
─────────────
Mute                         ✓     (toggles mute; state reflects mute)
─────────────
Settings…                    ⌘,
About Manopola
─────────────
Quit Manopola                ⌘Q
```

The menu is built once. `NSMenuDelegate.menuNeedsUpdate(_:)` refreshes titles and states right before display. When HID access is denied (§9.2), an extra item "Allow Input Monitoring…" appears below the Dial status line. Without an output device the lines read "Output: None" and "Volume: –". "Mute" is disabled when the device has neither a mute control nor software volume. The menu's Mute item sets mute on `AudioOutput` directly, without haptics or overlay, which belong to Dial gestures.

### 5.4 Volume Overlay

Because Manopola sets the volume through Core Audio, the system volume HUD does not appear. Manopola shows its own overlay for Dial-initiated changes only; changes made with the keyboard keep showing the system HUD, so the two never stack.

- `NSPanel`, style `[.borderless, .nonactivatingPanel]`, `level = .statusBar`, `ignoresMouseEvents = true`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`.
- Content: `NSVisualEffectView` (material `.hudWindow`, rounded 18 pt) with the speaker symbol, a 16-segment level bar, and the percentage. 200 × 200 pt.
- Placement: horizontally centered on the screen that contains the mouse pointer, 140 pt above the bottom of its `visibleFrame`.
- Shown immediately, faded out over 0.3 s after 1.5 s without further Dial input (`NSAnimationContext`). A single panel instance is reused.

## 6. Architecture

![Class overview](diagrams/class-overview.svg)

Source: [`diagrams/class-overview.puml`](diagrams/class-overview.puml)

| Module | Responsibility |
|---|---|
| **App** | `main.swift` creates `NSApplication` and installs `AppDelegate`. `AppDelegate` owns all long-lived objects, wires their callbacks, starts and stops them. No storyboards or nibs. |
| **Dial** | `DialDevice` owns the IOKit HID session for the Dial: discovery, input reports, feature/output reports, reconnection. `DialReport` is a pure encoder/decoder for the byte layouts. `DialEvent` is the device-independent event vocabulary. |
| **Control** | `DialController` is the gesture recognizer and the only place that decides what a Dial event does. It depends on two protocols (`AudioControlling`, `HapticFeedback`) so it can be unit-tested without hardware. `VolumeStepper` holds the step math. |
| **Audio** | `AudioOutput` wraps Core Audio for the default output device: read and write volume and mute, observe device and property changes, publish `AudioState`. |
| **UI** | `StatusItemController` (NSStatusItem and menu), `VolumeOverlay` (HUD panel), `SettingsWindowController` (preferences window). |
| **Support** | `Settings` (typed `UserDefaults` wrapper), `LoginItem` (`SMAppService.mainApp`), `Log` (`os.Logger` categories). |

Data flows one way: **DialDevice → DialController → AudioOutput → (Core Audio listener) → AudioOutput.onChange → StatusItemController**. The only reverse paths are haptic commands from `DialController` back to `DialDevice` and `onAdjusted` to the overlay.

![Rotation sequence](diagrams/rotate-sequence.svg)

Source: [`diagrams/rotate-sequence.puml`](diagrams/rotate-sequence.puml)

## 7. Detailed Design

### 7.1 HID Protocol

All multi-byte fields are little-endian. Report layouts follow the dumped report descriptor (top-level usage Generic Desktop `0x0E` "System Multi-axis Controller", logical collection Digitizer `0x21` "Puck").

**Input report 1 — state** (8 bytes payload, 9 with report ID)

| Byte | Bits | Usage | Meaning |
|---|---|---|---|
| 0 | — | Report ID | `0x01` |
| 1 | 0 | Button 1 | 1 = pressed |
| 1 | 1 | Digitizer Touch | on-screen contact (Surface Studio only; ignore) |
| 1 | 2–7 | — | padding |
| 2–3 | — | Generic Desktop Dial (`0x37`) | signed 16-bit relative rotation delta; positive = clockwise |
| 4–5 | — | X | on-screen position, null state; ignore |
| 6–7 | — | Y | on-screen position, null state; ignore |
| 8 | — | Digitizer Width | constant 58; ignore |

The delta unit is 1 / *R* of a revolution, where *R* is the resolution multiplier from the feature report. Manopola sets *R* = detents per revolution, so a delta of ±1 is exactly one detent. A fast turn can arrive as one report with |delta| > 1; it is handled as that many detents.

**Feature report 1 — resolution and haptics configuration** (7 bytes payload, 8 with report ID)

| Byte | Usage | Value written by Manopola |
|---|---|---|
| 0 | Report ID | `0x01` |
| 1–2 | Resolution Multiplier (Generic Desktop `0x48`), 0…3600 | detents per revolution (default 36) |
| 3 | Haptics Repeat Count (`0x0E:0x24`) | `0x00` |
| 4 | Haptics Auto Trigger (`0x0E:0x20`), waveform ordinal 1…7 | `0x03` (click) when haptic detents are on, `0x02` (stop/none) when off |
| 5 | Haptics Waveform Cutoff Time (`0x0E:0x28`) | `0x00` |
| 6–7 | Haptics Retrigger Period (`0x0E:0x25`), 0…2000 | `0x0000` |

**Output report 1 — manual haptic trigger** (4 bytes payload, 5 with report ID)

| Byte | Usage | Meaning |
|---|---|---|
| 0 | Report ID | `0x01` |
| 1 | Haptics Repeat Count (`0x0E:0x24`) | additional repetitions (0 = play once) |
| 2 | Haptics Manual Trigger (`0x0E:0x21`) | waveform ordinal: 3 = click, 4 = buzz |
| 3–4 | Haptics Retrigger Period (`0x0E:0x25`) | milliseconds between repetitions |

Waveform ordinals per the descriptor's waveform list: 3 → `0x1003` (Click), 4 → `0x1004` (Buzz Continuous). Ordinals 1 and 2 are the HID-defined None and Stop.

**Observed on hardware (2026-10-18, 36 detents, debug capture of 236 input reports):**

- Input report 1 always arrives as 9 bytes with the report ID first (R1).
- Byte 1 bit 1 (Digitizer Touch) is set in most reports during normal use, not only on a Surface Studio; the parser already ignores it.
- Bytes 4–7 are constant `0A 0B 0C 0D`, byte 8 is `0x3A` (58).
- Every delta is `0x0001`, `0xFFFF` or `0x0000`; fast turns arrive as a quick series of ±1 reports, not as one larger delta.
- Each button press also sends input report ID 50 (`0x32`), 2 bytes, always `32 02`. It is not part of the layouts above and is ignored.
- Manual triggers are accepted. Click with repeat 1 at 120 ms plays as a distinct double click. Buzz (ordinal 4) is *continuous*: it keeps playing until another haptic replaces it, such as the next detent click or a manual trigger (R4).

Feature report 2 (Auto Trigger Associated Control = `0x00010037`, the Dial axis) and the vendor collections `0xFF07` (report IDs 42, 48) are not used.

**Haptic patterns used**

| Pattern | Report | Bytes |
|---|---|---|
| Detent click | automatic, from feature report 1 | — |
| Unmute | output 1, click, repeat 0 | `01 00 03 00 00` |
| Mute | output 1, click, repeat 1, 120 ms | `01 01 03 78 00` |
| End stop | output 1, buzz, repeat 0; then output 1, Stop, 100 ms later | `01 00 04 00 00`, then `01 00 02 00 00` |

### 7.2 DialDevice

![Dial lifecycle](diagrams/dial-lifecycle.svg)

Source: [`diagrams/dial-lifecycle.puml`](diagrams/dial-lifecycle.puml)

```swift
enum DialEvent: Equatable {
    case rotated(detents: Int)  // positive = clockwise, before direction preference
    case pressed
    case released
}

enum HapticWaveform: UInt8 {
    case stop = 2
    case click = 3
    case buzz = 4
}

struct DialInputReport: Equatable {
    let isPressed: Bool
    let delta: Int16
}

enum DialReport {
    static let vendorID = 0x045E
    static let productID = 0x091B
    static let reportID: UInt8 = 0x01

    static func parseInput(reportID: UInt32, bytes: [UInt8]) -> DialInputReport?
    static func hapticConfiguration(detentsPerRevolution: Int, hapticsEnabled: Bool) -> [UInt8]
    static func manualTrigger(waveform: HapticWaveform, repeatCount: UInt8, retriggerMilliseconds: UInt16) -> [UInt8]
}

enum DialConnection: Equatable {   // DialConnection.swift
    case notConnected
    case connected
    case inUseElsewhere   // present, but another process holds it exclusively
}

final class DialDevice: HapticFeedback {
    var onEvent: ((DialEvent) -> Void)?
    var onConnectionChange: ((DialConnection) -> Void)?
    var onAccessDenied: (() -> Void)?
    private(set) var connection: DialConnection
    var isConnected: Bool { get }   // connection == .connected

    func start()
    func stop()
    func retryIfInUseElsewhere()
    func configure(detentsPerRevolution: Int, hapticsEnabled: Bool)
    func playHaptic(_ waveform: HapticWaveform, repeatCount: UInt8, retriggerMilliseconds: UInt16)
}
```

**Session setup**

1. `IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone)`.
2. `IOHIDManagerSetDeviceMatching` with `kIOHIDVendorIDKey = 0x045E`, `kIOHIDProductIDKey = 0x091B`.
3. Register matching, removal and input-report callbacks (`IOHIDManagerRegisterDeviceMatchingCallback`, `…RemovalCallback`, `…InputReportCallback`) with `Unmanaged.passUnretained(self)` as context. `DialDevice` lives for the whole app lifetime, so the unretained context is safe; `stop()` unregisters before the object could go away.
4. `IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes)`. All callbacks therefore arrive on the main thread.
5. `IOHIDManagerOpen(manager, kIOHIDOptionsTypeSeizeDevice)`. Seizing gives Manopola exclusive access and stops macOS from turning the Dial's reports into stray pointer events. If the open returns `kIOReturnExclusiveAccess`, open again with `kIOHIDOptionsTypeNone`. If it returns `kIOReturnNotPermitted`, follow §9.2.

**Report parsing.** `parseInput` accepts both buffer shapes seen on macOS: 9 bytes starting with `0x01` (report ID included) and 8 bytes when `reportID == 1` (ID stripped). Anything else returns `nil` and is logged at debug level. `DialDevice` keeps the last button state and emits `.pressed` / `.released` only on edges, then `.rotated(detents: Int(delta))` if `delta != 0`.

**Haptics configuration** is sent with `IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 1, bytes, 8)` — the buffer includes the report ID byte. It is sent:

- on every device match,
- whenever `configure(...)` is called (settings changed),
- on the first input report after 15 s or more without reports. The Dial powers down when idle and may come back with its default configuration; re-sending 8 bytes is cheap and makes this robust.

Manual triggers use `IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 1, bytes, 5)`. `HapticFeedback` conformance maps `endStop()` and `muteToggled(isMuted:)` to the patterns in §7.1 through `playHaptic(_:repeatCount:retriggerMilliseconds:)`; calls while disconnected are ignored. `endStop()` is debounced inside `DialController` (§7.3). Because the buzz waveform is continuous (§7.1), `endStop()` schedules a Stop trigger (ordinal 2) 100 ms after the buzz; any other `playHaptic` call within that window cancels the pending Stop, since its waveform replaces the buzz anyway. The user chose this short buzz over the three-click fallback: the Dial's own click feel is sluggish, which makes rapid click patterns hard to tell apart.

**Adoption.** A matching callback alone does not make the Dial usable. When another process has seized it, IOKit still reports the match, but `IOHIDManagerOpen` fails with `kIOReturnExclusiveAccess` in both modes and every report is refused (verified 2026-10-18 with two Manopola instances). The haptic configuration is the first report sent to a matched device, so its result decides:

- success, or a failure such as a Bluetooth timeout: the device is adopted and the state becomes `.connected`;
- `kIOReturnExclusiveAccess`: the device is remembered as blocked and the state becomes `.inUseElsewhere`; its removal returns the state to `.notConnected`;
- `kIOReturnNotOpen` or `kIOReturnNotPermitted`: logged, not adopted.

IOKit sends no notification when the other process releases the Dial, and polling is ruled out (NFR-2). `retryIfInUseElsewhere()` therefore rebuilds the manager on occasions the user causes: when the status menu opens and when the app becomes active. The published state is kept during that rebuild so the menu does not flicker; if `IOHIDManagerCopyDevices` then finds no Dial, the state becomes `.notConnected` right away. The Dial's own sleep and wake cycle and Mac wake cause a fresh match as well, which retries implicitly. Verified on hardware 2026-10-18: with two instances, the second reported `.inUseElsewhere` within the same second the first connected; after the first quit, opening the second's menu retried and connected in about 50 ms.

**Recovery.** On `NSWorkspace.didWakeNotification`, and when the input-report callback delivers a non-success `IOReturn`, schedule a rebuild 1 s later: unschedule, close, release, and re-create the manager. A pending rebuild is cancelled and rescheduled if another trigger arrives. Removal resets the button state and emits `onConnectionChange(.notConnected)`; `AppDelegate` then calls `DialController.reset()` so an in-flight press never toggles mute.

### 7.3 DialController

![Gesture states](diagrams/gesture-states.svg)

Source: [`diagrams/gesture-states.puml`](diagrams/gesture-states.puml)

```swift
protocol AudioControlling: AnyObject {
    var state: AudioState? { get }
    func setVolume(_ volume: Float32)
    func setMuted(_ muted: Bool)
}

protocol HapticFeedback: AnyObject {
    func endStop()
    func muteToggled(isMuted: Bool)
}

struct ControlSettings: Equatable {
    var stepPercent: Int
    var reverseDirection: Bool
}

final class DialController {
    var onAdjusted: ((AudioState) -> Void)?

    init(
        audio: any AudioControlling, haptics: any HapticFeedback,
        settings: @escaping () -> ControlSettings,
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }
    )

    func handle(_ event: DialEvent)
    func reset()
}
```

**Gesture state:** `idle`, `pressedStill`, `pressedTurned` (see diagram). Rules:

1. `rotated(n)`: if `reverseDirection`, `n = -n`. Step size is `stepPercent / 100`, or a quarter of it while pressed. If there is no state or `canSetVolume == false`, do nothing. If muted, call `setMuted(false)` first. Compute the new volume with `VolumeStepper`. If it equals the current volume and the current volume is at 0 or 1 in the direction of travel, call `haptics.endStop()`, debounced with `now`: the buzz plays only if the previous end-stop detent is at least 300 ms old, so a continuous spin past the end buzzes once (checklist item 5). Otherwise `setVolume`. The step is computed from the state after unmuting, because unmuting an emulated mute restores the remembered volume. Then call `onAdjusted(audio.state)`. Rotating while pressed moves to `pressedTurned` even when the volume cannot change, so the release never toggles mute.
2. `pressed` → `pressedStill`.
3. `released` in `pressedStill` → toggle mute, `haptics.muteToggled(isMuted:)` with the new state, `onAdjusted`. In `pressedTurned` → only return to `idle`.
4. `reset()` → `idle`.
5. A mute toggle the device refuses (neither mute nor software volume) gives no haptic confirmation and no `onAdjusted`.

**VolumeStepper.** `VolumeStepper.volume(from:detents:step:) -> Float32`, a caseless enum. Volumes are snapped to the step grid in the direction of travel so that a level set elsewhere (e.g. 37 %) never produces an uneven first step. The math runs in `Double`; zero detents return the volume unchanged:

```
ε = 0.0001
base = detents > 0 ? floor((v + ε) / s) · s : ceil((v − ε) / s) · s
result = clamp(base + detents · s, 0, 1)
```

Test vectors (s = 0.02): 0.37 ↑1 → 0.38; 0.37 ↓1 → 0.36; 0.40 ↑1 → 0.42; 0.40 ↓1 → 0.38; 0.99 ↑1 → 1.00; 0.01 ↓3 → 0.00; 1.00 ↑1 → 1.00 (end stop). Fine mode (s = 0.005): 0.37 ↑1 → 0.375.

### 7.4 AudioOutput

```swift
struct AudioState: Equatable {
    var deviceID: AudioObjectID
    var deviceUID: String
    var deviceName: String
    var volume: Float32       // 0...1, virtual main volume
    var isMuted: Bool
    var canSetVolume: Bool
    var hasHardwareMute: Bool
}

final class AudioOutput: AudioControlling {   // conformance added in M3 with the protocol
    private(set) var state: AudioState?   // nil when there is no output device
    var onChange: ((AudioState?) -> Void)?

    func start()
    func stop()
    func setVolume(_ volume: Float32)
    func setMuted(_ muted: Bool)
}
```

**Default device.** Read `kAudioHardwarePropertyDefaultOutputDevice` on `kAudioObjectSystemObject`, and observe it with `AudioObjectAddPropertyListenerBlock` (queue `DispatchQueue.main`). On change: remove the listeners from the old device, attach them to the new one, re-read the state.

**Volume.** Use the virtual main volume, which Core Audio derives from the device's per-channel controls and which behaves like the system volume slider:

- read and write through `AudioObjectGetPropertyData` / `AudioObjectSetPropertyData` with `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` (constant from AudioToolbox), scope `kAudioDevicePropertyScopeOutput`, element `kAudioObjectPropertyElementMain`. The HAL serves this property directly; the `AudioHardwareService…` functions are deprecated since macOS 10.11 and are not used;
- `canSetVolume` = `AudioObjectHasProperty` and `AudioObjectIsPropertySettable` both true. Many HDMI/DisplayPort outputs, some USB interfaces and aggregate devices have no software volume; those get the disabled state from §5.2 and rotation is ignored. Their `volume` is reported as 1, the fixed full level.

**Mute.**

- `hasHardwareMute` = `kAudioDevicePropertyMute` (scope output, element main) exists and is settable. Then mute is that property.
- Otherwise mute is emulated: remember the current volume keyed by `deviceUID` (in memory), set volume 0, report `isMuted = true`. Unmute restores the remembered volume. If the volume is changed to a non-zero value from elsewhere while emulated-muted, the emulated mute is cleared.

**Observation.** On the current device, listen with `AudioObjectAddPropertyListenerBlock` for the virtual main volume (as above), `kAudioDevicePropertyVolumeScalar` (scope output, element `kAudioObjectPropertyElementWildcard`) and `kAudioDevicePropertyMute` (scope output, element main). A device lacking one of them refuses that listener, which is logged at debug level. Any notification re-reads the full state; `onChange` fires only when the new `AudioState` differs from the cached one. If re-reading a newly selected device fails, the state becomes `nil` rather than keeping the previous device's values.

Core Audio identifies a listener by its block pointer. The listener closures are therefore stored once as `@convention(block)` values and the same instances are passed to add and remove.

**Writes** update the cached state immediately (optimistic) so `DialController` and the overlay see the new value without waiting for the listener round-trip; the listener then confirms or corrects it. Core Audio reads a written volume back with float noise (0.58 as 0.58000004); a re-read that differs from the cached volume of the same device by less than 0.0001 keeps the cached value, so it does not fire `onChange` a second time.

**Errors.** `CoreAudioError` and `OSStatus.throwIfError(_:)` are ported from Push to Hush (`CoreAudioSource.swift`), with the four-character-code rendering corrected to most-significant byte first. Failures are logged under the `audio` category; the cached state stays at the last confirmed value.

### 7.5 StatusItemController and VolumeOverlay

- `StatusItemController` creates an `NSStatusItem` with `squareLength`, sets the menu from §5.3 and implements `NSMenuDelegate`. `update(audio:dial:)` changes the button image, `appearsDisabled` and the Dial status line (so a retry result shows while the menu is open); the other menu titles are refreshed in `menuNeedsUpdate(_:)`. `menuWillOpen(_:)` calls `onMenuWillOpen`, which `AppDelegate` uses for `DialDevice.retryIfInUseElsewhere()`.
- Images: `NSImage(systemSymbolName:variableValue:accessibilityDescription:)`, `isTemplate = true`. Accessibility description states volume and mute, e.g. "Volume 42 %, muted", plus ", Surface Dial not connected" when applicable. Symbol choice, percentage text ("42 %") and accessibility text live in `VolumePresentation`, shared by the status item and the overlay.
- `StatusItemController` reports menu actions through `onToggleMute` and `onOpenSettings`; "Allow Input Monitoring…" and "About Manopola" are handled inside it.
- `VolumeOverlay.show(_:)` is called from `DialController.onAdjusted` and respects the `showOverlay` setting (checked in `AppDelegate`).

### 7.6 SettingsWindowController

Programmatic `NSWindowController` + `NSViewController` with an `NSGridView`. Non-resizable, titled "Manopola Settings", centered on first show, standard close button. Shown with `NSApp.activate()` because the app is `LSUIElement`.

| Label | Control | Values |
|---|---|---|
| Detents per turn | `NSPopUpButton` | 18, 24, 36, 48, 72 |
| Volume step | `NSPopUpButton` | 1 %, 2 %, 3 %, 5 % |
| Reverse direction | `NSButton` (checkbox) | — |
| Haptic detents | `NSButton` (checkbox) | — |
| Show volume overlay | `NSButton` (checkbox) | — |
| Launch at login | `NSButton` (checkbox) | — |

Changes apply immediately (no Apply button). When `LoginItem.status == .requiresApproval`, a small label and a button "Open Login Items…" (`SMAppService.openSystemSettingsLoginItems()`) appear below the checkbox. The checkbox shows on for both `.enabled` and `.requiresApproval`, since the app is registered in both cases. The view controller re-reads all values in `viewWillAppear()`, because launch at login can change in System Settings.

### 7.7 Settings and Persistence

`Settings` wraps `UserDefaults.standard`, registers defaults at launch, exposes typed properties and calls `onChange` after every write. `AppDelegate` reacts by calling `dial.configure(...)` when detents or haptics changed.

| Key | Type | Default | Valid range |
|---|---|---|---|
| `detentsPerRevolution` | Int | 36 | 18, 24, 36, 48, 72 |
| `volumeStepPercent` | Int | 2 | 1, 2, 3, 5 |
| `reverseDirection` | Bool | false | — |
| `hapticDetents` | Bool | true | — |
| `showOverlay` | Bool | true | — |

Out-of-range stored values fall back to the default. Launch at login is not stored; `SMAppService.mainApp.status` is the source of truth (`register()` / `unregister()` in `LoginItem`, a caseless enum).

### 7.8 Logging

`os.Logger(subsystem: "com.panjas.Manopola", category:)` with categories `dial`, `audio`, `control`, `ui`. Raw report bytes are logged at `.debug` only. No log files, no telemetry.

## 8. Concurrency Model

- The target builds in Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; every type in the app is main-actor isolated. The workload — a few HID reports per second and a Core Audio call each — does not justify background work.
- IOKit HID callbacks are `@convention(c)` functions without captures, declared at file scope as `nonisolated`. Because the manager is scheduled on the main run loop, they run on the main thread; they recover the object from the context pointer and call into it inside `MainActor.assumeIsolated { }`.
- Core Audio listener blocks are registered on `DispatchQueue.main` and use `MainActor.assumeIsolated` the same way.
- The callbacks resolve the `DialDevice` from the context pointer before entering the actor; as a main-actor class it is Sendable. The non-Sendable `IOHIDDevice` argument is passed through a `nonisolated(unsafe) let`, which is sound because it never leaves the main thread.
- No `@unchecked Sendable`, no locks, no `DispatchQueue.async` hops.

## 9. Permissions, Signing, Distribution

### 9.1 Signing and Distribution

- Not sandboxed (`ENABLE_APP_SANDBOX = NO`), Hardened Runtime on, no entitlements file. App Store distribution is a non-goal, and raw HID access to a Bluetooth device is the core of the app.
- Signed with Developer ID (team `8J2G689FCZ`), notarized with `xcrun notarytool`, stapled. A stable signing identity keeps privacy grants across updates — the problem that makes Mac Dial lose its Accessibility permission after every update does not occur.
- `project.yml` keeps automatic development signing. `make release` passes the Developer ID identity, manual signing, `--timestamp` and `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` on the command line, verifies the signature, and fails if the `get-task-allow` entitlement is present, because Xcode injects it into plain builds and the notary service rejects it. The result is a universal (arm64, x86_64) app with the hardened runtime and no entitlements, zipped to `build/dist/Manopola-<version>.zip`.
- `make notarize` submits the zip with `xcrun notarytool` using a stored keychain profile (default `manopola-notary`), staples the ticket, checks Gatekeeper with `spctl`, and re-zips the stapled app.
- No Accessibility permission: Manopola does not synthesize input events.

### 9.2 Input Monitoring

Whether macOS requires Input Monitoring for opening a non-keyboard, non-pointer HID device — seized or not — must be verified in milestone M1. The code handles both outcomes:

1. If `IOHIDManagerOpen` returns `kIOReturnNotPermitted`, call `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` once, which shows the system prompt.
2. Call `onAccessDenied`; the menu shows "Allow Input Monitoring…", which opens `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`.
3. When the app becomes active again, retry the open.

## 10. Edge Cases

| Situation | Behavior |
|---|---|
| Dial not paired / switched off | icon dimmed, menu says "Not Connected"; HID manager stays open and matches it when it appears |
| Dial idle sleep and wake-up | removal and matching callbacks fire; haptic configuration re-sent on match and after ≥ 15 s silence |
| Mac sleeps and wakes | HID session rebuilt 1 s after `didWakeNotification` |
| Button held while Dial disconnects | `reset()`; no mute toggle |
| Default output changes mid-turn | next detent applies to the new device |
| Output without software volume | rotation ignored, icon disabled, menu shows "Volume: not adjustable" |
| Output without hardware mute | emulated mute (§7.4) |
| No output device at all | `state == nil`; rotation and press ignored |
| Volume changed by keyboard while overlay visible | overlay is not updated (it only reflects Dial changes) and fades on its own |
| Two Dials connected | first matched device is used; others ignored and logged |
| Dial held by another process (another Dial utility, a second Manopola) | state `.inUseElsewhere`, icon dimmed, menu says "In Use by Another App"; retried when the menu opens or the app becomes active (§7.2) |
| Settings changed while disconnected | stored; applied on next match |

## 11. Testing

### 11.1 Unit Tests (Swift Testing)

Target `ManopolaTests`, added to `project.yml` in milestone M2. The `Manopola` target lists it under `scheme.testTargets`, so `xcodebuild -scheme Manopola test` runs it:

```yaml
  ManopolaTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests/ManopolaTests
    dependencies:
      - target: Manopola
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.panjas.ManopolaTests
        GENERATE_INFOPLIST_FILE: YES
```

The tests run hosted in the app. `main.swift` detects the test host through the `XCTestConfigurationFilePath` environment variable and then does not install `AppDelegate`, so a test run neither seizes the Dial nor touches audio.

| Suite | Covers |
|---|---|
| `DialReportTests` | parsing both buffer shapes; clockwise `01 00 01 00 …` → +1; counter-clockwise `01 00 FF FF …` → −1; pressed `01 01 00 00 …`; wrong ID or length → `nil`; exact bytes of the feature report (36 detents, haptics on → `01 24 00 00 03 00 00 00`) and of the three manual patterns in §7.1 |
| `VolumeStepperTests` | all vectors in §7.3, clamping, fine step |
| `SettingsTests` | defaults from §7.7, round trip of every key, out-of-range fallback, `onChange` per write; each test uses a private `UserDefaults` suite |
| `DialControllerTests` | gesture rules 1–4 with fake `AudioControlling` / `HapticFeedback` and an injected clock: short press toggles mute; press+turn steps by quarter and does not toggle; turn while muted unmutes; end stop fires and is rate-limited; reverse direction; `canSetVolume == false` ignores rotation; `reset()` mid-press |

`DialDevice`, `AudioOutput` and the UI are thin adapters over system frameworks and are covered by the manual checklist.

### 11.2 Manual Test Checklist

1. Fresh install: app starts, icon appears, Dial connects without prompts (or with one Input Monitoring prompt, per §9.2).
2. Turn slowly and fast in both directions; each detent clicks and changes volume by exactly one step.
3. Short press mutes (double click felt), press again unmutes (single click).
4. Press and turn: fine steps, no mute toggle on release.
5. Turn past 100 % and 0 %: end-stop buzz, no repeated buzzing while spinning.
6. Change volume and mute with the keyboard: icon and menu follow.
7. Connect AirPods, then disconnect: control follows the default output.
8. Select an HDMI output without volume control: disabled state.
9. Leave the Dial untouched for 15 minutes so it goes to sleep, then turn it: works, detents still click.
10. Sleep and wake the Mac: works without restarting the app.
11. Toggle every setting; detent count and haptics change immediately on the device.
12. Launch at login: survives a log out / log in.
13. Activity Monitor: 0 % CPU while idle. Measured 2026-10-18 on the M4 build: no measurable CPU time (below 0.01 s) over 60 s with the Dial connected but idle.

## 12. Project Structure and Build

```
Manopola/
├── project.yml                    XcodeGen spec (the .xcodeproj is generated, not committed)
├── Makefile                       build, test, lint, diagrams, icon, release, notarize
├── scripts/render-icon.swift      draws the app icon into AppIcon.appiconset
├── AGENTS.md / CLAUDE.md          agent instructions
├── docs/
│   ├── DESIGN.md                  this document
│   └── diagrams/                  PlantUML sources (+ rendered SVGs)
├── Sources/Manopola/
│   ├── App/                       main.swift, AppDelegate.swift
│   ├── Dial/                      DialDevice.swift, DialReport.swift, DialEvent.swift
│   ├── Control/                   DialController.swift, VolumeStepper.swift
│   ├── Audio/                     AudioOutput.swift, AudioState.swift, CoreAudioError.swift
│   ├── UI/                        StatusItemController.swift, VolumeOverlay.swift,
│   │                              SettingsWindowController.swift, SettingsViewController.swift,
│   │                              VolumePresentation.swift
│   ├── Support/                   Settings.swift, LoginItem.swift, Log.swift
│   └── Resources/                 Assets.xcassets
└── Tests/ManopolaTests/           Swift Testing suites (from M2)
```

`HapticWaveform`, `DialInputReport` live in `DialReport.swift`; `AudioControlling` and `HapticFeedback` in `DialController.swift`; `ControlSettings` in `Settings.swift` (alone there in M3; `AppDelegate` passes the §7.7 defaults until the `Settings` store arrives in M4).

Build, through the `Makefile`:

```sh
make build        # xcodegen generate, Debug build
make test         # unit tests
make lint         # swift-format lint --strict
make diagrams     # plantuml -tsvg docs/diagrams/*.puml
make icon         # re-render the app icon
make release      # Developer ID signed universal build, zipped (§9.1)
make notarize     # notarize, staple, Gatekeeper check
```

## 13. Implementation Plan

| Milestone | Content | Exit criterion |
|---|---|---|
| **M0 Scaffold** (done) | XcodeGen project, AppKit entry point, status item with Quit, repo conventions | `xcodegen generate` and build succeed; icon appears |
| **M1 HID spike** | `DialReport`, `DialDevice`, `Log`; log events only; debug-only `DiagnosticsMenu` to switch detents and haptics and play each haptic pattern (removed in M4) | rotation and press logged; §14 items R1–R4 answered and this document updated |
| **M2 Audio** | `AudioOutput`, `VolumeStepper`, test target, `DialReportTests`, `VolumeStepperTests`; `DiagnosticsMenu` gains volume step and mute toggle | volume/mute of the default device readable and settable; external changes observed; tests green |
| **M3 Control** | `DialController`, `DialControllerTests`, wiring in `AppDelegate` | volume and mute fully controllable with the Dial |
| **M4 UI** | `StatusItemController`, `VolumeOverlay`, `VolumePresentation`, `Settings`, `SettingsWindowController`, `LoginItem`, `SettingsTests`; `DiagnosticsMenu` removed | checklist items 1–12 pass |
| **M5 Release** | app icon (`scripts/render-icon.swift`: aluminum knob with an amber volume scale on a dark tile), README, `Makefile` with Developer ID signing and notarization, version 1.0.0 | checklist item 13 passes; notarized build runs on a second Mac |

## 14. Risks and Open Questions

| ID | Item | Plan |
|---|---|---|
| R1 | Does the input report buffer on macOS include the report ID byte? | parser accepts both; M1 logs the actual shape and the doc is updated. **Answered 2026-10-18:** 9 bytes with the report ID first, in every report of a live debug capture (§7.1) |
| R2 | Does seizing work for the Dial, and does any open mode require Input Monitoring? | M1 tests seize and shared mode on a clean user account; §9.2 is the fallback. **Partly answered 2026-10-18:** on the developer account the seized open succeeds and reports arrive without an Input Monitoring prompt, while `IOHIDCheckAccess` reports "unknown". The seize is exclusive: a second process gets `kIOReturnExclusiveAccess` (`0xe00002c5`) in seized and in shared mode, yet its matching callback still fires. Clean-account test still open |
| R3 | Is the delta exactly ±1 per detent after setting the resolution multiplier? | M1 logs raw deltas at 18 and 72 detents; if not, `DialDevice` divides by `3600 / R` with an accumulator. **Confirmed for 36 detents 2026-10-18:** every Dial-driven volume change was exactly one 2 % step, and a debug capture shows only ±1 deltas, also on fast turns. 18 and 72 still to check |
| R4 | Do manual trigger ordinal 4 (buzz) and repeat/retrigger work as specified? | M1 tries each pattern; fallback for end stop is click with repeat 2 at 40 ms. **Answered 2026-10-18:** all manual triggers are accepted. Click with repeat and retrigger works (mute double click felt). Buzz does not end on its own: ordinal 4 is Buzz Continuous and keeps vibrating until the next haptic, so the end stop needs the click fallback or an explicit Stop. **Decided and verified 2026-10-18:** short buzz, Stop trigger after 100 ms (§7.2). Stop (ordinal 2) works as a manual trigger; every buzz in a capture was followed by an accepted Stop about 135 ms later, and the buzz ends by itself |
| R5 | Haptic configuration lost after Dial idle sleep | re-send policy in §7.2 |
| R6 | Hardware is discontinued | buy a second used unit as a spare once M3 works |

## 15. Future Ideas

- Dial battery level via the Bluetooth LE Battery Service (`0x180F`) through CoreBluetooth; the HID descriptor has no battery usage.
- Modes switchable by long press: media transport, scrolling, output device selection.
- Per-device step size.
- Input (microphone) mute as an alternative press action.

## 16. References

- Mac Dial — https://github.com/andreasjhkarlsson/mac-dial (fork: https://github.com/drashna/mac-dial); Accessibility reset after updates: issue #12
- OrbitLauncher Surface Dial preview — https://github.com/S7venYoung/RingLauncher/releases/tag/v0.2.0-dial.1 (`Sources/OrbitLauncher/SurfaceDialManager.swift`)
- surface-dial-linux — https://github.com/daniel5151/surface-dial-linux (`notes/HID_Report_Descriptor.txt`, `src/dial_device/haptics.rs`)
- USB HID Usage Tables: Generic Desktop page (Dial `0x37`, Resolution Multiplier `0x48`), Haptics page `0x0E`
- Push to Hush — https://github.com/heikopanjas/push-to-hush (`CoreAudio.swift`)
