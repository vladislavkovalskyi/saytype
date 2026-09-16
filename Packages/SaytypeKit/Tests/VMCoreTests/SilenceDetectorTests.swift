import Foundation
import Testing
@testable import VMCore

@Suite struct SilenceDetectorTests {
    static let chunk = 0.1
    static let room: Float = 0.12
    static let fan: Float = 0.38

    /// Speech-like levels: loud syllables with short dips between words.
    static func speech(seconds: Double, loud: Float = 0.68, dip: Float = 0.42) -> [Float] {
        (0..<Int((seconds / chunk).rounded())).map { $0 % 5 == 4 ? dip : loud + Float($0 % 3) * 0.03 }
    }

    static func steady(_ level: Float, seconds: Double, jitter: Float = 0.02) -> [Float] {
        (0..<Int((seconds / chunk).rounded())).map { level + (Float($0 % 4) - 1.5) * jitter / 1.5 }
    }

    /// Seconds from the start at which the detector asks to stop, nil if it never does.
    static func stopTime(_ levels: [Float], limit: Double, chunk: Double = chunk) -> Double? {
        var detector = SilenceDetector(limit: limit)
        for (i, level) in levels.enumerated() where detector.update(level: level, duration: chunk) {
            return Double(i + 1) * chunk
        }
        return nil
    }

    @Test func offNeverStops() {
        #expect(Self.stopTime(Self.speech(seconds: 2) + Self.steady(0, seconds: 60), limit: 0) == nil)
    }

    @Test func stopsAfterTheLimitOfSilenceFollowingSpeech() throws {
        let levels = Self.steady(Self.room, seconds: 1) + Self.speech(seconds: 4) + Self.steady(Self.room, seconds: 10)
        let stop = try #require(Self.stopTime(levels, limit: 3))
        #expect(abs(stop - (1 + 4 + 3)) < 0.25)
    }

    @Test func pausesShorterThanTheLimitKeepRecording() {
        var levels = Self.steady(Self.room, seconds: 1)
        for _ in 0..<6 { levels += Self.speech(seconds: 3) + Self.steady(Self.room, seconds: 2.5) }
        #expect(Self.stopTime(levels, limit: 3) == nil)
    }

    @Test func waitsLongerBeforeAnySpeech() throws {
        let levels = Self.steady(Self.room, seconds: 30)
        let stop = try #require(Self.stopTime(levels, limit: 3))
        #expect(abs(stop - SilenceDetector(limit: 3).initialLimit) < 0.15)
        #expect(SilenceDetector(limit: 3).initialLimit == 8)
        #expect(SilenceDetector(limit: 10).initialLimit == 20)
        // Speech before the long limit: the ordinary limit applies from there.
        #expect(Self.stopTime(Self.steady(Self.room, seconds: 6) + Self.speech(seconds: 1) + Self.steady(Self.room, seconds: 2.5), limit: 3) == nil)
    }

    @Test func steadyFanIsNotSpeech() throws {
        let stop = try #require(Self.stopTime(Self.steady(Self.fan, seconds: 30), limit: 3))
        #expect(abs(stop - 8) < 0.15)
    }

    @Test func speechOverAFanStopsWhenOnlyTheFanRemains() throws {
        let levels = Self.steady(Self.fan, seconds: 2) + Self.speech(seconds: 5, loud: 0.72, dip: 0.5) + Self.steady(Self.fan, seconds: 10)
        let stop = try #require(Self.stopTime(levels, limit: 3))
        #expect(abs(stop - (2 + 5 + 3)) < 0.25)
    }

    @Test func fanStartingMidRecordingBecomesTheFloor() throws {
        let levels = Self.steady(Self.room, seconds: 1) + Self.speech(seconds: 3) + Self.steady(Self.fan, seconds: 30)
        let stop = try #require(Self.stopTime(levels, limit: 3))
        // The fan first sounds like voice, then settles into the floor within about ten seconds.
        #expect(stop > 1 + 3 + 3)
        #expect(stop < 1 + 3 + 3 + 11)
    }

    @Test func clicksAreNotSpeech() throws {
        var levels = Self.steady(Self.room, seconds: 1)
        for _ in 0..<10 { levels += [0.85] + Self.steady(Self.room, seconds: 1) }
        let stop = try #require(Self.stopTime(levels, limit: 3))
        // Each click pauses the clock for its own length only.
        #expect(stop > 8)
        #expect(stop < 9.5)
    }

    @Test func longMonologueNeverStops() {
        // A minute of talking with a short breath every six seconds.
        var levels = Self.steady(Self.room, seconds: 1)
        for _ in 0..<10 { levels += Self.speech(seconds: 5.7) + Self.steady(Self.room, seconds: 0.3) }
        #expect(Self.stopTime(levels, limit: 3) == nil)
        // Even twenty seconds of loud voice without a single dip isn't taken for noise.
        let breathless = Self.steady(Self.room, seconds: 1) + (0..<200).map { Float(0.62) + Float($0 % 7) * 0.02 } + Self.speech(seconds: 1)
        #expect(Self.stopTime(breathless, limit: 3) == nil)
    }

    @Test func chunkLengthDoesNotChangeTiming() throws {
        let short = 0.025
        let levels = Self.steady(Self.room, seconds: 1).flatMap { [Float](repeating: $0, count: 4) }
            + Self.speech(seconds: 4).flatMap { [Float](repeating: $0, count: 4) }
            + Self.steady(Self.room, seconds: 10).flatMap { [Float](repeating: $0, count: 4) }
        let stop = try #require(Self.stopTime(levels, limit: 5, chunk: short))
        #expect(abs(stop - (1 + 4 + 5)) < 0.25)
    }

    @Test func microphoneStartupZerosDoNotSetTheFloor() throws {
        let levels = [Float](repeating: 0, count: 3) + Self.steady(Self.fan, seconds: 30)
        let stop = try #require(Self.stopTime(levels, limit: 3))
        #expect(abs(stop - 8) < 0.15)
    }

    @Test func updateIsCheap() {
        var detector = SilenceDetector(limit: 5)
        let levels = Self.speech(seconds: 10)
        let clock = ContinuousClock()
        let rounds = 1_000_000
        let elapsed = clock.measure {
            for i in 0..<rounds { _ = detector.update(level: levels[i % levels.count], duration: 0.1) }
        }
        let nanoseconds = (Double(elapsed.components.seconds) * 1e18 + Double(elapsed.components.attoseconds)) / 1e9 / Double(rounds)
        print(String(format: "silence detector: %.1f ns per chunk", nanoseconds))
        #expect(nanoseconds < 1_000)
    }
}
