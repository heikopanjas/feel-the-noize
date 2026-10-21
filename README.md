# Feel the Noize

A macOS menu bar app that turns a Microsoft Surface Dial into a hardware volume knob.

- Turn the Dial to change the volume of the current output device, with a haptic click per step.
- Press the Dial to mute or unmute.
- Hold and turn for fine adjustment.

No Accessibility permission, no third-party dependencies, no network access.

## Requirements

- macOS 15.4 or later, Apple silicon or Intel
- Microsoft Surface Dial, paired via System Settings → Bluetooth

## Installation

1. Download `FeelTheNoize-1.2.0.zip` from the releases and unzip it.
2. Move `Feel the Noize.app` to `/Applications` and open it. The app is notarized, so it opens without warnings.
3. Pair the Dial if you have not yet: hold the pairing button next to the batteries for about 5 seconds until the light flashes, then click Connect in System Settings → Bluetooth.

Feel the Noize lives in the menu bar only; it has no Dock icon. Turn on "Launch at login" in Settings to start it automatically.

## Usage

| Gesture | Action |
|---|---|
| Turn | Volume up or down by one step per detent |
| Turn while muted | Unmute, then step |
| Short press | Mute or unmute; a double click confirms mute, a single click unmute |
| Press and turn | Fine adjustment, a quarter step per detent; no mute on release |
| Turn past 0 % or 100 % | A short buzz marks the end stop |

Feel the Noize always controls the current default output device and follows it when it changes, for example when AirPods connect. Volume and mute changes made with the keyboard or Control Center show up in the menu bar icon right away.

The menu bar icon is a knob, so it is easy to tell apart from the system's speaker icon; its pointer shows the volume level, and a slash shows mute. Choose its style, Arc, Ring or Dots, in Settings. Its menu also shows whether the Dial is connected and its battery level, which macOS asks permission to read over Bluetooth the first time. It is dimmed while the Dial is not connected or the output device has no software volume control, as with many HDMI and DisplayPort outputs.

### Settings

Settings has two tabs.

**General**

| Setting | Values | Default |
|---|---|---|
| Detents per turn | 18, 24, 36, 48, 72 | 36 |
| Volume step | 1 %, 2 %, 3 %, 5 % | 2 % |
| Icon style | Arc, Ring, Dots | Arc |
| Reverse direction | on or off | off |
| Haptic detents | on or off | on |
| Keep Dial awake while the Mac is in use | on or off | on |
| Show volume overlay | on or off | on |
| Launch at login | on or off | off |

On its own, the Dial goes to sleep about 5 minutes after you last touch it, and the next turn only wakes it, which takes about 1.5 seconds. With **Keep Dial awake while the Mac is in use**, Feel the Noize keeps it ready as long as your displays are on, including while a video plays. Once the displays sleep, the Dial sleeps too, which saves its batteries. When the Dial wakes from sleep, a single click tells you it is ready.

**Devices** lists every audio output with its connection type and whether it supports volume control and mute. Tick the devices the Dial should work with. New devices are ticked automatically. When the current output is unticked, the Dial does nothing and the menu bar icon dims. Devices that were connected before stay in the list while they are away, so you can set them up in advance. Devices without volume control can only be muted, unless you turn on Software Volume for them. When the Dial cannot change anything on the current output, turning it gives a short buzz.

### Software volume

Some audio interfaces, such as the MOTU M2, and many HDMI outputs have no volume control that macOS can reach. Tick **Software Volume** for such a device in the Devices tab, and Feel the Noize adjusts the level of the audio sent to it instead.

- macOS asks once for permission to record system audio. Feel the Noize only scales the audio on its way to the device; nothing is stored or sent anywhere.
- It adds a few milliseconds of latency, also for music software such as Logic Pro playing to that device.
- If Feel the Noize quits, the device plays at full level again, so keep its hardware knob at a safe setting.
- The keyboard volume keys still cannot change these devices; the Dial and the menu can.

### Troubleshooting

- **The Dial does not respond.** Check that it is connected in System Settings → Bluetooth. After a while without use the Dial sleeps; turn it once to wake it and wait for the click. Turn on Keep Dial awake while the Mac is in use to avoid this.
- **"Allow Input Monitoring…" appears in the menu.** macOS blocked access to the Dial. Choose the item, allow Feel the Noize under Input Monitoring, then reopen the app.
- **Turning does nothing on this output.** The device has no software volume control; adjust it on the device itself.

## Building

Requires Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and xcbeautify.

```sh
brew install xcodegen xcbeautify
./build.sh build      # generate the project and build Debug
./build.sh run        # build and launch
./build.sh test       # run the unit tests
./build.sh lint       # swift-format lint
```

Or run `xcodegen generate` and open the generated `FeelTheNoize.xcodeproj` in Xcode.

### Release

```sh
# once: store an App Store Connect API key in the keychain
xcrun notarytool store-credentials developer-id-notary \
  --key AuthKey_<key-id>.p8 --key-id <key-id> --issuer <issuer-uuid>

./build.sh release    # test, Developer ID sign, verify, zip to .build/dist
./build.sh notarize   # submit, staple, Gatekeeper check, re-zip
```

`NOTARY_PROFILE=<name> ./build.sh notarize` uses another stored profile. `./build.sh help` lists all commands.

## Design

See [`Docs/DESIGN.md`](Docs/DESIGN.md) for the architecture, the Surface Dial HID protocol and the Core Audio details.

## License

MIT — see [LICENSE](LICENSE).
