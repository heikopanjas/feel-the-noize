# Manopola

A macOS menu bar app that turns a Microsoft Surface Dial into a hardware volume knob.

- Turn the Dial to change the volume of the current output device, with a haptic click per step.
- Press the Dial to mute or unmute.
- Hold and turn for fine adjustment.

No Accessibility permission, no third-party dependencies, no network access.

## Requirements

- macOS 15.4 or later, Apple silicon or Intel
- Microsoft Surface Dial, paired via System Settings → Bluetooth

## Installation

1. Download `Manopola-1.0.0.zip` from the releases and unzip it.
2. Move `Manopola.app` to `/Applications` and open it. The app is notarized, so it opens without warnings.
3. Pair the Dial if you have not yet: hold the pairing button next to the batteries for about 5 seconds until the light flashes, then click Connect in System Settings → Bluetooth.

Manopola lives in the menu bar only; it has no Dock icon. Turn on "Launch at login" in Settings to start it automatically.

## Usage

| Gesture | Action |
|---|---|
| Turn | Volume up or down by one step per detent |
| Turn while muted | Unmute, then step |
| Short press | Mute or unmute; a double click confirms mute, a single click unmute |
| Press and turn | Fine adjustment, a quarter step per detent; no mute on release |
| Turn past 0 % or 100 % | A short buzz marks the end stop |

Manopola always controls the current default output device and follows it when it changes, for example when AirPods connect. Volume and mute changes made with the keyboard or Control Center show up in the menu bar icon right away.

The menu bar icon shows the volume level and mute state. It is dimmed while the Dial is not connected or the output device has no software volume control, as with many HDMI and DisplayPort outputs.

### Settings

Settings has two tabs.

**General**

| Setting | Values | Default |
|---|---|---|
| Detents per turn | 18, 24, 36, 48, 72 | 36 |
| Volume step | 1 %, 2 %, 3 %, 5 % | 2 % |
| Reverse direction | on or off | off |
| Haptic detents | on or off | on |
| Show volume overlay | on or off | on |
| Launch at login | on or off | off |

**Devices** lists every audio output with its connection type and whether it supports volume control and mute. Tick the devices the Dial should work with. New devices are ticked automatically. When the current output is unticked, the Dial does nothing and the menu bar icon dims. Devices that were connected before stay in the list while they are away, so you can set them up in advance. Devices without volume control can only be muted; devices with neither volume nor mute cannot be selected.

### Troubleshooting

- **The Dial does not respond.** Check that it is connected in System Settings → Bluetooth. After a while without use the Dial sleeps; turn it once to wake it.
- **"Allow Input Monitoring…" appears in the menu.** macOS blocked access to the Dial. Choose the item, allow Manopola under Input Monitoring, then reopen the app.
- **Turning does nothing on this output.** The device has no software volume control; adjust it on the device itself.

## Building

Requires Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and xcbeautify.

```sh
brew install xcodegen xcbeautify
make build      # generate the project and build Debug
make run        # build and launch
make test       # run the unit tests
make lint       # swift-format lint
```

Or run `xcodegen generate` and open the generated `Manopola.xcodeproj` in Xcode.

### Release

```sh
# once: store notary credentials in the keychain
xcrun notarytool store-credentials manopola-notary --apple-id <apple-id> --team-id 8J2G689FCZ

make release    # test, Developer ID sign, verify, zip to build/dist
make notarize   # submit, staple, Gatekeeper check, re-zip
```

`make notarize NOTARY_PROFILE=<name>` uses another stored profile.

## Design

See [`docs/DESIGN.md`](docs/DESIGN.md) for the architecture, the Surface Dial HID protocol and the Core Audio details.

## License

MIT — see [LICENSE](LICENSE).
