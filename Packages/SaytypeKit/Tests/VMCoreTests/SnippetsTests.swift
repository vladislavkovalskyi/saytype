import Foundation
import Testing
@testable import VMCore

@Suite struct SnippetsTests {
    let email = Snippet(triggers: ["мой имейл", "my email"], text: "vlad@example.com")
    let repo = Snippet(triggers: ["ссылка на репо"], text: "https://github.com/vladislavkovalskyi/saytype")
    let review = Snippet(triggers: ["шаблон ревью"], text: "Review the diff below. Focus on bugs, не на стиль.")

    var snippets: [Snippet] { [email, repo, review] }

    /// The pipeline with markers, then the snippets put in: what the app inserts without a model.
    func insert(_ raw: String, _ settings: AppSettings = AppSettings(), mode: DictationMode? = nil, snippets: [Snippet]? = nil, values: SnippetValues = SnippetValues()) -> String {
        let result = DictationPipeline.format(Transcript(text: raw), settings: settings, mode: mode ?? settings.standardMode, snippets: snippets ?? self.snippets)
        return SnippetPlacement.resolve(result.text, texts: result.snippets.map { $0.insertion(values) })
    }

    func matchedTexts(_ text: String, _ snippets: [Snippet]? = nil) -> [String] {
        SnippetMatcher(snippets ?? self.snippets).matches(in: text).map { String(text[$0.range]) }
    }

    // MARK: Settings

    @Test func settingsFromBeforeSnippetsLoadWithNone() throws {
        // A 0.3.0 document: no "snippets" key.
        let old = Data(#"{"voiceCommands":true,"autoTranslate":true,"translateTarget":"en","dictionary":[{"id":"6F1B7A2E-3C4D-4E5F-8A9B-0C1D2E3F4A5B","heard":"хедер","written":"Header","source":"manual"}]}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: old)
        #expect(settings.snippets.isEmpty)
        #expect(settings.autoTranslate)
        #expect(settings.dictionary.map(\.written) == ["Header"])
    }

    @Test func snippetsSurviveARoundTrip() throws {
        var settings = AppSettings()
        settings.snippets = snippets
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.snippets == snippets)
    }

    @Test func aSnippetWithMissingFieldsStillLoads() throws {
        let document = Data(#"{"snippets":[{"text":"hello"},{"triggers":["привет"],"text":"hi","color":"green"}]}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: document)
        #expect(settings.snippets.map(\.text) == ["hello", "hi"])
        #expect(settings.snippets[0].triggers.isEmpty)
        #expect(settings.snippets[1].triggers == ["привет"])
    }

    // MARK: Matching

    @Test func caseAndPunctuationDoNotMatter() {
        for text in ["мой имейл", "Мой имейл.", "МОЙ ИМЕЙЛ!", "Мой, имейл", "«Мой имейл»", "My email."] {
            #expect(matchedTexts(text).count == 1, "\(text)")
        }
    }

    @Test func spacingAndHyphensDoNotMatter() {
        #expect(matchedTexts("Вот шаблон-ревью.") == ["шаблон-ревью"])
        #expect(matchedTexts("Вот шаблонревью.") == ["шаблонревью"])
        #expect(matchedTexts("Вот шаблон  ревью.") == ["шаблон  ревью"])
        // The trigger may be written joined while Whisper splits it.
        #expect(matchedTexts("открой гит хаб", [Snippet(triggers: ["гитхаб"], text: "github.com")]) == ["гит хаб"])
    }

    @Test func yoAndDiacriticsFold() {
        let snippet = Snippet(triggers: ["всё ок"], text: "LGTM")
        #expect(matchedTexts("Все ок, мержи.", [snippet]) == ["Все ок"])
    }

    @Test func onlyWholeWordsMatch() {
        #expect(matchedTexts("мой имейлы").isEmpty)
        #expect(matchedTexts("домой имейл").isEmpty)
        #expect(matchedTexts("шаблоны ревью").isEmpty)
        #expect(matchedTexts("мой имейл2").isEmpty)
    }

    @Test func aMatchStopsAtTheEndOfASentence() {
        #expect(matchedTexts("Это мой. Имейл потом.").isEmpty)
        #expect(matchedTexts("это мой\nимейл").isEmpty)
        // A dot inside a term is not a sentence end.
        #expect(matchedTexts("открой Next.js доку", [Snippet(triggers: ["next js доку"], text: "https://nextjs.org/docs")]) == ["Next.js доку"])
    }

    @Test func theLongestTriggerWins() {
        let short = Snippet(triggers: ["ссылка"], text: "link")
        #expect(matchedTexts("Вот ссылка на репо.", [short, repo]) == ["ссылка на репо"])
        let found = SnippetMatcher([short, repo]).matches(in: "Вот ссылка на репо.")
        #expect(found.map(\.snippet.id) == [repo.id])
    }

    @Test func theEarlierSnippetWinsASharedTrigger() {
        let first = Snippet(triggers: ["мой имейл"], text: "work@example.com")
        let second = Snippet(triggers: ["Мой имейл"], text: "home@example.com")
        #expect(SnippetMatcher([first, second]).matches(in: "мой имейл").map(\.snippet.id) == [first.id])
    }

    @Test func triggersShorterThanTwoLettersAreIgnored() {
        let matcher = SnippetMatcher([Snippet(triggers: ["я", " ", "!!"], text: "x")])
        #expect(matcher.isEmpty)
        #expect(matcher.matches(in: "я тут").isEmpty)
    }

    @Test func everyOccurrenceMatches() {
        #expect(matchedTexts("мой имейл и ещё раз мой имейл") == ["мой имейл", "мой имейл"])
    }

    // MARK: Pipeline and placement

    @Test func aSnippetAloneIsInsertedExactly() {
        #expect(insert("Мой имейл.") == "vlad@example.com")
        #expect(insert("ссылка на репо") == "https://github.com/vladislavkovalskyi/saytype")
        #expect(insert("Шаблон ревью.") == review.text)
    }

    @Test func aSnippetInsideAPhraseGoesInPlace() {
        #expect(insert("Проверь шаблон ревью для этого файла.") == "Проверь Review the diff below. Focus on bugs, не на стиль. для этого файла.")
        #expect(insert("Напиши мне на мой имейл, спасибо.") == "Напиши мне на vlad@example.com, спасибо.")
    }

    @Test func theFormatterPeriodAfterASentenceEndingSnippetGoes() {
        #expect(insert("Проверь шаблон ревью.") == "Проверь Review the diff below. Focus on bugs, не на стиль.")
    }

    @Test func snippetTextSkipsEveryTextRule() {
        let template = Snippet(triggers: ["шаблон"], text: "Ну, юз эффект и хедер — ПРОВЕРЬ, короче")
        var settings = AppSettings()
        settings.isChatStyle = true
        settings.fillerMode = .all
        settings.wordFilters = ["короче"]
        settings.dictionary = [DictionaryEntry(heard: "хедер", written: "Header")]
        settings.censorProfanity = true
        #expect(insert("Вставь шаблон, короче, в хедер.", settings, snippets: [template]) == "вставь Ну, юз эффект и хедер — ПРОВЕРЬ, короче, в Header")
    }

    @Test(arguments: [AppSettings.PunctuationStyle.full, .commas, .none])
    func markersSurviveEveryPunctuationStyle(style: AppSettings.PunctuationStyle) {
        var settings = AppSettings()
        settings.punctuationStyle = style
        for letterCase in [AppSettings.LetterCase.asSpoken, .lowercase] {
            settings.letterCase = letterCase
            let result = DictationPipeline.format(Transcript(text: "Эээ, проверь шаблон ревью, ну, для useEffect. Мой имейл."), settings: settings, mode: settings.standardMode, snippets: snippets)
            #expect(SnippetMarker.numbers(in: result.text) == [1, 2], "\(style) \(letterCase): \(result.text)")
            #expect(result.snippets.map(\.id) == [review.id, email.id])
        }
    }

    @Test func markersSurviveSpokenCodeAndBackticks() {
        let settings = AppSettings()
        let developer = DictationMode.defaults.first { $0.developer } ?? DictationMode(id: "dev", developer: true)
        let result = DictationPipeline.format(Transcript(text: "шаблон ревью для кэмел кейс юзер дата в src слэш app точка tsx"), settings: settings, mode: developer, snippets: snippets)
        #expect(result.text.hasPrefix("⟦1⟧ "))
        #expect(result.text.contains("userData"))
        let wrapped = Backticks.wrap(result.text, terms: [])
        #expect(wrapped.hasPrefix("⟦1⟧ "))
        #expect(SnippetPlacement.resolve(wrapped, texts: [review.text]).hasPrefix(review.text + " для"))
    }

    @Test func paragraphTimingsAreDroppedOnlyWithASnippet() {
        let words = [
            TranscriptWord(text: "Первое.", start: 0, end: 0.5),
            TranscriptWord(text: "Второе.", start: 3, end: 3.5),
        ]
        let settings = AppSettings()
        let plain = DictationPipeline.format(Transcript(text: "Первое. Второе.", words: words), settings: settings, mode: settings.standardMode, snippets: snippets)
        #expect(plain.text == "Первое.\n\nВторое.")
        #expect(plain.snippets.isEmpty)
        let timed = [
            TranscriptWord(text: "Мой", start: 0, end: 0.3),
            TranscriptWord(text: "имейл.", start: 0.3, end: 0.6),
            TranscriptWord(text: "Второе.", start: 3, end: 3.5),
        ]
        let withSnippet = DictationPipeline.format(Transcript(text: "Мой имейл. Второе.", words: timed), settings: settings, mode: settings.standardMode, snippets: snippets)
        #expect(withSnippet.text == "⟦1⟧. Второе.")
        #expect(SnippetPlacement.resolve(withSnippet.text, texts: [email.text]) == "vlad@example.com. Второе.")
    }

    @Test func emptySnippetsTakeTheirSpace() {
        let paste = Snippet(triggers: ["из буфера"], text: "{clipboard}")
        #expect(insert("Вставь из буфера, пожалуйста.", snippets: [paste], values: SnippetValues(clipboard: nil)) == "Вставь, пожалуйста.")
        #expect(insert("Из буфера.", snippets: [paste], values: SnippetValues(clipboard: "  ")) == "")
    }

    @Test func snippetEdgesAreTrimmed() {
        let padded = Snippet(triggers: ["подпись"], text: "\n  С уважением,\nВлад\n\n")
        #expect(insert("Подпись.", snippets: [padded]) == "С уважением,\nВлад")
    }

    @Test func severalSnippetsInALine() {
        #expect(insert("Мой имейл, ссылка на репо.") == "vlad@example.com https://github.com/vladislavkovalskyi/saytype")
    }

    @Test func placementLeavesTextWithoutMarkersAlone() {
        #expect(SnippetPlacement.resolve("Привет, мир.", texts: ["x"]) == "Привет, мир.")
        // A marker without a snippet disappears; a lone bracket stays.
        #expect(SnippetPlacement.resolve("Вот ⟦3⟧ и ⟦ тут.", texts: ["x"]) == "Вот и ⟦ тут.")
    }

    // MARK: Voice commands

    @Test func voiceCommandsBreakLinesBetweenSnippets() {
        #expect(insert("Шаблон ревью. Новая строка. Мой имейл.") == review.text + "\nvlad@example.com")
    }

    @Test func aCommandWinsOverASnippetWithTheSameWords() {
        let clash = Snippet(triggers: ["новая строка"], text: "NEWLINE")
        #expect(insert("Привет. Новая строка. Пока.", snippets: [clash]) == "Привет.\nПока.")
        var off = AppSettings()
        off.voiceCommands = false
        #expect(insert("Привет. Новая строка. Пока.", off, snippets: [clash]) == "Привет. NEWLINE. Пока.")
    }

    @Test func sendAfterASnippetStillSends() {
        let settings = AppSettings()
        let result = DictationPipeline.format(Transcript(text: "Шаблон ревью, отправь."), settings: settings, mode: settings.standardMode, snippets: snippets)
        #expect(result.send)
        #expect(SnippetPlacement.resolve(result.text, texts: result.snippets.map(\.text)) == review.text)
    }

    @Test func snippetsThatAreNotSaidChangeNothing() {
        let settings = AppSettings()
        let unrelated = [Snippet(triggers: ["несказанная фраза"], text: "x")]
        for text in ["Привет. Новая строка. Как дела?", "проверь шаблон ревью", "Мой имейл, отправь."] {
            let before = DictationPipeline.format(Transcript(text: text), settings: settings, mode: settings.standardMode)
            let after = DictationPipeline.format(Transcript(text: text), settings: settings, mode: settings.standardMode, snippets: unrelated)
            #expect(before == after)
            #expect(after.snippets.isEmpty)
        }
    }

    // MARK: Variables

    let moment = Date(timeIntervalSince1970: 1_790_172_300) // 2026-09-23 14:05 UTC

    @Test func variablesAreFilledIn() {
        let values = SnippetValues(clipboard: "let x = 1", selection: "func a() {}", now: moment, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)
        let text = SnippetVariables.expand("{date} {time}: review {selection} with {clipboard}", values: values)
        #expect(text.hasPrefix("September 23, 2026 2:05"))
        #expect(text.contains("PM: review func a() {} with let x = 1"))
    }

    @Test func dateFollowsTheLocale() {
        let values = SnippetValues(now: moment, locale: Locale(identifier: "ru_RU"), timeZone: TimeZone(identifier: "UTC")!)
        #expect(values.date.hasPrefix("23 сентября 2026"))
        #expect(values.time == "14:05")
    }

    @Test func unknownBracesStayAndNamesIgnoreCase() {
        let values = SnippetValues(clipboard: "C", now: moment, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)
        #expect(SnippetVariables.expand("{name} { id } {CLIPBOARD} {Clipboard}{", values: values) == "{name} { id } C C{")
        #expect(SnippetVariables.used(in: "{Selection} {name} {date}") == [.selection, .date])
        #expect(SnippetVariables.used(in: "plain text").isEmpty)
    }

    @Test func missingValuesAreEmpty() {
        #expect(SnippetVariables.expand("[{clipboard}][{selection}]", values: SnippetValues()) == "[][]")
    }

    // MARK: Markers and the language model

    @Test func onlyMarkers() {
        #expect(SnippetMarker.isOnlyMarkers("⟦1⟧."))
        #expect(SnippetMarker.isOnlyMarkers("⟦1⟧, ⟦2⟧!\n⟦3⟧"))
        #expect(!SnippetMarker.isOnlyMarkers("Проверь ⟦1⟧."))
        #expect(!SnippetMarker.isOnlyMarkers("Привет."))
        #expect(!SnippetMarker.isOnlyMarkers("1. ⟦1⟧"))
    }

    @Test func markerMismatches() {
        let original = "Проверь ⟦1⟧ и ⟦2⟧."
        #expect(SnippetMarker.mismatch(original: original, candidate: "Check ⟦1⟧ and ⟦2⟧.") == nil)
        #expect(SnippetMarker.mismatch(original: original, candidate: "Check ⟦2⟧ and ⟦1⟧.") == nil)
        #expect(SnippetMarker.mismatch(original: original, candidate: "Check ⟦1⟧.")?.marker == "⟦2⟧")
        #expect(SnippetMarker.mismatch(original: original, candidate: "Check ⟦1⟧ and ⟦2⟧ ⟦2⟧.")?.missing == false)
        #expect(SnippetMarker.mismatch(original: original, candidate: "Check ⟦1⟧ and ⟦3⟧.")?.marker == "⟦2⟧")
        #expect(SnippetMarker.mismatch(original: "⟦1⟧ x", candidate: "⟦ 1 ⟧ x")?.missing == true)
        #expect(SnippetMarker.mismatch(original: "no markers", candidate: "⟦1⟧ appeared")?.missing == false)
        #expect(SnippetMarker.mismatch(original: "⟦1⟧ x", candidate: "⟦1⟧ x ⟦")?.marker == "⟦")
    }

    @Test func theModelIsToldAboutMarkersOnlyWhenThereAreSome() {
        let request = RewriteRequest(style: .none, translate: true)
        #expect(!request.userMessage("Привет.").contains("⟦"))
        let message = request.userMessage("Проверь ⟦1⟧ для этого файла.")
        #expect(message.contains(RewriteRequest.markerRule))
        #expect(message.hasSuffix("<dictation>\nПроверь ⟦1⟧ для этого файла.\n</dictation>"))
        #expect(request.systemPrompt == RewriteRequest(style: .none, translate: true).systemPrompt)
    }

    @Test func aRewriteThatLosesAMarkerIsRejected() {
        let request = RewriteRequest(style: .none, translate: true)
        let original = "Проверь ⟦1⟧ для этого файла."
        #expect(RewriteValidator.check(original: original, candidate: "Check ⟦1⟧ for this file.", request: request) == .accepted)
        #expect(RewriteValidator.check(original: original, candidate: "Check the review template for this file.", request: request) == .rejected(.dropped("⟦1⟧")))
        #expect(RewriteValidator.check(original: original, candidate: "Check ⟦1⟧ ⟦1⟧ for this file.", request: request) == .rejected(.invented("⟦1⟧")))
        let prompt = RewriteRequest(style: .prompt, sourceLanguage: "Russian")
        #expect(RewriteValidator.check(original: original, candidate: "Цель: проверить ⟦1⟧ для этого файла.", request: prompt) == .accepted)
    }
}
