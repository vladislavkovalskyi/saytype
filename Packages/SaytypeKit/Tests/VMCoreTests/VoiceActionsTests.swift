import Foundation
import Testing
@testable import VMCore

@Suite struct VoiceActionsTests {
    typealias Language = AppSettings.SpeechLanguage

    /// What an utterance should come out as.
    struct Expected: CustomStringConvertible {
        let text: String
        /// Text was selected by Accessibility when recording started.
        var selection = false
        let source: VoiceAction.Source
        let reference: VoiceAction.Reference
        let job: VoiceAction.Job
        var send = false

        var description: String { "\(text) [selection: \(selection)]" }
    }

    static func translate(_ code: String) -> VoiceAction.Job { .translate(Language(rawValue: code)) }

    // MARK: Corpus

    /// The owner's phrases from the request, then Russian and English phrasings of translation,
    /// then other instructions.
    static let positives: [Expected] = [
        // The owner's own words.
        Expected(text: "Translate the clipboard text to English.", source: .clipboard, reference: .named, job: translate("en")),
        Expected(text: "Can you translate this to English, please?", source: .selection, reference: .pointer, job: translate("en")),
        Expected(text: "Translate to English.", selection: true, source: .selection, reference: .implied, job: translate("en")),
        Expected(text: "Or translate to English.", selection: true, source: .selection, reference: .implied, job: translate("en")),
        Expected(text: "Translate the highlighted text into Spanish.", source: .selection, reference: .named, job: translate("es")),
        Expected(text: "Translate the text into Spanish.", source: .selection, reference: .pointer, job: translate("es")),

        // Russian: the selection.
        Expected(text: "Переведи выделенное на испанский.", source: .selection, reference: .named, job: translate("es")),
        Expected(text: "Переведи выделенный текст на английский язык.", source: .selection, reference: .named, job: translate("en")),
        Expected(text: "Переведи выделенное на английском.", source: .selection, reference: .named, job: translate("en")),
        Expected(text: "Не мог бы ты перевести выделенное на итальянский?", source: .selection, reference: .named, job: translate("it")),
        Expected(text: "Выделенное переведи на английский.", source: .selection, reference: .named, job: translate("en")),
        Expected(text: "Переведи с русского на английский выделенный текст.", source: .selection, reference: .named, job: translate("en")),
        Expected(text: "Переведи выделенное на украинский.", source: .selection, reference: .named, job: translate("uk")),
        Expected(text: "Переведи выделенное на китайский.", source: .selection, reference: .named, job: translate("zh")),
        Expected(text: "Переведи выделенное на норвежский.", source: .selection, reference: .named, job: translate("no")),
        Expected(text: "Переведи на иврит то, что выделено.", source: .selection, reference: .named, job: translate("he")),
        Expected(text: "Эээ, переведи выделенное на английский.", source: .selection, reference: .named, job: translate("en")),
        Expected(text: "Переведи-ка выделенное на немецкий.", source: .selection, reference: .named, job: translate("de")),

        // Russian: the clipboard.
        Expected(text: "Переведи, пожалуйста, текст из буфера обмена на английский.", source: .clipboard, reference: .named, job: translate("en")),
        Expected(text: "Переведи текст из буфера на испанский.", source: .clipboard, reference: .named, job: translate("es")),
        Expected(text: "Переведи скопированный текст на немецкий.", source: .clipboard, reference: .named, job: translate("de")),
        Expected(text: "Переведи на французский то, что в буфере обмена.", source: .clipboard, reference: .named, job: translate("fr")),
        Expected(text: "Переведи на английский то, что я скопировал.", source: .clipboard, reference: .named, job: translate("en")),
        Expected(text: "Переведи текст, который я скопировал, на испанский.", source: .clipboard, reference: .named, job: translate("es")),
        Expected(text: "Текст из буфера обмена переведи на испанский.", source: .clipboard, reference: .named, job: translate("es")),
        Expected(text: "Переведи буфер обмена на польский.", source: .clipboard, reference: .named, job: translate("pl")),
        Expected(text: "Слушай, переведи скопированное на португальский.", source: .clipboard, reference: .named, job: translate("pt")),

        // Russian: pointing at the selection, or nothing.
        Expected(text: "Переведи это на английский.", source: .selection, reference: .pointer, job: translate("en")),
        Expected(text: "Переведи мне это на английский, пожалуйста.", source: .selection, reference: .pointer, job: translate("en")),
        Expected(text: "Можешь перевести это на испанский?", source: .selection, reference: .pointer, job: translate("es")),
        Expected(text: "Это переведи на английский.", source: .selection, reference: .pointer, job: translate("en")),
        Expected(text: "Переведи этот текст на японский.", source: .selection, reference: .pointer, job: translate("ja")),
        Expected(text: "Переведи на испанский.", selection: true, source: .selection, reference: .implied, job: translate("es")),
        Expected(text: "Переведи по-английски.", selection: true, source: .selection, reference: .implied, job: translate("en")),
        Expected(text: "Пожалуйста, переведи на турецкий язык.", selection: true, source: .selection, reference: .implied, job: translate("tr")),

        // English.
        Expected(text: "Please translate the selected text into German.", source: .selection, reference: .named, job: translate("de")),
        Expected(text: "Translate what I copied to French.", source: .clipboard, reference: .named, job: translate("fr")),
        Expected(text: "Translate what's in my clipboard to Japanese.", source: .clipboard, reference: .named, job: translate("ja")),
        Expected(text: "Could you please translate the selection into Portuguese?", source: .selection, reference: .named, job: translate("pt")),
        Expected(text: "Translate the text in my clipboard into Korean.", source: .clipboard, reference: .named, job: translate("ko")),
        Expected(text: "Translate from Russian to English the clipboard text.", source: .clipboard, reference: .named, job: translate("en")),
        Expected(text: "Translate the selected text into Norwegian Nynorsk.", source: .selection, reference: .named, job: translate("nn")),
        Expected(text: "Translate it into Spanish.", source: .selection, reference: .pointer, job: translate("es")),
        Expected(text: "I need you to translate this into Italian.", source: .selection, reference: .pointer, job: translate("it")),
        Expected(text: "Translate this into Mandarin.", source: .selection, reference: .pointer, job: translate("zh")),
        Expected(text: "Hey, can you translate that to Ukrainian?", source: .selection, reference: .pointer, job: translate("uk")),

        // No language named.
        Expected(text: "Переведи выделенное.", source: .selection, reference: .named, job: .translateUnnamed),
        Expected(text: "Переведи это.", source: .selection, reference: .pointer, job: .translateUnnamed),
        Expected(text: "Translate the clipboard.", source: .clipboard, reference: .named, job: .translateUnnamed),

        // "…и отправь".
        Expected(text: "Переведи выделенное на испанский и отправь.", source: .selection, reference: .named, job: translate("es"), send: true),
        Expected(text: "Translate this to English and send it.", source: .selection, reference: .pointer, job: translate("en"), send: true),

        // More than a translation: the instruction goes to the model as said.
        Expected(text: "Переведи выделенное на испанский и сделай вежливее.", source: .selection, reference: .named, job: .instruct),
        Expected(text: "Сократи выделенный текст до двух предложений.", source: .selection, reference: .named, job: .instruct),
        Expected(text: "Перефразируй текст из буфера.", source: .clipboard, reference: .named, job: .instruct),
        Expected(text: "Исправь ошибки в выделенном тексте.", source: .selection, reference: .named, job: .instruct),
        Expected(text: "Исправь выделенный текст.", source: .selection, reference: .named, job: .instruct),
        Expected(text: "Сделай выделенный текст более формальным.", source: .selection, reference: .named, job: .instruct),
        Expected(text: "Преврати выделенное в список.", source: .selection, reference: .named, job: .instruct),
        Expected(text: "Из выделенного сделай список.", source: .selection, reference: .named, job: .instruct),
        Expected(text: "Перепиши выделенное в стиле Пушкина.", source: .selection, reference: .named, job: .instruct),
        Expected(text: "Упрости скопированный текст.", source: .clipboard, reference: .named, job: .instruct),
        Expected(text: "Сократи это.", source: .selection, reference: .pointer, job: .instruct),
        Expected(text: "Перепиши этот абзац короче.", source: .selection, reference: .pointer, job: .instruct),
        Expected(text: "Исправь опечатки в этом тексте.", source: .selection, reference: .pointer, job: .instruct),
        Expected(text: "Сократи.", selection: true, source: .selection, reference: .implied, job: .instruct),
        Expected(text: "Перепиши короче.", selection: true, source: .selection, reference: .implied, job: .instruct),
        Expected(text: "Исправь опечатки.", selection: true, source: .selection, reference: .implied, job: .instruct),
        Expected(text: "Сократи до одного предложения.", selection: true, source: .selection, reference: .implied, job: .instruct),
        Expected(text: "Fix the typos in the selected text.", source: .selection, reference: .named, job: .instruct),
        Expected(text: "Summarize the text in my clipboard.", source: .clipboard, reference: .named, job: .instruct),
        Expected(text: "Make the selected text more formal.", source: .selection, reference: .named, job: .instruct),
        Expected(text: "Rewrite what I copied in a friendlier tone.", source: .clipboard, reference: .named, job: .instruct),
        Expected(text: "Rephrase this in a friendlier tone.", source: .selection, reference: .pointer, job: .instruct),
        Expected(text: "Shorten this to one sentence.", source: .selection, reference: .pointer, job: .instruct),
        Expected(text: "Proofread.", selection: true, source: .selection, reference: .implied, job: .instruct),
        Expected(text: "Fix the grammar.", selection: true, source: .selection, reference: .implied, job: .instruct),
        Expected(text: "Сделай это короче.", source: .selection, reference: .pointer, job: .instruct),
        Expected(text: "Make it more formal.", source: .selection, reference: .pointer, job: .instruct),
        Expected(text: "Сделай вежливее.", selection: true, source: .selection, reference: .implied, job: .instruct),
        Expected(text: "Переведи весь текст на английский.", source: .selection, reference: .pointer, job: translate("en")),
        Expected(text: "Можешь, пожалуйста, перевести вот это на английский?", source: .selection, reference: .pointer, job: translate("en")),
        Expected(text: "Ты можешь перевести текст в буфере на английский?", source: .clipboard, reference: .named, job: translate("en")),
        Expected(text: "Переведи выделенное на английский. Спасибо.", source: .selection, reference: .named, job: translate("en")),
        Expected(text: "Translate the selected text into Spanish, thank you.", source: .selection, reference: .named, job: translate("es")),
        Expected(text: "Переведи содержимое буфера обмена на английский.", source: .clipboard, reference: .named, job: translate("en")),
        Expected(text: "Translate the contents of my clipboard to German.", source: .clipboard, reference: .named, job: translate("de")),
        Expected(text: "Переведи английский текст на русский.", source: .selection, reference: .pointer, job: translate("ru")),
        Expected(text: "Translate the Spanish text into English.", source: .selection, reference: .pointer, job: translate("en")),
        Expected(text: "Переведи с английского.", selection: true, source: .selection, reference: .implied, job: .translateUnnamed),
    ]

    /// Dictations that must stay dictations: chat messages, instructions to coding agents,
    /// questions. Each is checked with and without a selection unless noted.
    static let negatives: [(text: String, withSelection: Bool)] = [
        // Chat.
        ("Переведи мне деньги на карту.", true),
        ("Переведи деньги маме до пятницы.", true),
        ("Можешь перевести деньги на карту?", true),
        ("Переведи его на другую должность.", true),
        ("Can you translate this to English for me by Friday?", true),
        ("Please translate the document into English.", true),
        ("Как перевести это на английский?", true),
        ("We need to translate the app into Spanish.", true),
        ("Перевести это на английский будет сложно.", true),
        ("Отправь выделенное Васе.", true),
        ("Я скопировал текст в буфер обмена.", true),
        // Instructions to a coding agent about selections and the clipboard.
        ("Поправь вставку из буфера обмена в карточке.", true),
        ("Сократи задержку при чтении буфера обмена.", true),
        ("Исправь баг с выделенным текстом.", true),
        ("Сделай так, чтобы выделенный текст подсвечивался жёлтым.", true),
        ("Исправь выделенный текст в карточке, он не подсвечивается.", true),
        ("Перепиши компонент, который читает буфер обмена.", true),
        ("Поправь буфер обмена в Paster.", true),
        ("Fix the clipboard restore in Paster.", true),
        ("Translate the clipboard manager docs.", true),
        ("Make the selected tab bold.", true),
        ("Сделай скриншот выделенной области.", true),
        ("Скопируй выделенный текст в буфер обмена.", true),
        ("Вставь текст из буфера.", true),
        ("Перепиши README на английский.", true),
        ("Translate button should open the language menu.", true),
        ("Переведи этот баг в статус готово.", true),
        ("Fix this bug before the release.", true),
        ("Can you fix it?", true),
        ("Исправь это.", true),
        ("Сделай это.", true),
        ("Сделай это до пятницы.", true),
        ("Make it work.", true),
        ("Сделай это в два раза быстрее.", true),
        ("Improve this.", true),
        ("Проверь выделенный текст.", true),
        ("Объясни выделенное.", true),
        ("Это переведи потом.", true),
        // Not a language, a subordinate clause, two sources, too long, a voice command.
        ("Переведи это на человеческий.", true),
        ("Переведи выделенный текст на английский так, чтобы звучало естественно.", true),
        ("Переведи выделенное и то, что в буфере, на английский.", true),
        ("Переведи выделенное на английский, а потом сделай из этого письмо для всей команды и добавь в конец подпись с моим именем и ссылкой на репозиторий.", true),
        ("Переведи выделенное на английский. Новая строка. Спасибо.", true),
        // Nothing selected: an instruction without a source is a dictation.
        ("Переведи на английский.", false),
        ("Translate to English.", false),
        ("Сократи.", false),
        ("Переведи.", true),
        ("Переведи текст песни на английский.", true),
        ("Скажи это по-английски.", true),
        ("Исправь опечатки.", false),
    ]

    @Test func positives() {
        for expected in Self.positives {
            let action = VoiceActions.detect(expected.text, selectionAtStart: expected.selection)
            #expect(action?.source == expected.source, "\(expected)")
            #expect(action?.reference == expected.reference, "\(expected)")
            #expect(action?.job == expected.job, "\(expected)")
            #expect(action?.send == expected.send, "\(expected)")
        }
    }

    @Test func negatives() {
        for (text, withSelection) in Self.negatives {
            #expect(VoiceActions.detect(text, selectionAtStart: false) == nil, "\(text)")
            if withSelection {
                #expect(VoiceActions.detect(text, selectionAtStart: true) == nil, "\(text) [selection]")
            }
        }
    }

    /// A named source or a pointer does not depend on what was selected at key press.
    @Test func explicitSourcesIgnoreTheSelectionAtStart() {
        for expected in Self.positives where expected.reference != .implied {
            #expect(VoiceActions.detect(expected.text, selectionAtStart: !expected.selection) == VoiceActions.detect(expected.text, selectionAtStart: expected.selection), "\(expected)")
        }
    }

    @Test func corpusSize() {
        #expect(Self.positives.count >= 70)
        #expect(Self.negatives.count >= 40)
    }

    // MARK: Instruction

    @Test func instructionIsTheWordsAsSaidWithoutTheSend() {
        #expect(VoiceActions.detect("Переведи выделенное на испанский, и отправь.", selectionAtStart: false)?.instruction == "Переведи выделенное на испанский")
        #expect(VoiceActions.detect("Сократи выделенный текст до двух предложений.", selectionAtStart: false)?.instruction == "Сократи выделенный текст до двух предложений.")
        #expect(VoiceActions.detect("Translate this to English and send it", selectionAtStart: false)?.instruction == "Translate this to English")
    }

    @Test func sendIsOnlyACommandWithVoiceCommandsOn() {
        let action = VoiceActions.detect("Переведи выделенное на испанский и отправь", selectionAtStart: false, sendCommand: false)
        #expect(action?.send == false)
        #expect(action?.job == .instruct)
        #expect(action?.instruction == "Переведи выделенное на испанский и отправь")
        // Voice commands off: "новая строка" is just words, and then too many of them.
        #expect(VoiceActions.detect("Переведи выделенное на английский. Новая строка.", selectionAtStart: false, sendCommand: false)?.job == .instruct)
    }

    @Test func sendAloneIsNotAnAction() {
        #expect(VoiceActions.detect("Отправь.", selectionAtStart: true) == nil)
        #expect(VoiceActions.detect("Send it.", selectionAtStart: true) == nil)
    }

    // MARK: Languages

    /// Every one of Whisper's languages can be named in Russian, in the cases people use, and in
    /// English, and no name is taken by another language.
    @Test func everyLanguageByName() {
        let russian = Locale(identifier: "ru")
        let english = Locale(identifier: "en")
        for code in Language.whisperCodes {
            let language = Language(rawValue: code)
            let name = english.localizedString(forLanguageCode: code)!.lowercased()
            #expect(VoiceActions.detect("Translate the clipboard into \(name).", selectionAtStart: false)?.job == .translate(language), "\(name)")
            let russianName = russian.localizedString(forLanguageCode: code)!.lowercased().split(separator: " ")[0]
            var forms = [String(russianName)]
            if russianName.hasSuffix("ий") {
                let stem = russianName.dropLast(2)
                forms += ["\(stem)ом", "\(stem)ого"]
            }
            for form in forms {
                #expect(VoiceActions.detect("Переведи выделенное на \(form)", selectionAtStart: false)?.job == .translate(language), "\(form)")
            }
        }
        #expect(VoiceActions.detect("Переведи выделенное по-испански", selectionAtStart: false)?.job == Self.translate("es"))
        #expect(VoiceActions.detect("Переведи выделенное на голландский", selectionAtStart: false)?.job == Self.translate("nl"))
        #expect(VoiceActions.detect("Переведи выделенное на фарси", selectionAtStart: false)?.job == Self.translate("fa"))
        #expect(VoiceActions.detect("Translate the selection into Farsi", selectionAtStart: false)?.job == Self.translate("fa"))
    }

    @Test func sourceLanguageIsNotTheTarget() {
        #expect(VoiceActions.detect("Переведи выделенное с английского на русский", selectionAtStart: false)?.job == Self.translate("ru"))
        #expect(VoiceActions.detect("Translate this from Spanish into English", selectionAtStart: false)?.job == Self.translate("en"))
    }

    // MARK: Default target

    @Test func unnamedTargetGoesAcrossScripts() {
        // Russian text: into the translate everything language.
        #expect(VoiceActions.defaultTarget(for: "Привет, как дела?", instruction: "переведи выделенное", translateTarget: .english) == .english)
        // English text and a Russian instruction: into Russian.
        #expect(VoiceActions.defaultTarget(for: "Hello, how are you?", instruction: "переведи выделенное", translateTarget: .english) == .russian)
        // English text and an English instruction: the model decides.
        #expect(VoiceActions.defaultTarget(for: "Hello, how are you?", instruction: "translate the selection", translateTarget: .english) == nil)
        // Translate everything into Ukrainian, English text: Ukrainian.
        #expect(VoiceActions.defaultTarget(for: "Hello there", instruction: "translate this", translateTarget: Language(rawValue: "uk")) == Language(rawValue: "uk"))
        // Chinese text, target English.
        #expect(VoiceActions.defaultTarget(for: "你好，世界", instruction: "переведи это", translateTarget: .english) == .english)
        // No letters at all.
        #expect(VoiceActions.defaultTarget(for: "12 345", instruction: "переведи", translateTarget: .english) == nil)
    }

    // MARK: Request

    @Test func translationRequestNamesTheTarget() {
        let spanish = RewriteRequest.translation(into: Language(rawValue: "es"))
        #expect(spanish.style == .none)
        #expect(spanish.translate)
        #expect(spanish.targetLanguage == "Spanish")
        #expect(!spanish.answersInEnglish)
        #expect(spanish.systemPrompt.contains("Write the answer in Spanish."))
        #expect(RewriteRequest.translation(into: .english).answersInEnglish)
    }

    // MARK: History

    @Test func historyCountsTheSpokenWordsOfAnAction() {
        let now = Date()
        let action = DictationRecord(text: Array(repeating: "word", count: 300).joined(separator: " "), raw: "Translate the clipboard text to English.", appName: nil, bundleID: nil, duration: 3, date: now, action: .init(source: .clipboard, target: "en"))
        let dictation = DictationRecord(text: "Привет, как дела у тебя сегодня", raw: "привет как дела у тебя сегодня", appName: nil, bundleID: nil, duration: 2, date: now)
        #expect(action.spokenWordCount == 6)
        #expect(dictation.spokenWordCount == 6)
        #expect(HistoryStats(records: [action, dictation], now: now).wordsToday == 12)
    }

    @Test func historyWithoutActionsStillDecodes() throws {
        let json = #"[{"id":"6F9A3C1E-7D2B-4E5F-9A1B-2C3D4E5F6A7B","text":"Привет","raw":"привет","duration":1.2,"date":"2026-09-20T10:00:00Z"}]"#
        let records = try JSONDecoder.history.decode([DictationRecord].self, from: Data(json.utf8))
        #expect(records.first?.action == nil)
        let record = DictationRecord(text: "Hola", raw: "переведи выделенное на испанский", appName: nil, bundleID: nil, duration: 2, date: Date(timeIntervalSince1970: 0), action: .init(source: .selection, target: "es"))
        let decoded = try JSONDecoder.history.decode(DictationRecord.self, from: JSONEncoder.history.encode(record))
        #expect(decoded == record)
    }

    // MARK: Settings

    @Test func settingIsOnByDefaultAndSurvivesARoundTrip() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"voiceCommands": true}"#.utf8))
        #expect(old.voiceActions)
        var settings = AppSettings()
        settings.voiceActions = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(!decoded.voiceActions)
    }

    // MARK: Speed

    @Test func detectionIsCheap() {
        let long = Array(repeating: "Переведи выделенное на испанский и сделай вежливее", count: 3).joined(separator: " ")
        let start = Date()
        for _ in 0..<200 {
            _ = VoiceActions.detect("Переведи, пожалуйста, текст из буфера обмена на английский.", selectionAtStart: true)
            _ = VoiceActions.detect(long, selectionAtStart: true)
        }
        #expect(Date().timeIntervalSince(start) / 400 < 0.005)
    }
}
