/// Pure encoder and decoder for the Surface Dial report layouts in Docs/DESIGN.md §7.1.
/// All multi-byte fields are little-endian.
enum DialReport {
    static let vendorID = 0x045E
    static let productID = 0x091B
    static let reportID: UInt8 = 0x01

    private static let inputPayloadLength = 8
    private static let maximumResolutionMultiplier = 3600

    static func parseInput(reportID: UInt32, bytes: [UInt8]) -> DialInputReport? {
        guard let payload = Self.payload(reportID: reportID, bytes: bytes) else {
            return nil
        }
        let start = payload.startIndex
        let isPressed = payload[start] & 0x01 != 0
        let delta = Int16(bitPattern: UInt16(payload[start + 1]) | UInt16(payload[start + 2]) << 8)
        return DialInputReport(isPressed: isPressed, delta: delta)
    }

    /// Accepts both buffer shapes seen on macOS: 9 bytes with the report ID first, or 8 bytes with the ID stripped.
    private static func payload(reportID: UInt32, bytes: [UInt8]) -> ArraySlice<UInt8>? {
        if bytes.count == Self.inputPayloadLength + 1 {
            if bytes[0] == Self.reportID {
                return bytes.dropFirst()
            }
        }
        if bytes.count == Self.inputPayloadLength {
            if reportID == UInt32(Self.reportID) {
                return bytes[...]
            }
        }
        return nil
    }

    /// Feature report 1, including the report ID byte.
    static func hapticConfiguration(detentsPerRevolution: Int, hapticsEnabled: Bool) -> [UInt8] {
        let multiplier = UInt16(min(max(detentsPerRevolution, 0), Self.maximumResolutionMultiplier))
        let autoTrigger: HapticWaveform = hapticsEnabled == true ? .click : .stop
        return [
            Self.reportID,
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
        return [
            Self.reportID,
            repeatCount,
            waveform.rawValue,
            UInt8(truncatingIfNeeded: retriggerMilliseconds),
            UInt8(truncatingIfNeeded: retriggerMilliseconds >> 8)
        ]
    }
}
