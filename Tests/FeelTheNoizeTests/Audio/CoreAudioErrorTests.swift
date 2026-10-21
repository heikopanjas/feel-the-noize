import CoreAudio
import Testing

@testable import FeelTheNoize

struct CoreAudioErrorTests {
    @Test(
        "Four-character codes are shown as such, other statuses as unknown",
        arguments: [
            (kAudioHardwareBadDeviceError, "Reading the volume failed: '!dev' (560227702)"),
            (kAudioHardwareUnknownPropertyError, "Reading the volume failed: 'who?' (2003332927)"),
            (OSStatus(-50), "Reading the volume failed: unknown error (-50)"),
            (OSStatus(1), "Reading the volume failed: unknown error (1)")
        ] as [(OSStatus, String)])
    func description(status: OSStatus, expected: String) -> Void {
        let error = CoreAudioError(status: status, operation: "Reading the volume")
        #expect(error.description == expected)
    }

    @Test func noErrDoesNotThrow() -> Void {
        #expect(throws: Never.self) {
            try noErr.throwIfError("Reading the volume")
        }
    }

    @Test func otherStatusesThrowWithTheOperation() -> Void {
        let error = #expect(throws: CoreAudioError.self) {
            try kAudioHardwareNotRunningError.throwIfError("Starting the aggregate device")
        }
        #expect(error?.status == kAudioHardwareNotRunningError)
        #expect(error?.operation == "Starting the aggregate device")
    }
}
