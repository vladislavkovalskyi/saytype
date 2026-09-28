@preconcurrency import AVFoundation
import Foundation
import VMCatch
import VMCore

/// Captures a microphone as 16 kHz mono Float32, the format Whisper expects.
///
/// Every recording gets a fresh `AVAudioEngine`. A long-lived one keeps the input format it saw
/// first, so a microphone that changed rate while saytype was idle made the next tap raise, and
/// after another app's voice call it stayed deaf until relaunch. The engine's lifecycle runs on
/// `queue`; the tap runs on a real-time audio thread and hands chunks to an `AsyncStream`
/// under `lock`. Every engine call goes through `guarded`, so an Objective-C exception from
/// AVFoundation becomes a Swift error instead of unwinding through Swift code.
public final class AudioCapture: @unchecked Sendable {
    public struct Chunk: Sendable {
        public let samples: [Float]
        /// Loudness of the chunk mapped from −60…0 dBFS to 0…1. Zero means silence.
        public let level: Float
    }

    public enum CaptureError: Error {
        case noInputDevice
        case converterUnavailable
        /// AVAudioEngine raised an Objective-C exception; its reason.
        case engine(String)
    }

    public static let sampleRate: Double = 16_000

    private let queue = DispatchQueue(label: "dev.kovalskyi.saytype.capture")
    private let lock = NSLock()
    /// On `queue`: the running engine, its configuration-change observer, and the watchdog that
    /// moves a recording whose buffers stopped to a fresh engine.
    private var engine: AVAudioEngine?
    private var configObserver: NSObjectProtocol?
    private var watchdog: DispatchSourceTimer?
    private var relaunches = 0
    /// Under `lock`: where the tap delivers, and when it last did.
    private var continuation: AsyncStream<Chunk>.Continuation?
    private var lastBuffer = DispatchTime.now()
    private var flowing = false

    /// Buffers missing this long mean the engine stalled; before the first buffer the device
    /// gets longer, since Bluetooth headsets take about a second to switch to their microphone.
    static let stallLimit = 0.6
    static let firstBufferLimit = 2.0
    static let relaunchLimit = 3

    /// UID of the microphone to use; `nil` or a disconnected device means the system default.
    public var deviceUID: String? {
        get { lock.withLock { _deviceUID } }
        set { lock.withLock { _deviceUID = newValue } }
    }
    private var _deviceUID: String?

    public init() {}

    deinit {
        stop()
    }

    /// Starts capturing. The stream finishes when `stop()` is called; the chunks captured before
    /// that are still delivered, so a reader that keeps iterating gets every one of them.
    public func start() throws -> AsyncStream<Chunk> {
        let (stream, continuation) = AsyncStream.makeStream(of: Chunk.self, bufferingPolicy: .unbounded)
        try queue.sync {
            stopWatchdog()
            teardown()
            finish()
            lock.withLock { self.continuation = continuation }
            relaunches = 0
            do {
                try launch()
                startWatchdog()
            } catch {
                teardown()
                finish()
                throw error
            }
        }
        return stream
    }

    public func stop() {
        queue.sync {
            stopWatchdog()
            teardown()
            finish()
        }
    }

    /// A fresh engine for a new recording. On `queue`.
    private func launch() throws {
        let engine = AVAudioEngine()
        // Owned before it starts, so a failed start is torn down with it.
        self.engine = engine
        lock.withLock {
            lastBuffer = .now()
            flowing = false
        }
        try tap(engine)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self, weak engine] _ in
            // Posted on any thread; the restart runs on the capture's own queue.
            self?.queue.async { self?.restart(after: engine) }
        }
    }

    /// Puts `engine` on the chosen device, taps it in the device's own format and starts it.
    /// On `queue`.
    private func tap(_ engine: AVAudioEngine) throws {
        try Self.guarded { selectDevice(engine) }
        let input = engine.inputNode
        // The device's format, not the node's output format: after the device is selected the
        // output format can still say 48 kHz for a microphone at 44.1, and a tap in it gets
        // no buffers at all.
        let format = try Self.guarded { input.inputFormat(forBus: 0) }
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw CaptureError.noInputDevice
        }
        let converter = try Converter(from: format)
        try Self.guarded {
            input.installTap(onBus: 0, bufferSize: 1_600, format: format) { [weak self] buffer, _ in
                guard let self, let samples = converter.convert(buffer) else { return }
                let chunk = Chunk(samples: samples, level: Self.level(of: samples))
                self.lock.withLock {
                    self.lastBuffer = .now()
                    self.flowing = true
                    _ = self.continuation?.yield(chunk)
                }
            }
            engine.prepare()
            try engine.start()
        }
    }

    /// The device or its format changed during a recording (headphones, AirPods, another app
    /// changing the rate, or the device selection settling after the start): the same engine
    /// is tapped again in the new format and the stream goes on. Only when that fails does a
    /// fresh engine take over; a fresh one for every change would announce a change of its own
    /// and restart forever. If neither starts, the stream ends and the dictation keeps what it
    /// has. On `queue`.
    private func restart(after changed: AVAudioEngine?) {
        guard let engine, changed === engine else { return }
        do {
            try Self.guarded {
                engine.inputNode.removeTap(onBus: 0)
                if engine.isRunning { engine.stop() }
            }
            try tap(engine)
        } catch {
            teardown()
            do {
                try launch()
            } catch {
                teardown()
                finish()
            }
        }
    }

    /// A device can stop delivering without any error: after a rate change in the middle of a
    /// recording the notification comes while the engine still reads the old format, and the
    /// retapped engine runs but gets nothing. The watchdog notices and a fresh engine takes over.
    /// On `queue`.
    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in self?.checkFlow() }
        timer.resume()
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    private func checkFlow() {
        guard engine != nil, relaunches < Self.relaunchLimit else { return }
        let (last, flowing) = lock.withLock { (lastBuffer, self.flowing) }
        let silent = Double(DispatchTime.now().uptimeNanoseconds - last.uptimeNanoseconds) / 1e9
        guard silent > (flowing ? Self.stallLimit : Self.firstBufferLimit) else { return }
        relaunches += 1
        teardown()
        do {
            try launch()
        } catch {
            stopWatchdog()
            teardown()
            finish()
        }
    }

    /// Stops and drops the engine. On `queue`.
    private func teardown() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        guard let engine else { return }
        self.engine = nil
        try? Self.guarded {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
    }

    private func finish() {
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
    }

    /// Points the engine's input unit at the chosen device before its format is read. Setting
    /// the device the unit already uses would only announce a configuration change.
    private func selectDevice(_ engine: AVAudioEngine) {
        guard let device = AudioDevices.resolve(uid: deviceUID), let unit = engine.inputNode.audioUnit else { return }
        var current = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &current, &size) == noErr, current == device.id { return }
        var id = device.id
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    /// Runs `body`, turning an Objective-C exception it raises into `CaptureError.engine`.
    static func guarded<T>(_ body: () throws -> T) throws -> T {
        var result: Result<T, Error>?
        if let exception = VMCatchException({ result = Result { try body() } }) {
            throw CaptureError.engine(exception.reason ?? exception.name.rawValue)
        }
        return try result!.get()
    }

    /// RMS loudness mapped to 0…1 over a −60…0 dBFS range.
    public static func level(of samples: [Float]) -> Float {
        Loudness.level(rms: Loudness.rms(samples[...]))
    }
}

/// Resamples the tap's buffers to 16 kHz mono, on the audio thread, one buffer at a time.
private final class Converter: @unchecked Sendable {
    private let target: AVAudioFormat
    private var converter: AVAudioConverter

    init(from format: AVAudioFormat) throws {
        guard
            let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioCapture.sampleRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: format, to: target)
        else {
            throw AudioCapture.CaptureError.converterUnavailable
        }
        self.target = target
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        // A buffer in another format rebuilds the converter instead of being resampled at the
        // wrong rate, which Whisper would hear as sped-up or slowed-down speech.
        if converter.inputFormat != buffer.format {
            guard let rebuilt = AVAudioConverter(from: buffer.format, to: target) else { return nil }
            converter = rebuilt
        }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
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
        guard error == nil, let channel = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
