import Foundation
import Testing
@testable import VMCore

@Suite struct VoiceGateTests {
    static let frame = VoiceGate.frameSeconds
    static let quietRoom: Float = 0.05
    static let room: Float = 0.12
    static let fan: Float = 0.38

    static func steady(_ level: Float, seconds: Double, jitter: Float = 0.02) -> [Float] {
        (0..<Int((seconds / frame).rounded())).map { level + (Float($0 % 4) - 1.5) * jitter / 1.5 }
    }

    /// Syllables with dips between them, as 50 ms frames see speech.
    static func speech(seconds: Double, loud: Float, dip: Float) -> [Float] {
        (0..<Int((seconds / frame).rounded())).map { $0 % 4 == 3 ? dip : loud }
    }

    @Test func nothingIsNoVoice() {
        #expect(!VoiceGate.hasVoice(levels: []))
        #expect(!VoiceGate.hasVoice([Float](repeating: 0, count: 16_000)))
    }

    @Test func roomAndFanAreNoVoice() {
        #expect(!VoiceGate.hasVoice(levels: Self.steady(Self.quietRoom, seconds: 3)))
        #expect(!VoiceGate.hasVoice(levels: Self.steady(Self.room, seconds: 3)))
        #expect(!VoiceGate.hasVoice(levels: Self.steady(Self.fan, seconds: 3)))
        #expect(!VoiceGate.hasVoice(levels: Self.steady(Self.fan, seconds: 0.5)))
    }

    @Test func aClickIsNoVoice() {
        let levels = Self.steady(Self.room, seconds: 1) + [0.8] + Self.steady(Self.room, seconds: 1)
        #expect(!VoiceGate.hasVoice(levels: levels))
    }

    @Test func aQuietShortWordIsVoice() {
        // «да» at −41 dBFS, a fifth of a second, in a quiet room.
        let levels = Self.steady(Self.quietRoom, seconds: 0.3) + Self.steady(0.32, seconds: 0.2, jitter: 0.01) + Self.steady(Self.quietRoom, seconds: 0.3)
        #expect(VoiceGate.hasVoice(levels: levels))
    }

    @Test func quietSpeechInAnOrdinaryRoomIsVoice() {
        let levels = Self.steady(Self.room, seconds: 0.4) + Self.speech(seconds: 1.5, loud: 0.34, dip: 0.2) + Self.steady(Self.room, seconds: 0.3)
        #expect(VoiceGate.hasVoice(levels: levels))
    }

    @Test func speechOverAFanIsVoice() {
        let levels = Self.steady(Self.fan, seconds: 0.5) + Self.speech(seconds: 2, loud: 0.72, dip: 0.5) + Self.steady(Self.fan, seconds: 0.3)
        #expect(VoiceGate.hasVoice(levels: levels))
    }

    @Test func speechWithNoQuietMomentIsVoice() {
        #expect(VoiceGate.hasVoice(levels: Self.speech(seconds: 3, loud: 0.68, dip: 0.42)))
    }

    @Test func aRampingMicrophoneDoesNotLetAFanThrough() {
        let levels: [Float] = [0.02, 0.1] + Self.steady(Self.fan, seconds: 2)
        #expect(!VoiceGate.hasVoice(levels: levels))
    }

    // MARK: Samples

    static func tone(dBFS: Float, seconds: Double) -> [Float] {
        let amplitude = powf(10, dBFS / 20) * Float(2).squareRoot()
        return (0..<Int(seconds * 16_000)).map { amplitude * sin(Float($0) * 2 * .pi * 220 / 16_000) }
    }

    static func noise(dBFS: Float, seconds: Double) -> [Float] {
        var generator = SystemRandomNumberGenerator()
        let amplitude = powf(10, dBFS / 20) * Float(3).squareRoot()
        return (0..<Int(seconds * 16_000)).map { _ in Float.random(in: -amplitude...amplitude, using: &generator) }
    }

    @Test func levelsSkipDigitalZeros() {
        let samples = [Float](repeating: 0, count: 8_000) + Self.noise(dBFS: -50, seconds: 1)
        let levels = VoiceGate.levels(of: samples)
        #expect(levels.count == 20)
        #expect(levels.allSatisfy { abs($0 - 10.0 / 60) < 0.02 })
    }

    @Test func samplesWithAQuietWordPass() {
        let samples = [Float](repeating: 0, count: 1_600) + Self.noise(dBFS: -58, seconds: 0.3) + Self.tone(dBFS: -40, seconds: 0.2) + Self.noise(dBFS: -58, seconds: 0.3)
        #expect(VoiceGate.hasVoice(samples))
    }

    @Test func samplesOfRoomNoiseDoNotPass() {
        #expect(!VoiceGate.hasVoice(Self.noise(dBFS: -52, seconds: 2)))
        #expect(!VoiceGate.hasVoice([Float](repeating: 0, count: 1_600) + Self.noise(dBFS: -35, seconds: 1)))
    }

    @Test func voiceEndsWithTheLastWord() throws {
        let samples = Self.noise(dBFS: -58, seconds: 0.5) + Self.tone(dBFS: -30, seconds: 1) + Self.noise(dBFS: -58, seconds: 0.8)
        let end = try #require(VoiceGate.voiceEnd(samples))
        #expect(abs(end - 1.5) <= VoiceGate.frameSeconds)
        #expect(VoiceGate.voiceEnd(Self.noise(dBFS: -58, seconds: 2)) == nil)
        #expect(VoiceGate.voiceEnd([]) == nil)
    }

    @Test func loudnessMatchesTheCaptureScale() {
        #expect(Loudness.level(rms: 0) == 0)
        #expect(abs(Loudness.level(rms: 0.001) - 0) < 0.0001)
        #expect(abs(Loudness.level(rms: 0.01) - 1.0 / 3) < 0.0001)
        #expect(Loudness.level(rms: 1) == 1)
        #expect(Loudness.rms([0.5, -0.5][...]) == 0.5)
    }
}
