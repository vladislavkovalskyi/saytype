import Foundation
import Testing
@testable import VMCore

@Suite struct TextFormatterTests {
    func words(_ spec: [(String, Double, Double)]) -> [TranscriptWord] {
        spec.map { TranscriptWord(text: $0.0, start: $0.1, end: $0.2) }
    }

    @Test func splitsParagraphsAtLongPausesAfterSentences() {
        let transcript = Transcript(
            text: "Сборка упала. Посмотри логи. Потом задеплой",
            words: words([("Сборка", 0, 0.4), ("упала.", 0.4, 0.9), ("Посмотри", 2.8, 3.2), ("логи.", 3.2, 3.6), ("Потом", 3.9, 4.2), ("задеплой", 4.2, 4.8)])
        )
        #expect(Paragraphs.split(transcript, pause: 1.5) == ["Сборка упала.", "Посмотри логи. Потом задеплой"])
    }

    @Test func noParagraphInsideASentence() {
        let transcript = Transcript(text: "поправь хедер", words: words([("поправь", 0, 0.5), ("хедер", 3, 3.5)]))
        #expect(Paragraphs.split(transcript, pause: 1.5) == ["поправь хедер"])
    }

    @Test func fallsBackWhenWordsDoNotMatchText() {
        let transcript = Transcript(text: "другой текст", words: words([("поправь", 0, 0.5), ("хедер.", 0.5, 1)]))
        #expect(Paragraphs.split(transcript, pause: 1.5) == ["другой текст"])
    }

    @Test func buildsNumberedListFromOrdinals() {
        let text = "Сегодня доделываю авторизацию. Во-первых, поправить useEffect в Header. Во-вторых, задеплоить ветку на Vercel. В-третьих, скинуть превью"
        #expect(Lists.format(text) == """
        Сегодня доделываю авторизацию:
        1. Поправить useEffect в Header.
        2. Задеплоить ветку на Vercel.
        3. Скинуть превью.
        """)
    }

    @Test func singleOrdinalIsNotAList() {
        let text = "Во-первых, это неплохо."
        #expect(Lists.format(text) == text)
    }

    @Test func fullPipelineAppliesDictionaryFillersAndList() {
        var settings = AppSettings()
        settings.dictionary = [DictionaryEntry(heard: "юз эффект", written: "useEffect")]
        let transcript = Transcript(text: "Эээ, во-первых, поправь юз эффект. Во-вторых, задеплой.")
        #expect(TextFormatter.format(transcript, settings: settings) == "1. Поправь useEffect.\n2. Задеплой.")
    }

    @Test func punctuationOffStripsMarksButKeepsTerms() {
        var settings = AppSettings()
        settings.punctuationStyle = .none
        settings.smartStructure = false
        let transcript = Transcript(text: "Обнови Next.js, потом feature/auth.")
        #expect(TextFormatter.format(transcript, settings: settings) == "Обнови Next.js потом feature/auth")
    }
}

@Suite struct CodeLikeTests {
    @Test func detectsIdentifiersButNotProse() {
        for word in ["useEffect", "Next.js,", "feature/auth", "OPENAI_API_KEY", "localhost:3000", "/start", ".env", "process.env."] {
            #expect(Words.isCodeLike(word), "\(word)")
        }
        for word in ["Vercel", "React.", "поправь", "API", "15.2", "U.S"] {
            #expect(!Words.isCodeLike(word), "\(word)")
        }
    }
}

@Suite struct ChatStyleTests {
    @Test func chatStyleKeepsCommasAndLowercases() {
        var settings = AppSettings()
        settings.isChatStyle = true
        let transcript = Transcript(text: "Привет! Я закончил useEffect в React, завтра покажу API. Ок?")
        #expect(TextFormatter.format(transcript, settings: settings) == "привет я закончил useEffect в React, завтра покажу API ок")
    }

    @Test func lowercaseWithFullPunctuation() {
        var settings = AppSettings()
        settings.letterCase = .lowercase
        let transcript = Transcript(text: "Сборка упала. Посмотри GitHub Actions.")
        #expect(TextFormatter.format(transcript, settings: settings) == "сборка упала. посмотри GitHub Actions.")
    }

    @Test func lowercaseKeepsLineBreaks() {
        #expect(Letters.lowercase("План:\n1. Купить Хлеб.\n2. Позвонить") == "план:\n1. купить хлеб.\n2. позвонить")
    }

    @Test func stripKeepsTermsWithDots() {
        #expect(Punctuation.strip("Обнови Next.js, 3.5. Готово!", keeping: [","]) == "Обнови Next.js, 3.5 Готово")
    }

    @Test func legacyPunctuationSwitchMigrates() throws {
        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"punctuation":false}"#.utf8))
        #expect(off.punctuationStyle == .none)
        let on = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"punctuation":true}"#.utf8))
        #expect(on.punctuationStyle == .full)
    }
}
