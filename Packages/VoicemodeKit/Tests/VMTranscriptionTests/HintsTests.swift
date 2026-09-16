import Testing
@testable import VMTranscription

@Suite struct HintsTests {
    @Test func defaultsToRussianWithWordTimings() {
        let hints = TranscriptionHints()
        #expect(hints.language == "ru")
        #expect(hints.wordTimestamps)
    }
}
