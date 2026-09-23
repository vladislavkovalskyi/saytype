import Testing
@testable import VMSystem

@Suite struct ScreenContextReaderTests {
    @Test func cutTextLosesTheWordsCutInTwo() {
        let text = "ctationController and PromptBuilder then fetchUserPro"
        #expect(ScreenContextReader.wholeWords(text, cutStart: true, cutEnd: true) == " and PromptBuilder then")
        #expect(ScreenContextReader.wholeWords(text, cutStart: false, cutEnd: false) == text)
        #expect(ScreenContextReader.wholeWords("oneword", cutStart: true, cutEnd: true) == "oneword")
    }

    @Test func noAppGivesNothingAndReturnsAtOnce() {
        let reading = ScreenContextReader.read(pid: -1)
        #expect(reading.text.isEmpty)
        #expect(reading.nodes == 0)
        #expect(reading.elapsed < .milliseconds(200))
    }

    @Test func numbersFromAnotherAppAreChecked() {
        #expect(!ScreenContextReader.sane.contains(Int.max))
        #expect(!ScreenContextReader.sane.contains(-1))
        #expect(ScreenContextReader.sane.contains(0))
    }
}
