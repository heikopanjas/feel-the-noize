import CoreAudio

/// A failed Core Audio call, ported from Push to Hush.
struct CoreAudioError: Error, CustomStringConvertible {
    let status: OSStatus
    let operation: String

    var description: String {
        return "\(self.operation) failed: \(Self.fourCharCode(self.status)) (\(self.status))"
    }

    /// Core Audio statuses are mostly four-character codes such as 'who?'; plain numbers are shown as such.
    private static func fourCharCode(_ status: OSStatus) -> String {
        let value = UInt32(bitPattern: status)
        let bytes = [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
        if bytes.allSatisfy({ (0x20 ... 0x7E).contains($0) }) == false {
            return "unknown error"
        }
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }
}

extension OSStatus {
    func throwIfError(_ operation: String) throws -> Void {
        guard self == noErr else {
            throw CoreAudioError(status: self, operation: operation)
        }
    }
}
