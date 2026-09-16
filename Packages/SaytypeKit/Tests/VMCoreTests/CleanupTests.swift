import Testing
@testable import VMCore

@Suite struct CleanupTests {
    @Test func hesitationsModeRemovesOnlySounds() {
        #expect(Cleanup.removeFillers("Эээ, так, ну поправь хедер.", mode: .hesitations) == "Так, ну поправь хедер.")
        #expect(Cleanup.removeFillers("поправь ммм хедер", mode: .hesitations) == "поправь хедер")
    }

    @Test func allModeAlsoRemovesFillerWords() {
        #expect(Cleanup.removeFillers("Ну короче, задеплой как бы на Vercel.", mode: .all) == "Задеплой на Vercel.")
        #expect(Cleanup.removeFillers("Готово, типа.", mode: .all) == "Готово.")
    }

    @Test func keepModeChangesNothing() {
        let text = "Эээ, ну типа готово."
        #expect(Cleanup.removeFillers(text, mode: .keep) == text)
    }

    @Test func dropsTrailingPeriodOfShortPhrases() {
        #expect(Cleanup.dropTrailingPeriod("Открой настройки.") == "Открой настройки")
        #expect(Cleanup.dropTrailingPeriod("Что дальше...") == "Что дальше...")
        #expect(Cleanup.dropTrailingPeriod("Это длинная фраза из восьми слов подряд тут.") == "Это длинная фраза из восьми слов подряд тут.")
    }
}
