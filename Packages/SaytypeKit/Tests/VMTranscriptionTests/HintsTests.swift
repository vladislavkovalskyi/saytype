import Testing
@testable import VMTranscription

@Suite struct HintsTests {
    @Test func defaultsToRussianWithoutGlossary() {
        let hints = TranscriptionHints()
        #expect(hints.language == "ru")
        #expect(hints.glossary.isEmpty)
        #expect(!hints.translate)
    }
}
