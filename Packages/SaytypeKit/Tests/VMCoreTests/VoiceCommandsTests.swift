import Foundation
import Testing
@testable import VMCore

@Suite struct VoiceCommandsTests {
    let settings = AppSettings()

    func format(_ text: String, _ settings: AppSettings? = nil, mode: DictationMode? = nil) -> PipelineResult {
        let settings = settings ?? self.settings
        return DictationPipeline.format(Transcript(text: text), settings: settings, mode: mode ?? settings.standardMode)
    }

    // MARK: Breaks

    @Test func punctuatedLineBreak() {
        #expect(VoiceCommands.parse("Привет. Новая строка. Как дела?") == [.text("Привет."), .command(.newLine), .text("Как дела?")])
        #expect(format("Привет. Новая строка. Как дела?").text == "Привет.\nКак дела?")
        #expect(format("Привет, с новой строки, как дела?").text == "Привет\nКак дела?")
        #expect(format("Hello. New line. How are you?").text == "Hello.\nHow are you?")
    }

    @Test func unpunctuatedLineBreakCapitalizesTheNewLine() {
        #expect(format("привет новая строка как дела").text == "привет\nКак дела")
        #expect(format("hello new line how are you").text == "hello\nHow are you")
    }

    @Test func paragraphs() {
        #expect(format("Первый пункт готов. Новый абзац. Второй пункт.").text == "Первый пункт готов.\n\nВторой пункт.")
        #expect(format("Итак. С нового абзаца. Дальше.").text == "Итак.\n\nДальше.")
        // A paragraph right after a line break is still one empty line, not two.
        #expect(format("Раз. Новая строка. Новый абзац. Два.").text == "Раз.\n\nДва.")
        #expect(format("Раз. New paragraph. Два.").text == "Раз.\n\nДва.")
    }

    @Test func adjacentCommands() {
        #expect(format("Раз. Новая строка новая строка. Два.").text == "Раз.\n\nДва.")
    }

    @Test func breaksAtTheEdgesAreDropped() {
        #expect(format("Новая строка. Привет.").text == "Привет.")
        #expect(format("Привет. Новый абзац.").text == "Привет.")
    }

    @Test func termsKeepTheirCaseAtTheStartOfALine() {
        #expect(format("Раз. Новая строка. useEffect поправь.").text == "Раз.\nuseEffect поправь.")
    }

    @Test func lowercaseModesStayLowercase() {
        var chat = settings
        chat.isChatStyle = true
        #expect(format("Привет. Новая строка. Как дела?", chat).text == "привет\nкак дела")
        let message = settings.modes.first { $0.id == DictationMode.messageID }!
        #expect(format("Привет, новая строка, как дела?", mode: message).text == "привет\nкак дела")
        var none = settings
        none.punctuationStyle = .none
        #expect(format("привет. новая строка. как дела?", none).text == "привет\nкак дела")
    }

    // MARK: Delete

    @Test func deletesTheSentenceBefore() {
        #expect(format("Купи молоко. Купи хлеб. Удали последнее предложение. Купи сыр.").text == "Купи молоко. Купи сыр.")
        #expect(format("Купи молоко. Удалить последнее предложение.").text == "")
        #expect(format("Buy milk. Buy bread. Delete the last sentence.").text == "Buy milk.")
        #expect(format("купи молоко купи хлеб удали последнее предложение купи сыр").text == "купи сыр")
    }

    @Test func deleteInChatStyleUsesWhisperSentences() {
        var chat = settings
        chat.isChatStyle = true
        #expect(format("Го завтра. Я поздно. Удали последнее предложение. Я в семь.", chat).text == "го завтра я в семь")
    }

    @Test func deleteAfterABreakRemovesTheSentenceBeforeIt() {
        #expect(format("Раз. Новая строка. Два. Удали последнее предложение. Три.").text == "Раз.\nТри.")
        #expect(format("Раз. Два. Новая строка. Удали последнее предложение. Три.").text == "Раз. Три.")
    }

    @Test func droppingLastSentence() {
        #expect(VoiceCommands.droppingLastSentence("Раз. Два!") == "Раз.")
        #expect(VoiceCommands.droppingLastSentence("Раз? Два.") == "Раз?")
        #expect(VoiceCommands.droppingLastSentence("Одна фраза") == "")
        #expect(VoiceCommands.droppingLastSentence("Раз.\nДва.") == "Раз.\n")
        #expect(VoiceCommands.droppingLastSentence("Поправь Next.js конфиг. Задеплой на Vercel.") == "Поправь Next.js конфиг.")
        #expect(VoiceCommands.droppingLastSentence("План:\n1. Поправь Header.\n2. Задеплой.") == "План:\n1. Поправь Header.\n")
        #expect(VoiceCommands.droppingLastSentence("Он сказал «Привет!» Потом ушёл.") == "Он сказал «Привет!»")
    }

    // MARK: Send

    @Test func sendOnlyAsTheLastWords() {
        let sent = format("Напиши Васе, что я опоздаю. Отправь.")
        #expect(sent.text == "Напиши Васе, что я опоздаю.")
        #expect(sent.send)
        #expect(format("Хорошо, отправь").send)
        #expect(format("See you tomorrow. Send it.") == PipelineResult(text: "See you tomorrow.", send: true))
        #expect(format("я буду в семь отправить") == PipelineResult(text: "я буду в семь", send: true))

        let text = format("Отправь письмо Васе.")
        #expect(text.text == "Отправь письмо Васе.")
        #expect(!text.send)
    }

    @Test func sendAloneSendsNothing() {
        #expect(format("Отправь.") == PipelineResult(text: "", send: true))
    }

    // MARK: Quotes

    @Test func quotes() {
        #expect(format("Он сказал открой кавычки привет закрой кавычки и ушёл.").text == "Он сказал «привет» и ушёл.")
        #expect(format("Фильм называется, открой кавычки, Брат, закрой кавычки.").text == "Фильм называется «Брат».")
        #expect(format("He said open quote hello there close quote and left.").text == "He said \"hello there\" and left.")
        #expect(format("Открой кавычки. Стоп! Закрой кавычки. Так и написано.").text == "«Стоп!». Так и написано.")
    }

    @Test func unpairedQuoteStaysText() {
        let text = "Открой кавычки в этом файле."
        #expect(VoiceCommands.parse(text) == [.text(text)])
    }

    @Test func commandsOffKeepEverything() {
        var off = settings
        off.voiceCommands = false
        #expect(format("Привет. Новая строка. Как дела? Отправь.", off) == PipelineResult(text: "Привет. Новая строка. Как дела? Отправь."))
    }

    // MARK: Ordinary sentences

    /// Sentences with command words that must come back exactly as they were.
    static let ordinary = [
        "Добавь новую строку в таблицу.",
        "добавь новую строку в таблицу",
        "Это новая строка кода.",
        "это новая строка кода",
        "Новый абзац в договоре нужно переписать.",
        "новый абзац в договоре",
        "Новая строка кода не компилируется.",
        "В таблице появилась новая строка.",
        "Каждый пункт пиши с новой строки.",
        "Начни с новой строки, пожалуйста.",
        "С новой строки начинается цитата.",
        "Там новая строка, а не старая.",
        "Новая строка, а не старая.",
        "Новый абзац, который ты прислал, хороший.",
        "Вставь новый абзац после введения.",
        "Отправь письмо Васе.",
        "отправь письмо васе",
        "Не знаю, что отправить.",
        "Что мне отправить?",
        "Документы готовы. Отправить?",
        "Можешь отправить?",
        "можешь отправить",
        "Я забыл отправить.",
        "Нужно отправить.",
        "Удали последнее предложение в абзаце.",
        "Он попросил удалить последнее предложение из письма.",
        "Надо удалить последнее предложение.",
        "Add a new line to the table.",
        "Insert a new paragraph after the intro.",
        "New line characters break the parser.",
        "Can you send it?",
        "I'll send it.",
        "Please send it to Anna.",
        "Delete the last sentence of the email.",
        "Why did you delete the last sentence?",
        "Открой кавычки в этом файле.",
        "Строка номер пять новая.",
        "Это новый абзац.",
        "Сделай новый абзац.",
        "Скажи, когда отправить.",
        "Не забудь отправить.",
        "Проверь и отправь.",
        "Файл нужно отправить сегодня.",
        "Where is the new line?",
        "Start a new paragraph here.",
        "новая строка кода не компилируется",
        "в таблице появилась новая строка",
        "каждый пункт пиши с новой строки",
        "удали последнее предложение в абзаце",
        "add a new line to the table",
        "can you send it",
    ]

    @Test(arguments: ordinary) func ordinarySentencesStayText(_ sentence: String) {
        #expect(VoiceCommands.parse(sentence) == [.text(sentence)])
        #expect(format(sentence).send == false)
    }

    // MARK: Speed

    @Test func parseAndAssemblyAreFast() {
        let sentence = "Поправь хук в хедере и проверь, что он не дёргается при каждом рендере"
        var words: [String] = []
        while words.count < 200 { words += sentence.split(separator: " ").map(String.init) }
        let plain = words.prefix(200).joined(separator: " ") + "."
        var commanded = ""
        for (i, word) in words.prefix(200).enumerated() {
            commanded += (i == 0 ? "" : " ") + word
            if i % 40 == 39 { commanded += ". Новая строка." }
        }
        commanded += ". Отправь."

        let rounds = 200
        func seconds(_ body: () -> Void) -> Double {
            let clock = ContinuousClock()
            let elapsed = clock.measure { for _ in 0..<rounds { body() } }
            return Double(elapsed.components.attoseconds) / 1e18 / Double(rounds) + Double(elapsed.components.seconds) / Double(rounds)
        }
        _ = VoiceCommands.parse(commanded)
        let parsePlain = seconds { _ = VoiceCommands.parse(plain) }
        let parseCommands = seconds { _ = VoiceCommands.parse(commanded) }
        let pipeline = seconds { _ = format(commanded) }
        let formatterOnly = seconds { _ = TextFormatter.format(Transcript(text: plain), settings: settings) }
        print(String(format: "voice commands, 200 words: parse %.3f ms plain, %.3f ms with 6 commands; pipeline %.3f ms; formatter alone %.3f ms",
                     parsePlain * 1000, parseCommands * 1000, pipeline * 1000, formatterOnly * 1000))
        #expect(parseCommands < 0.001)
    }
}
