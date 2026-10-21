/// Waveform ordinals from the Dial's haptic waveform list (Docs/DESIGN.md §7.1).
/// Ordinals 1 and 2 are the HID-defined None and Stop; 3 maps to Click (0x1003), 4 to Buzz Continuous (0x1004).
enum HapticWaveform: UInt8 {
    case stop = 2
    case click = 3
    case buzz = 4
}
