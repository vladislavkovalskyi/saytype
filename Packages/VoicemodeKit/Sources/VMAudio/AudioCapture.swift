@preconcurrency import AVFoundation
import Foundation

/// Captures the default microphone as 16 kHz mono Float32, the format Whisper expects.
///
/// The tap runs on a real-time audio thread, so nothing here is actor-isolated:
/// buffers leave through an `AsyncStream` and state is guarded by a lock.
public final class AudioCapture: @unchecked Sendable {
    public struct Chunk: Sendable {
        public let samples: [Float]
        /// Loudness of the chunk mapped from −60…0 dBFS to 0…1. Zero means silence.
        public let level: Float
    }

    public enum CaptureError: Error {
        case noInputDevice
        case converterUnavailable
    }

    public static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var continuation: AsyncStream<Chunk>.Continuation?
    private var configObserver: NSObjectProtocol?

    public init() {}

    deinit {
        stop()
    }

    /// Starts capturing. The stream finishes when `stop()` is called.
    public func start() throws -> AsyncStream<Chunk> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: Chunk.self, bufferingPolicy: .unbounded)
        lock.withLock { self.continuation = continuation }
        try installTap()
        engine.prepare()
        try engine.start()
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            // The input device changed (headphones, AirPods). The old tap format is stale.
            try? self?.restart()
        }
        return stream
    }

    public func stop() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
    }

    private func restart() throws {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try installTap()
        engine.prepare()
        try engine.start()
    }

    private func installTap() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw CaptureError.noInputDevice
        }
        guard
            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else {
            throw CaptureError.converterUnavailable
        }
        let ratio = Self.sampleRate / inputFormat.sampleRate
        input.installTap(onBus: 0, bufferSize: 1_600, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var fed = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if fed {
                    status.pointee = .noDataNow
                    return nil
                }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let channel = output.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            let chunk = Chunk(samples: samples, level: Self.level(of: samples))
            self.lock.withLock { _ = self.continuation?.yield(chunk) }
        }
    }

    /// RMS loudness mapped to 0…1 over a −60…0 dBFS range.
    public static func level(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(1, max(0, (db + 60) / 60))
    }
}
