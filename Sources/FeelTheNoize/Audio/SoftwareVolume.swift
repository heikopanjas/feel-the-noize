import CoreAudio
import Foundation
import Synchronization

/// Software volume for an output device that has no volume control of its own (Docs/DESIGN.md §7.9).
///
/// A process tap takes the audio other apps send to the device and keeps it from reaching the hardware. A private
/// aggregate device made of that tap and the device plays it into the device again, scaled by the gain. The IO block is
/// the only code in the app that runs off the main actor; it shares the gain through atomics, without locks.
final class SoftwareVolume: SoftwareVolumeControlling {
    static let aggregateUIDPrefix = "com.panjas.FeelTheNoize.software-volume."

    /// The device being controlled, or `nil` while stopped.
    private(set) var deviceUID: String?

    /// 0…1 as shown to the user; mapped to an amplitude by `SoftwareGain`.
    var level: Float = 1 {
        didSet {
            self.gain.setTarget(SoftwareGain.amplitude(for: self.level))
        }
    }

    var isRunning: Bool {
        return self.deviceUID != nil
    }

    private let gain = Gain()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var tapUUID = UUID()

    func start(deviceUID: String, level: Float) throws -> Void {
        self.stop()
        self.level = level
        self.gain.reset(to: SoftwareGain.amplitude(for: level))
        do {
            try self.createTap(for: deviceUID)
            try self.createAggregate(for: deviceUID)
            try self.startIO()
            self.deviceUID = deviceUID
            Log.audio.info("Software volume started for \(deviceUID, privacy: .public)")
        }
        catch {
            self.stop()
            throw error
        }
    }

    /// Reverses `start` step by step, so it also cleans up after a start that failed halfway.
    func stop() -> Void {
        if let ioProcID = self.ioProcID {
            AudioDeviceStop(self.aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(self.aggregateID, ioProcID)
        }
        self.ioProcID = nil
        if self.aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(self.aggregateID)
        }
        self.aggregateID = AudioObjectID(kAudioObjectUnknown)
        if self.tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(self.tapID)
        }
        self.tapID = AudioObjectID(kAudioObjectUnknown)
        if let deviceUID = self.deviceUID {
            Log.audio.info("Software volume stopped for \(deviceUID, privacy: .public)")
        }
        self.deviceUID = nil
    }

    // MARK: - Setup

    private func createTap(for deviceUID: String) throws -> Void {
        // Leaving Feel the Noize itself out of the tap keeps its own playback into the aggregate from feeding back.
        let ownProcess = try CoreAudioProperty.readOwnProcessObject()
        let description = CATapDescription(excludingProcesses: [ownProcess], deviceUID: deviceUID, stream: 0)
        description.name = "Feel the Noize Software Volume"
        description.isPrivate = true
        // The tapped apps no longer reach the hardware directly; only the scaled copy does.
        description.muteBehavior = .muted
        self.tapUUID = description.uuid
        var tapID = AudioObjectID(kAudioObjectUnknown)
        try AudioHardwareCreateProcessTap(description, &tapID).throwIfError("Creating the process tap")
        self.tapID = tapID
    }

    private func createAggregate(for deviceUID: String) throws -> Void {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Feel the Noize Software Volume",
            kAudioAggregateDeviceUIDKey: Self.aggregateUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: self.tapUUID.uuidString, kAudioSubTapDriftCompensationKey: true]]
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        try AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID).throwIfError("Creating the aggregate device")
        self.aggregateID = aggregateID
    }

    private func startIO() throws -> Void {
        let inputs = try CoreAudioProperty.readBufferChannelCounts(of: self.aggregateID, scope: kAudioObjectPropertyScopeInput)
        let outputs = try CoreAudioProperty.readBufferChannelCounts(of: self.aggregateID, scope: kAudioObjectPropertyScopeOutput)
        Log.audio.info("Software volume buffers: input channels \(inputs, privacy: .public), output channels \(outputs, privacy: .public)")
        let tapBufferIndex = try Self.tapBufferIndex(inputs: inputs, outputs: outputs)

        var ioProcID: AudioDeviceIOProcID?
        try AudioDeviceCreateIOProcIDWithBlock(&ioProcID, self.aggregateID, nil, Self.makeIOBlock(gain: self.gain, tapBufferIndex: tapBufferIndex))
            .throwIfError("Creating the IO proc")
        self.ioProcID = ioProcID
        try AudioDeviceStart(self.aggregateID, ioProcID).throwIfError("Starting the aggregate device")
    }

    /// The aggregate lists the sub-device's own inputs first and the tap last.
    private static func tapBufferIndex(inputs: [Int], outputs: [Int]) throws -> Int {
        guard let index = inputs.indices.last else {
            throw CoreAudioError(status: kAudioHardwareUnspecifiedError, operation: "Finding the tap and output buffers")
        }
        guard outputs.isEmpty == false else {
            throw CoreAudioError(status: kAudioHardwareUnspecifiedError, operation: "Finding the tap and output buffers")
        }
        return index
    }

    // MARK: - Real-Time Processing

    /// Runs on the HAL IO thread: no allocation, no locks, no logging. Copies the tap buffer into the first output buffer,
    /// scaled by the gain and ramped across the buffer so level changes do not click; other output buffers stay silent.
    private nonisolated static func makeIOBlock(gain: Gain, tapBufferIndex: Int) -> AudioDeviceIOBlock {
        return { _, inputData, _, outputData, _ in
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            let outputs = UnsafeMutableAudioBufferListPointer(outputData)
            let (from, to) = gain.advance()
            var source: AudioBuffer?
            if tapBufferIndex < inputs.count {
                source = inputs[tapBufferIndex]
            }
            for index in 0 ..< outputs.count {
                if index == 0 {
                    Self.render(source, into: outputs[index], from: from, to: to)
                }
                else {
                    Self.silence(outputs[index])
                }
            }
        }
    }

    /// Copies `source` into `destination`, scaled from `from` to `to` across the buffer; silence without a source.
    private nonisolated static func render(_ source: AudioBuffer?, into destination: AudioBuffer, from: Float, to: Float) -> Void {
        guard let destinationData = destination.mData else {
            return
        }
        guard let source = source else {
            Self.silence(destination)
            return
        }
        guard let sourceData = source.mData else {
            Self.silence(destination)
            return
        }
        let outputSamples = Int(destination.mDataByteSize) / MemoryLayout<Float>.size
        let output = destinationData.assumingMemoryBound(to: Float.self)
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

    private nonisolated static func silence(_ buffer: AudioBuffer) -> Void {
        guard let data = buffer.mData else {
            return
        }
        let samples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        data.assumingMemoryBound(to: Float.self).update(repeating: 0, count: samples)
    }
}

/// The gain shared between the main actor, which sets the target, and the IO thread, which ramps towards it.
/// Floats are stored as their bit patterns because `Atomic` needs an integer representation.
private nonisolated final class Gain: Sendable {
    private let target = Atomic<UInt32>(Float(1).bitPattern)
    private let current = Atomic<UInt32>(Float(1).bitPattern)

    func setTarget(_ amplitude: Float) -> Void {
        self.target.store(amplitude.bitPattern, ordering: .relaxed)
    }

    func reset(to amplitude: Float) -> Void {
        self.target.store(amplitude.bitPattern, ordering: .relaxed)
        self.current.store(amplitude.bitPattern, ordering: .relaxed)
    }

    /// IO thread only: the amplitude at the start and end of this buffer.
    func advance() -> (from: Float, to: Float) {
        let to = Float(bitPattern: self.target.load(ordering: .relaxed))
        let from = Float(bitPattern: self.current.exchange(to.bitPattern, ordering: .relaxed))
        return (from: from, to: to)
    }
}
