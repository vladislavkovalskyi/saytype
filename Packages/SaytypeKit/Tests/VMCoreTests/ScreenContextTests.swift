import Foundation
import Testing
@testable import VMCore

@Suite struct SoundKeyTests {
    func key(_ word: String) -> String { SoundKey.string(SoundKey.key(word)) }

    func distance(_ a: String, _ b: String) -> Double {
        var left: [UInt8] = []
        for word in Words.split(a) { SoundKey.append(SoundKey.key(word), to: &left) }
        var right: [UInt8] = []
        for word in Words.split(b) { SoundKey.append(SoundKey.key(word), to: &right) }
        return SoundKey.distance(left, right)
    }

    @Test func englishSpellingAndItsCyrillicRenderingMeet() {
        #expect(key("DictationController") == "daktaSnkantralar")
        #expect(distance("диктишн контроллер", "DictationController") == 0)
        #expect(distance("диктейшн контроллер", "DictationController") == 0)
        #expect(distance("термканоника лазер", "TermCanonicalizer") == 0)
        #expect(distance("MaxRetroAccount", "MAX_RETRY_COUNT") == 0)
        #expect(distance("ScreenContextRider", "ScreenContextReader") == 0)
        #expect(distance("WhisperKit Engine", "WhisperKitEngine") == 0)
        #expect(distance("виспер кит энджин", "WhisperKitEngine") <= 0.1)
    }

    @Test func nearMissesCostLittle() {
        #expect(distance("фич-юзер профил", "fetchUserProfile") <= 0.1)
        #expect(distance("useAufSession", "useAuthSession") == 0.5)
        #expect(distance("юз ауф сешн", "useAuthSession") == 0.5)
        #expect(distance("UserProfileCart.tsx", "UserProfileCard.tsx") <= 1)
        // The final e of "readme" is sounded; of "use" and "case" it is not. Either way it is cheap.
        #expect(distance("ridme.md", "README.md") <= 0.1)
        #expect(distance("Rydmi.MD", "README.md") <= 0.1)
        #expect(distance("юз", "use") <= 0.1)
        #expect(distance("кейс", "case") <= 0.1)
    }

    @Test func englishRules() {
        #expect(key("session") == "saSn")
        #expect(key("fetch") == "faC")
        #expect(key("phone") == "fane")
        #expect(key("whisper") == "vaspar")
        #expect(key("quick") == "kvak")
        #expect(key("box") == "baks")
        #expect(key("cache") == "kaCe")
        #expect(key("config") == "kanfag")
        #expect(key("juice") == "gase")
        #expect(key("feature") == "faCare")
        #expect(key("know") == "na")
    }

    @Test func cyrillicRules() {
        #expect(key("джейсон") == "gasan")
        #expect(key("фетч") == "faC")
        #expect(key("щётка") == "Satka")
        #expect(key("ёжик") == "aSak")
        #expect(key("цвет") == "tsvat")
        #expect(key("объект") == "abakt")
    }

    @Test func unrelatedWordsStayFar() {
        #expect(distance("контроллер", "DictationController") > 5)
        #expect(distance("проект сервиса", "ProjectTermsService") > 3)
        #expect(distance("поправь", "PromptBuilder") > 3)
    }

    @Test func distanceStopsAtItsLimit() {
        let a = SoundKey.key("DictationController")
        let b = SoundKey.key("PromptBuilder")
        #expect(SoundKey.distance(a, b, limit: 1) > 1)
        #expect(SoundKey.distance(a, a, limit: 1) == 0)
    }
}

@Suite struct ScreenTermsTests {
    @Test func takesIdentifiersFilesHandlesAndNames() {
        let text = ScreenText(
            title: "DictationController.swift — saytype",
            focused: """
            final class DictationController {
                let projects: ProjectTermsService
                // TODO: use_auth_session and MAX_RETRY_COUNT from config.yaml
            }
            """,
            visible: [
                "@vlad_kovalskyi поправит WhisperKitEngine",
                "src/components/UserProfileCard.tsx",
                "shop-front, Kovalskyi",
            ]
        )
        let terms = ScreenTerms.extract(from: text)
        for expected in ["DictationController.swift", "DictationController", "ProjectTermsService", "use_auth_session",
                         "MAX_RETRY_COUNT", "config.yaml", "@vlad_kovalskyi", "WhisperKitEngine", "UserProfileCard.tsx",
                         "UserProfileCard", "shop-front", "Kovalskyi"] {
            #expect(terms.contains(expected), "\(expected)")
        }
        for skipped in ["saytype", "final", "class", "let", "projects", "TODO", "src", "components", "from", "and"] {
            #expect(!terms.contains(skipped), "\(skipped)")
        }
    }

    @Test func leavesOutLinksHashesAndEverydayWords() {
        let text = ScreenText(visible: [
            "https://github.com/vladislavkovalskyi/saytype-docs vlad@example.com",
            "agent-a7a06b5a4025024ad 3f9c2e1b-44aa",
            "built-in follow-up drag-and-drop e-mail",
            "Issues Actions Settings Pull requests Welcome",
            "GitHub useEffect Next.js ChatGPT",
            "self.phase value.dictionary DictionaryRewriter.cached",
            "github.com example.io",
        ])
        let terms = ScreenTerms.extract(from: text)
        #expect(terms == ["DictionaryRewriter"])
    }

    @Test func handlesAndScopes() {
        let terms = ScreenTerms.extract(from: ScreenText(visible: ["@kirill_dev написал", "@acme/shop-front", "@ab"]))
        #expect(terms.contains("@kirill_dev"))
        #expect(terms.contains("shop-front"))
        #expect(!terms.contains("@acme"))
        #expect(!terms.contains("@ab"))
    }

    @Test func pathsGiveFilesAndIdentifierFolders() {
        let terms = ScreenTerms.extract(from: ScreenText(focused: "Packages/SaytypeKit/Sources/VMCore/PromptBuilder.swift"))
        #expect(terms.contains("PromptBuilder.swift"))
        #expect(terms.contains("PromptBuilder"))
        #expect(terms.contains("SaytypeKit"))
        #expect(terms.contains("VMCore"))
        #expect(!terms.contains("Packages"))
    }

    @Test func focusedTextAndTitleOutrankTheRestOfTheWindow() {
        let text = ScreenText(
            title: "OrderService",
            focused: "fetchUserProfile",
            visible: ["InvoiceRecord InvoiceRecord", "CheckoutForm", "Kovalskyi"]
        )
        let terms = ScreenTerms.extract(from: text)
        #expect(Array(terms.prefix(2)).sorted() == ["OrderService", "fetchUserProfile"])
        #expect(terms[2] == "InvoiceRecord")
        #expect(terms.last == "Kovalskyi")
    }

    @Test func spellingFromTheFocusedFieldWins() {
        let terms = ScreenTerms.extract(from: ScreenText(focused: "useAuthSession", visible: ["use_auth_session"]))
        #expect(terms == ["useAuthSession"])
    }

    @Test func capsTheList() {
        let names = (0..<200).map { "someIdentifier\(String(UnicodeScalar(UInt8(65 + $0 % 26))))Part\($0 / 26)" }
        let terms = ScreenTerms.extract(from: ScreenText(visible: [names.joined(separator: " ")]))
        #expect(terms.count == ScreenTerms.limit)
    }

    @Test func kinds() {
        #expect(ScreenTerms.kind(of: "@vlad") == .handle)
        #expect(ScreenTerms.kind(of: "README.md") == .file)
        #expect(ScreenTerms.kind(of: "useAuthSession") == .identifier)
        #expect(ScreenTerms.kind(of: "Kovalskyi") == .name)
    }
}

@Suite struct ScreenTermMatcherTests {
    static let screen = ScreenTermMatcher(terms: [
        "DictationController", "ProjectTermsService.swift", "ProjectTermsService", "useAuthSession", "ScreenContextReader",
        "TermCanonicalizer", "WhisperKitEngine", "PromptBuilder", "MAX_RETRY_COUNT", "fetchUserProfile",
        "UserProfileCard.tsx", "UserProfileCard", "README.md", "FocusInspector", "SelectionReader", "isLoading",
        "@vlad_kovalskyi", "Kovalskyi",
    ])

    func fix(_ text: String) -> String { Self.screen.apply(to: text) }

    @Test func whatWhisperWroteBecomesTheScreenSpelling() {
        #expect(fix("Поправь диктишн контроллер, чтобы он читал экран.") == "Поправь DictationController, чтобы он читал экран.")
        #expect(fix("Открой project-therms-service.swift.") == "Открой ProjectTermsService.swift.")
        #expect(fix("Посмотри функцию useAufSession в конфиге.") == "Посмотри функцию useAuthSession в конфиге.")
        #expect(fix("Переименуй ScreenContextRider во что-нибудь короче.") == "Переименуй ScreenContextReader во что-нибудь короче.")
        #expect(fix("Добавь тест для термканоника лазер.") == "Добавь тест для TermCanonicalizer.")
        #expect(fix("Проверь WhisperKit Engine и Prompt Builder.") == "Проверь WhisperKitEngine и PromptBuilder.")
        #expect(fix("Где используется MaxRetroAccount.") == "Где используется MAX_RETRY_COUNT.")
        #expect(fix("Напиши Кириллу, что фич-юзер профил падает.") == "Напиши Кириллу, что fetchUserProfile падает.")
        #expect(fix("Обнови UserProfileCart.tsx.") == "Обнови UserProfileCard.tsx.")
        #expect(fix("Скинь ссылку на ridme.md.") == "Скинь ссылку на README.md.")
        #expect(fix("Focus Inspector возвращает неправильное окно.") == "FocusInspector возвращает неправильное окно.")
        #expect(fix("Selection Reader копирует через буфер обмена.") == "SelectionReader копирует через буфер обмена.")
    }

    @Test func spokenMarksJoinTheName() {
        #expect(fix("открой проджект термс сервис точка свифт") == "открой ProjectTermsService.swift")
        #expect(fix("открой юзер профайл кард") == "открой UserProfileCard")
    }

    @Test func caseEndingsAndPunctuation() {
        #expect(fix("ошибка в диктейшн контроллере.") == "ошибка в DictationController.")
        #expect(fix("(диктейшн контроллер)") == "(DictationController)")
        #expect(fix("«Диктейшн контроллер» не работает") == "«DictationController» не работает")
    }

    @Test func wordsTheMatchDoesNotNeedStayOut() {
        #expect(fix("да диктишн контроллер") == "да DictationController")
        #expect(fix("дай диктишн контроллер") == "дай DictationController")
        #expect(fix("диктишн контроллер и промпт билдер") == "DictationController и PromptBuilder")
        #expect(fix("диктишн, контроллер") == "диктишн, контроллер")
    }

    @Test func functionWordsOnlyForShortParts() {
        #expect(fix("проверь из лоадинг") == "проверь isLoading")
        #expect(fix("юзер и профайл кард") == "юзер и профайл кард")
    }

    @Test func handlesNeedTheAt() {
        #expect(fix("напиши собака влад ковальский") == "напиши @vlad_kovalskyi")
        #expect(fix("напиши @vlad_kovalsky") == "напиши @vlad_kovalskyi")
        #expect(fix("напиши влад ковальский") == "напиши влад ковальский")
    }

    @Test func namesOnlyFromLatinThatSoundsTheSame() {
        #expect(fix("Спроси Kovalsky про релиз") == "Спроси Kovalskyi про релиз")
        #expect(fix("Спроси Ковальского про релиз") == "Спроси Ковальского про релиз")
        #expect(fix("Спроси Kowalski про релиз") == "Спроси Kowalski про релиз")
    }

    @Test func ordinarySpeechStaysAsItIs() {
        let sentences = [
            "Поправь контроллер, он плохо читает экран.",
            "Проект сервиса запустился, но диктовка не работает.",
            "Сегодня созвон с командой в три часа, потом ревью.",
            "Фокус не на том окне, выбери другое.",
            "Прочитай выделенный текст и сделай ревью.",
            "Контроллер диктовки отдаёт пустой текст.",
            "Проверь сервис и термины в проекте.",
            "Иван Петров прислал файл с настройками.",
            "The dictation starts when the key goes down.",
            "Please review the profile card before the release.",
            "Читай ридми внимательно.",
            "Юзер профайл открывается долго.",
        ]
        for sentence in sentences {
            #expect(fix(sentence) == sentence)
        }
    }

    /// Sentences the first version rewrote, with saytype's own identifiers as the screen
    /// (`vm-bench context text`).
    @Test func proseThatSoundsLikeCodeStays() {
        let matcher = ScreenTermMatcher(terms: [
            "bestRun", "isAlnum", "systemPrompt", "isSpace", "LanguageModel", "SpeechLanguage", "addFileName", "KeyPoster",
            "HistoryStats", "WordFilter", "SaytypeKit", "inSentence", "WhisperKit", "Reason", "builtIn", "BuiltInDictionary",
            "isCode", "isBusy", "copySettings",
        ])
        let sentences = [
            "Parakeet v3 быстрее и на чистом русском точнее.",
            "Никто из сильных конкурентов так не делает.",
            "У режима свой системный промпт.",
            "Функция берёт из базы заявки со статусом new.",
            "Needs a language model (Model → Rewrites).",
            "Pick yours in Text → Speech language.",
            "If a file name from your dictation is missing, it inserts your text as dictated.",
            "It copies the selection and puts your clipboard back.",
            "Dictation history stays in a local JSON file.",
            "Word filters.",
            "Click the saytype icon in the menu bar.",
            "The phrase works alone or inside a sentence.",
            "Whisper can translate on its own.",
            "Speak Russian with English terms?",
            "The built-in microphone is fine.",
            "Каждое третье слово — английский термин или имя из кода.",
            "Функция берёт из базы заявки.",
            "Настройки лежат в vladislavkovalskyi.github.io/saytype/com/settings.",
            "Choose Russian: the built-in dictionary turns «юз эффект» into useEffect.",
        ]
        for sentence in sentences {
            #expect(matcher.apply(to: sentence) == sentence)
        }
        // Inside Russian speech the capitalised parts are a term, lowercase English words are not.
        #expect(matcher.apply(to: "Поправь Language Model в настройках.") == "Поправь LanguageModel в настройках.")
        #expect(matcher.apply(to: "Плашка пишет «Language model is off».") == "Плашка пишет «Language model is off».")
    }

    @Test func exactTermsAreLeftAlone() {
        let text = "Поправь DictationController и README.md."
        #expect(fix(text) == text)
    }

    @Test func singlePartTermsNeverComeFromCyrillic() {
        let matcher = ScreenTermMatcher(terms: ["Controller", "Session", "Grafana"])
        #expect(matcher.apply(to: "контроллер сессия графана") == "контроллер сессия графана")
    }
}

@Suite struct ScreenContextPipelineTests {
    @Test func theFormatterUsesScreenTermsAfterTheDictionary() {
        var settings = AppSettings()
        settings.dictionary = [DictionaryEntry(heard: "диктишн контроллер", written: "MyController")]
        let screen = ScreenTermMatcher(terms: ["DictationController", "PromptBuilder"])
        let result = DictationPipeline.format(
            Transcript(text: "Поправь диктишн контроллер и промпт билдер."),
            settings: settings,
            mode: DictationMode(id: DictationMode.standardID),
            screen: screen
        )
        #expect(result.text == "Поправь MyController и PromptBuilder.")
    }

    @Test func offWithLatinTerms() {
        var settings = AppSettings()
        settings.latinTerms = false
        let screen = ScreenTermMatcher(terms: ["PromptBuilder"])
        let text = TextFormatter.format(Transcript(text: "Поправь промпт билдер."), settings: settings, screen: screen)
        #expect(text == "Поправь промпт билдер.")
    }

    @Test func namesKeepTheirCaseInLowercaseStyle() {
        var settings = AppSettings()
        settings.letterCase = .lowercase
        let screen = ScreenTermMatcher(terms: ["Kovalskyi", "PromptBuilder"])
        let text = TextFormatter.format(Transcript(text: "Спроси Kovalsky про промпт билдер."), settings: settings, screen: screen)
        #expect(text == "спроси Kovalskyi про PromptBuilder.")
    }

    @Test func withoutScreenTermsNothingChanges() {
        let settings = AppSettings()
        let transcript = Transcript(text: "Поправь диктишн контроллер.")
        let mode = DictationMode(id: DictationMode.standardID)
        #expect(DictationPipeline.format(transcript, settings: settings, mode: mode).text
            == DictationPipeline.format(transcript, settings: settings, mode: mode, screen: ScreenTermMatcher(terms: [])).text)
    }
}

@Suite struct ScreenContextPerformanceTests {
    /// A full window: about 20 000 characters of code and chat, the reader's limit.
    static let window: ScreenText = {
        let code = (0..<400).map { "let value\($0 % 7) = fetch\(["User", "Order", "Cart", "Profile"][$0 % 4])Item\($0 % 50)(from: session)" }
        let chat = Array(repeating: "Кирилл: посмотри, пожалуйста, ProjectTermsService.swift и TermCanonicalizer, там падает сборка.", count: 60)
        return ScreenText(title: "DictationController.swift — saytype", focused: code.joined(separator: "\n"), visible: chat)
    }()

    @Test func extractionAndMatchingStayFast() {
        let terms = ScreenTerms.extract(from: Self.window)
        let matcher = ScreenTermMatcher(terms: terms)
        let dictation = DeveloperPerformanceTests.dictation
        let extract = DeveloperPerformanceTests.median(20) { _ = ScreenTerms.extract(from: Self.window) }
        let build = DeveloperPerformanceTests.median(20) { _ = ScreenTermMatcher(terms: terms) }
        let apply = DeveloperPerformanceTests.median(20) { _ = matcher.apply(to: dictation) }
        print(String(format: "perf screen: %d characters → %d terms in %.2f ms, matcher %.2f ms, %d words matched in %.2f ms",
                     Self.window.characterCount, terms.count, extract, build, Words.split(dictation).count, apply))
        #expect(terms.count == ScreenTerms.limit)
        #expect(extract + build + apply < 250)
    }
}
