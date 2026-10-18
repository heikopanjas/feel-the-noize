import CoreAudio
import Foundation
import Synchronization

/// Software volume for an output device that has no volume control of its own (docs/DESIGN.md §7.9).
///
/// A process tap takes the audio other apps send to the device and keeps it from reaching the hardware. A private
/// aggregate device made of that tap and the device plays it into the device again, scaled by the gain. The IO block is
/// the only code in the app that runs off the main actor; it shares the gain through atomics, without locks.
final class SoftwareVolume {
    static let aggregateUIDPrefix = "com.panjas.Manopola.software-volume."

    /// The device being controlled, or `nil` while stopped.
    private(set) var deviceUID: String?

    /// 0…1 as shown to the user; mapped to an amplitude by `SoftwareGain`.
    var level: Float = 1 {
        didSet { gain.setTarget(SoftwareGain.amplitude(for: level)) }
    }

    var isRunning: Bool {
        deviceUID != nil
    }

    private let gain = Gain()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    func start(deviceUID: String, level: Float) throws {
        stop()
        self.level = level
        gain.reset(to: SoftwareGain.amplitude(for: level))
        do {
            try createTap(for: deviceUID)
            try createAggregate(for: deviceUID)
            try startIO()
            self.deviceUID = deviceUID
            Log.audio.info("Software volume started for \(deviceUID, privacy: .public)")
        }
        catch {
            stop()
            throw error
        }
    }

    /// Reverses `start` step by step, so it also cleans up after a start that failed halfway.
    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapID = AudioObjectID(kAudioObjectUnknown)
        if let deviceUID {
            Log.audio.info("Software volume stopped for \(deviceUID, privacy: .public)")
        }
        deviceUID = nil
    }

    // MARK: - Setup

    private var tapUUID = UUID()

    private func createTap(for deviceUID: String) throws {
        // Leaving Manopola itself out of the tap keeps its own playback into the aggregate from feeding back.
        let ownProcess = try CoreAudioProperty.readOwnProcessObject()
        let description = CATapDescription(excludingProcesses: [ownProcess], deviceUID: deviceUID, stream: 0)
        description.name = "Manopola Software Volume"
        description.isPrivate = true
        // The tapped apps no longer reach the hardware directly; only the scaled copy does.
        description.muteBehavior = .muted
        tapUUID = description.uuid
        var tapID = AudioObjectID(kAudioObjectUnknown)
        try AudioHardwareCreateProcessTap(description, &tapID).throwIfError("Creating the process tap")
        self.tapID = tapID
    }

    private func createAggregate(for deviceUID: String) throws {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Manopola Software Volume",
            kAudioAggregateDeviceUIDKey: Self.aggregateUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUUID.uuidString, kAudioSubTapDriftCompensationKey: true]]
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        try AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID).throwIfError("Creating the aggregate device")
        self.aggregateID = aggregateID
    }

    private func startIO() throws {
        let inputs = try CoreAudioProperty.readBufferChannelCounts(of: aggregateID, scope: kAudioObjectPropertyScopeInput)
        let outputs = try CoreAudioProperty.readBufferChannelCounts(of: aggregateID, scope: kAudioObjectPropertyScopeOutput)
        Log.audio.info("Software volume buffers: input channels \(inputs, privacy: .public), output channels \(outputs, privacy: .public)")
        // The aggregate lists the sub-device's own inputs first and the tap last.
        guard let tapBufferIndex = inputs.indices.last, !outputs.isEmpty else {
            throw CoreAudioError(status: kAudioHardwareUnspecifiedError, operation: "Finding the tap and output buffers")
        }

        var ioProcID: AudioDeviceIOProcID?
        try AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil, Self.makeIOBlock(gain: gain, tapBufferIndex: tapBufferIndex))
            .throwIfError("Creating the IO proc")
        self.ioProcID = ioProcID
        try AudioDeviceStart(aggregateID, ioProcID).throwIfError("Starting the aggregate device")
    }

    // MARK: - Real-Time Processing

    /// Runs on the HAL IO thread: no allocation, no locks, no logging. Copies the tap buffer into the first output buffer,
    /// scaled by the gain and ramped across the buffer so level changes do not click; other output buffers stay silent.
    private nonisolated static func makeIOBlock(gain: Gain, tapBufferIndex: Int) -> AudioDeviceIOBlock {
        { _, inputData, _, outputData, _ in
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            let outputs = UnsafeMutableAudioBufferListPointer(outputData)
            let (from, to) = gain.advance()

            for index in 0 ..< outputs.count {
                let destination = outputs[index]
                guard let destinationData = destination.mData else { continue }
                let outputSamples = Int(destination.mDataByteSize) / MemoryLayout<Float>.size
                let output = destinationData.assumingMemoryBound(to: Float.self)

                guard index == 0, tapBufferIndex < inputs.count, let sourceData = inputs[tapBufferIndex].mData else {
                    output.update(repeating: 0, count: outputSamples)
                    continue
                }
                let source = inputs[tapBufferIndex]
                let input = sourceData.assumingMemoryBound(to: Float.self)
                let channels = max(Int(source.mNumberChannels), 1)
                let samples = min(Int(source.mDataByteSize) / MemoryLayout<Float>.size, outputSamples)
                let frames = samples / channels

                if from == to {
                    for sample in 0 ..< samples {
                        output[sample] = input[sample] * to
                    }
                }
                else {
                    let step = (to - from) / Float(max(frames, 1))
                    for frame in 0 ..< frames {
                        let factor = from + step * Float(frame)
                        for channel in 0 ..< channels {
                            let sample = frame * channels + channel
                            output[sample] = input[sample] * factor
                        }
                    }
                }
                if samples < outputSamples {
                    (output + samples).update(repeating: 0, count: outputSamples - samples)
                }
            }
        }
    }
}

/// The gain shared between the main actor, which sets the target, and the IO thread, which ramps towards it.
/// Floats are stored as their bit patterns because `Atomic` needs an integer representation.
private nonisolated final class Gain: Sendable {
    private let target = Atomic<UInt32>(Float(1).bitPattern)
    private let current = Atomic<UInt32>(Float(1).bitPattern)

    func setTarget(_ amplitude: Float) {
        target.store(amplitude.bitPattern, ordering: .relaxed)
    }

    func reset(to amplitude: Float) {
        target.store(amplitude.bitPattern, ordering: .relaxed)
        current.store(amplitude.bitPattern, ordering: .relaxed)
    }

    /// IO thread only: the amplitude at the start and end of this buffer.
    func advance() -> (from: Float, to: Float) {
        let to = Float(bitPattern: target.load(ordering: .relaxed))
        let from = Float(bitPattern: current.exchange(to.bitPattern, ordering: .relaxed))
        return (from, to)
    }
}
