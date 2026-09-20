import Testing
@testable import VMCore

@Suite("Learning from an edited card")
struct EditLearningTests {
    /// Terms the app knows without the user teaching them.
    private let known = ["Next.js", "Supabase", "Vercel"]

    // MARK: What is learned

    @Test("A term rewritten in Latin becomes an entry")
    func latinTerm() {
        let entries = EditLearning.corrections(
            raw: "поправь хедер в компоненте",
            text: "Поправь хедер в компоненте.",
            edited: "Поправь Header в компоненте."
        )
        #expect(entries.count == 1)
        #expect(entries.first?.heard == "хедер")
        #expect(entries.first?.written == "Header")
        #expect(entries.first?.source == .history)
    }

    @Test("Two spoken words become one identifier")
    func twoWordsToOne() {
        let entries = EditLearning.corrections(
            raw: "перепиши юз эффект в хуке",
            text: "Перепиши юз эффект в хуке.",
            edited: "Перепиши useEffect в хуке."
        )
        #expect(entries.map(\.heard) == ["юз эффект"])
        #expect(entries.map(\.written) == ["useEffect"])
    }

    @Test("A fix of case alone teaches the spelling only")
    func caseOnly() {
        let entries = EditLearning.corrections(
            raw: "залей на github",
            text: "Залей на github.",
            edited: "Залей на GitHub."
        )
        #expect(entries.count == 1)
        #expect(entries.first?.heard == "")
        #expect(entries.first?.written == "GitHub")
    }

    @Test("A known term is learned even when it sounds far off")
    func knownTerm() {
        let entries = EditLearning.corrections(
            raw: "подними некст джей эс",
            text: "Подними некст джей эс.",
            edited: "Подними Next.js.",
            knownTerms: known
        )
        #expect(entries.map(\.written) == ["Next.js"])
        #expect(entries.map(\.heard) == ["некст джей эс"])
    }

    @Test("Trailing punctuation is not part of the spelling")
    func trailingPunctuation() {
        let entries = EditLearning.corrections(
            raw: "залей на версель",
            text: "Залей на версель.",
            edited: "Залей на Vercel.",
            knownTerms: known
        )
        #expect(entries.map(\.written) == ["Vercel"])
    }

    @Test("Several fixes in one edit")
    func severalFixes() {
        let entries = EditLearning.corrections(
            raw: "поправь хедер и задеплой на версель",
            text: "Поправь хедер и задеплой на версель.",
            edited: "Поправь Header и задеплой на Vercel."
        )
        #expect(entries.map(\.written) == ["Header", "Vercel"])
    }

    @Test("A one-word spelling fix inside one script")
    func sameScript() {
        let entries = EditLearning.corrections(
            raw: "поставь кубернетис",
            text: "Поставь кубернетис.",
            edited: "Поставь Кубернетес."
        )
        #expect(entries.map(\.written) == ["Кубернетес"])
    }

    // MARK: What is not learned

    @Test("A rewritten phrase is not a rule")
    func rewrittenPhrase() {
        let entries = EditLearning.corrections(
            raw: "поправь это в компоненте",
            text: "Поправь это в компоненте.",
            edited: "Fix this в компоненте."
        )
        #expect(entries.isEmpty)
    }

    @Test("A translation of a phrase is not a rule")
    func translation() {
        let entries = EditLearning.corrections(
            raw: "сделай список из этого",
            text: "Сделай список из этого.",
            edited: "Make a list из этого."
        )
        #expect(entries.isEmpty)
    }

    @Test("Words only added or only removed teach nothing")
    func insertionsAndDeletions() {
        #expect(EditLearning.corrections(raw: "поправь хедер", text: "Поправь хедер.", edited: "Поправь хедер сегодня.").isEmpty)
        #expect(EditLearning.corrections(raw: "поправь хедер сегодня", text: "Поправь хедер сегодня.", edited: "Поправь хедер.").isEmpty)
    }

    @Test("A run longer than three words is a rewrite")
    func longRun() {
        let entries = EditLearning.corrections(
            raw: "надо бы это всё переделать заново",
            text: "Надо бы это всё переделать заново.",
            edited: "Rewrite all of that please заново."
        )
        #expect(entries.isEmpty)
    }

    @Test("A capital at the start of a sentence is not a term")
    func sentenceCase() {
        #expect(EditLearning.corrections(raw: "поправь хедер", text: "поправь хедер.", edited: "Поправь хедер.").isEmpty)
        #expect(EditLearning.corrections(raw: "fix this", text: "fix this.", edited: "Fix this.").isEmpty)
    }

    @Test("A different mark after a word teaches nothing")
    func punctuationOnly() {
        #expect(EditLearning.corrections(raw: "поправь хедер потом", text: "Поправь хедер, потом.", edited: "Поправь хедер. Потом.").isEmpty)
    }

    @Test("An unchanged text teaches nothing")
    func unchanged() {
        #expect(EditLearning.corrections(raw: "поправь хедер", text: "Поправь хедер.", edited: "Поправь хедер.").isEmpty)
    }

    @Test("At most five entries from one edit")
    func limit() {
        let words = ["хедер", "версель", "призма", "супабейс", "докер", "зод"]
        let latin = ["Header", "Vercel", "Prisma", "Supabase", "Docker", "Zod"]
        let entries = EditLearning.corrections(
            raw: words.joined(separator: " и "),
            text: words.joined(separator: " и "),
            edited: latin.joined(separator: " и ")
        )
        #expect(entries.count == EditLearning.entryLimit)
    }

    // MARK: Sounds

    @Test("Cyrillic is compared by sound")
    func sound() {
        #expect(EditLearning.sound("хедер") == "heder")
        #expect(EditLearning.sound("Юз Эффект") == "yuzeffekt")
        #expect(EditLearning.sound("Next.js") == "nextjs")
    }

    @Test("Similarity of the pairs the thresholds were set on", arguments: [
        ("хедер", "Header", 0.8),
        ("версель", "Vercel", 0.8),
        ("супабейс", "Supabase", 0.6),
        ("юз эффект", "useEffect", 0.5),
    ])
    func similarityOfTerms(heard: String, written: String, atLeast: Double) {
        #expect(EditLearning.similarity(heard, written) >= atLeast)
    }

    @Test("Similarity of pairs that must stay out", arguments: [
        ("поправь это", "fix this"),
        ("сделай список", "make a list"),
    ])
    func similarityOfPhrases(heard: String, written: String) {
        #expect(EditLearning.similarity(heard, written) < EditLearning.similarityLimit)
    }
}
