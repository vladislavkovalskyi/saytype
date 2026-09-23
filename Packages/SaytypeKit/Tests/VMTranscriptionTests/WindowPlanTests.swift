import Foundation
import Testing
@testable import VMTranscription

@Suite struct WindowPlanTests {
    static func tone(seconds: Double) -> [Float] {
        (0..<Int(seconds * 16_000)).map { 0.05 * sin(Float($0) * 2 * .pi * 220 / 16_000) }
    }

    static func room(seconds: Double) -> [Float] {
        (0..<Int(seconds * 16_000)).map { Float($0 % 7 - 3) * 0.0003 }
    }

    @Test func aShortWordGetsItsWindow() {
        let samples = Self.room(seconds: 0.1) + Self.tone(seconds: 0.3) + Self.room(seconds: 0.2)
        let plan = WhisperKitEngine.windowPlan(samples)
        // The voice ends at 0.4 s: windows may start up to 0.1 s, and the first one starts at 0.
        #expect(plan.limit == 1_600)
        #expect(plan.padding == 1_600 + 16_000 - samples.count)
        #expect(plan.clipTime == 1)
    }

    @Test func noWindowStartsOnTheSilenceAfterTheVoice() {
        let samples = Self.room(seconds: 0.2) + Self.tone(seconds: 2) + Self.room(seconds: 3)
        let plan = WhisperKitEngine.windowPlan(samples)
        #expect(plan.limit == Int(1.9 * 16_000))
        #expect(plan.padding == 0)
        #expect(abs(plan.clipTime - 3.3) < 0.001)
    }

    @Test func aRecordingThatEndsInVoiceIsPaddedForTheChunker() {
        // 40 s of phrases with short pauses, the last one cut by the key.
        let samples = (0..<40).flatMap { _ in Self.room(seconds: 0.2) + Self.tone(seconds: 0.8) }
        let plan = WhisperKitEngine.windowPlan(samples)
        #expect(plan.limit == samples.count - 4_800)
        #expect(plan.padding == 16_000 - 4_800)
        #expect(plan.clipTime == 1)
    }

    @Test func withoutVoiceTheWholeRecordingIsOpen() {
        // Nothing to compare with: loud from start to end counts as no known end of voice.
        #expect(WhisperKitEngine.windowPlan(Self.tone(seconds: 2)).limit == 32_000)
        let samples = Self.room(seconds: 2)
        let plan = WhisperKitEngine.windowPlan(samples)
        #expect(plan.limit == samples.count)
        #expect(plan.padding == 16_000)
        #expect(plan.clipTime == 1)
    }
}
