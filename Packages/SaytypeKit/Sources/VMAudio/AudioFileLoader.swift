@preconcurrency import AVFoundation
import Foundation

public enum AudioFileLoader {
    public enum LoadError: Error {
        case unreadable(URL)
    }

    /// Reads any audio file AVFoundation understands as 16 kHz mono Float32.
    public static func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard
            let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioCapture.sampleRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: source, to: target),
            let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length))
        else {
            throw LoadError.unreadable(url)
        }
        try file.read(into: input)
        let capacity = AVAudioFrameCount(Double(input.frameLength) * AudioCapture.sampleRate / source.sampleRate) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw LoadError.unreadable(url)
        }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        guard let channel = output.floatChannelData?[0] else { throw LoadError.unreadable(url) }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
