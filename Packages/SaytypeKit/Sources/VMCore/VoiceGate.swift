import Foundation

/// Loudness on the scale the overlay and the silence detector use: −60…0 dBFS mapped to 0…1.
public enum Loudness {
    public static func rms(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    public static func level(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        return min(1, max(0, (20 * log10(rms) + 60) / 60))
    }
}

/// Decides whether a finished recording has any voice in it, before Whisper sees it. Whisper
/// asked to decode silence invents text ("Thank you."), so silence ends as "Nothing heard".
///
/// Voice is what the silence detector calls voice, with the floor taken from the whole
/// recording: a frame of at least −45 dBFS that is 9 dB above the room. The room is the 10th
/// percentile of the frames, so a frame or two of the microphone ramping up does not pull it
/// down. The gate is permissive on purpose: 0.1 s of voice frames anywhere is enough, so a
/// quiet «да» passes; a steady room or fan, however loud, does not.
public enum VoiceGate {
    public static let frameSeconds = 0.05
    /// Voice in total, not in one run: a short «да» is two or three frames.
    public static let minimumVoiceSeconds = 0.1

    /// Levels of consecutive 50 ms frames. Frames of digital zeros, which the microphone gives
    /// while it starts, say nothing about the room and are left out.
    public static func levels(of samples: [Float], sampleRate: Double = 16_000) -> [Float] {
        frames(of: samples, sampleRate: sampleRate).compactMap(\.self)
    }

    /// Frame levels on the 0…1 scale, each `frameSeconds` long.
    public static func hasVoice(levels: [Float]) -> Bool {
        guard let threshold = threshold(levels) else { return false }
        return levels.count(where: { $0 >= threshold }) >= Int((minimumVoiceSeconds / frameSeconds).rounded())
    }

    public static func hasVoice(_ samples: [Float], sampleRate: Double = 16_000) -> Bool {
        hasVoice(levels: levels(of: samples, sampleRate: sampleRate))
    }

    /// Where the last frame of voice ends, in seconds from the start; nil when there is none.
    public static func voiceEnd(_ samples: [Float], sampleRate: Double = 16_000) -> Double? {
        let frames = frames(of: samples, sampleRate: sampleRate)
        guard let threshold = threshold(frames.compactMap(\.self)),
              let last = frames.lastIndex(where: { ($0 ?? 0) >= threshold }) else { return nil }
        return Double(last + 1) * frameSeconds
    }

    /// Levels of consecutive frames in order, nil for a frame of digital zeros.
    static func frames(of samples: [Float], sampleRate: Double) -> [Float?] {
        let frame = Int(sampleRate * frameSeconds)
        guard frame > 0 else { return [] }
        return stride(from: 0, to: samples.count - frame + 1, by: frame).map { start in
            let rms = Loudness.rms(samples[start..<(start + frame)])
            return rms > 0 ? Loudness.level(rms: rms) : nil
        }
    }

    /// The level a frame needs to be voice in a recording with these frame levels.
    static func threshold(_ levels: [Float]) -> Float? {
        guard !levels.isEmpty else { return nil }
        let room = levels.sorted()[levels.count / 10]
        return max(SilenceDetector.minimumVoice, room + SilenceDetector.voiceMargin)
    }
}
