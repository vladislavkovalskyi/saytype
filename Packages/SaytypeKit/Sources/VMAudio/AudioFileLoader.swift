@preconcurrency import AVFoundation
import Foundation

public enum AudioFileLoader {
    public enum LoadError: Error {
        case unreadable(URL)
    }

    /// Reads any audio file AVFoundation understands as 16 kHz mono Float32, to the last frame.
    public static func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard
            let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioCapture.sampleRate, channels: 1, interleaved: false),
            let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(max(file.length, 1))),
            let chunk = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 16_384)
        else {
            throw LoadError.unreadable(url)
        }
        // One read may hand out fewer frames than asked (a few hundred short of the end, a
        // different number for each container), so read until the file ends.
        while file.framePosition < file.length {
            try file.read(into: chunk)
            guard chunk.frameLength > 0, let from = chunk.floatChannelData, let to = input.floatChannelData else { break }
            let count = min(Int(chunk.frameLength), Int(input.frameCapacity - input.frameLength))
            for channel in 0..<Int(source.channelCount) {
                (to[channel] + Int(input.frameLength)).update(from: from[channel], count: count)
            }
            input.frameLength += AVAudioFrameCount(count)
        }
        // Already 16 kHz mono: the samples as they are.
        if source.sampleRate == AudioCapture.sampleRate, source.channelCount == 1, let channel = input.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channel, count: Int(input.frameLength)))
        }
        guard
            let converter = AVAudioConverter(from: source, to: target),
            let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 16_384)
        else {
            throw LoadError.unreadable(url)
        }
        var samples: [Float] = []
        var fed = false
        while true {
            output.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, status in
                if fed {
                    status.pointee = .endOfStream
                    return nil
                }
                fed = true
                status.pointee = .haveData
                return input
            }
            if let error { throw error }
            if let channel = output.floatChannelData?[0] {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            }
            // The converter keeps the tail of its filter until the input ends; loop until it is out.
            guard status == .haveData else { break }
        }
        return samples
    }
}
