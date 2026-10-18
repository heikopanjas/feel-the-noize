/// Waveform ordinals from the Dial's haptic waveform list (docs/DESIGN.md §7.1).
/// Ordinals 1 and 2 are the HID-defined None and Stop; 3 maps to Click (0x1003), 4 to Buzz Continuous (0x1004).
enum HapticWaveform: UInt8 {
    case stop = 2
    case click = 3
    case buzz = 4
}

/// Decoded payload of input report 1.
struct DialInputReport: Equatable {
    let isPressed: Bool
    let delta: Int16
}

/// Pure encoder and decoder for the Surface Dial report layouts in docs/DESIGN.md §7.1.
/// All multi-byte fields are little-endian.
enum DialReport {
    static let vendorID = 0x045E
    static let productID = 0x091B
    static let reportID: UInt8 = 0x01

    private static let inputPayloadLength = 8
    private static let maximumResolutionMultiplier = 3600

    /// Accepts both buffer shapes seen on macOS: 9 bytes with the report ID first, or 8 bytes with the ID stripped.
    static func parseInput(reportID: UInt32, bytes: [UInt8]) -> DialInputReport? {
        let payload: ArraySlice<UInt8>
        if bytes.count == inputPayloadLength + 1, bytes[0] == self.reportID {
            payload = bytes.dropFirst()
        }
        else if bytes.count == inputPayloadLength, reportID == UInt32(self.reportID) {
            payload = bytes[...]
        }
        else {
            return nil
        }

        let start = payload.startIndex
        let isPressed = payload[start] & 0x01 != 0
        let delta = Int16(bitPattern: UInt16(payload[start + 1]) | UInt16(payload[start + 2]) << 8)
        return DialInputReport(isPressed: isPressed, delta: delta)
    }

    /// Feature report 1, including the report ID byte.
    static func hapticConfiguration(detentsPerRevolution: Int, hapticsEnabled: Bool) -> [UInt8] {
        let multiplier = UInt16(min(max(detentsPerRevolution, 0), maximumResolutionMultiplier))
        let autoTrigger: HapticWaveform = hapticsEnabled ? .click : .stop
        return [
            reportID,
            UInt8(truncatingIfNeeded: multiplier),
            UInt8(truncatingIfNeeded: multiplier >> 8),
            0x00,  // repeat count
            autoTrigger.rawValue,
            0x00,  // waveform cutoff time
            0x00,  // retrigger period, low byte
            0x00  // retrigger period, high byte
        ]
    }

    /// Output report 1, including the report ID byte.
    static func manualTrigger(waveform: HapticWaveform, repeatCount: UInt8, retriggerMilliseconds: UInt16) -> [UInt8] {
        [
            reportID,
            repeatCount,
            waveform.rawValue,
            UInt8(truncatingIfNeeded: retriggerMilliseconds),
            UInt8(truncatingIfNeeded: retriggerMilliseconds >> 8)
        ]
    }
}
