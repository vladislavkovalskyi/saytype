import Foundation

/// Structure a language model assigns to one sentence. The model never writes text itself:
/// it only labels sentences, so the spoken words cannot change.
public enum StructureLabel: Character, Sendable {
    /// Continues the current paragraph.
    case text = "T"
    /// Starts a new paragraph.
    case paragraph = "P"
    /// A list item.
    case item = "L"
}

public enum SmartStructure {
    public static let systemPrompt = """
    Ты размечаешь структуру надиктованного сообщения. Предложения пронумерованы.
    Метки:
    T — продолжает текущий абзац
    P — начинает новый абзац
    L — пункт списка

    Список нужен, когда автор перечисляет отдельные задачи, шаги, проблемы или требования, и таких пунктов хотя бы два. Каждое такое предложение — L, включая последнее («И ещё…», «Потом…»).
    Предложение, которое объявляет список («есть три проблемы», «надо сделать пару вещей»), — T.
    Описание одной ситуации, связный рассказ или объяснение — T, без списка.
    Вывод или просьба после списка («После этого…», «Посмотри…») — P.

    Отвечай строками «номер метка» и больше ничего.

    Пример 1:
    [1] Надо сделать две вещи. [2] Обнови зависимости. [3] Потом прогони тесты. [4] Как закончишь, напиши мне.
    1 T
    2 L
    3 L
    4 P

    Пример 2:
    [1] Кнопка Save не работает. [2] Когда нажимаю, в консоли ошибка 500. [3] Посмотри логи сервера.
    1 T
    2 T
    3 T
    """

    /// The model sees paragraphs as they are; a paragraph that already holds a list is left alone.
    public static func shouldStructure(_ text: String, minWords: Int) -> Bool {
        Words.split(text).count >= minWords && !text.contains("\n1. ")
    }

    public static func sentences(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n").flatMap { paragraph in
            paragraph
                .replacingOccurrences(of: #"(?<=[.!?…])\s+(?=\S)"#, with: "\u{1F}", options: .regularExpression)
                .components(separatedBy: "\u{1F}")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    /// Sentence indices that start a paragraph in the formatted text, e.g. after a long pause.
    public static func paragraphStarts(_ text: String) -> Set<Int> {
        var starts: Set<Int> = []
        var index = 0
        for paragraph in text.components(separatedBy: "\n\n") {
            let count = sentences(paragraph).count
            if index > 0, count > 0 { starts.insert(index) }
            index += count
        }
        return starts
    }

    public static func userMessage(_ sentences: [String]) -> String {
        sentences.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: " ")
    }

    /// Reads "1 T" lines. Missing or unreadable lines stay `.text`.
    public static func parseLabels(_ output: String, count: Int) -> [StructureLabel] {
        var labels = Array(repeating: StructureLabel.text, count: count)
        let regex = try? NSRegularExpression(pattern: #"(\d+)\s*[-:.)]?\s*([TPL])\b"#)
        let ns = output as NSString
        for match in regex?.matches(in: output, range: NSRange(location: 0, length: ns.length)) ?? [] {
            guard let index = Int(ns.substring(with: match.range(at: 1))), (1...count).contains(index),
                  let label = StructureLabel(rawValue: Character(ns.substring(with: match.range(at: 2))))
            else { continue }
            labels[index - 1] = label
        }
        return labels
    }

    /// Builds the text from labelled sentences. A lone list item stays a plain sentence;
    /// the sentence before a list ends with a colon.
    public static func render(_ sentences: [String], labels: [StructureLabel], paragraphStarts: Set<Int> = []) -> String {
        var labels = labels
        var i = 0
        while i < labels.count {
            guard labels[i] == .item else { i += 1; continue }
            var end = i
            while end + 1 < labels.count, labels[end + 1] == .item { end += 1 }
            if end == i { labels[i] = paragraphStarts.contains(i) ? .paragraph : .text }
            i = end + 1
        }
        for start in paragraphStarts where start < labels.count && labels[start] == .text {
            labels[start] = .paragraph
        }

        var blocks: [String] = []
        var paragraph: [String] = []
        var items: [String] = []

        func flushItems() {
            guard !items.isEmpty else { return }
            let list = items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            if let last = paragraph.popLast() {
                paragraph.append(introduction(last))
                blocks.append(paragraph.joined(separator: " ") + "\n" + list)
            } else {
                blocks.append(list)
            }
            paragraph = []
            items = []
        }

        for (sentence, label) in zip(sentences, labels) {
            switch label {
            case .item:
                items.append(Cleanup.capitalizeFirst(sentence))
            case .text, .paragraph:
                if !items.isEmpty {
                    flushItems()
                } else if label == .paragraph, !paragraph.isEmpty {
                    blocks.append(paragraph.joined(separator: " "))
                    paragraph = []
                }
                paragraph.append(sentence)
            }
        }
        flushItems()
        if !paragraph.isEmpty { blocks.append(paragraph.joined(separator: " ")) }
        return blocks.joined(separator: "\n\n")
    }

    static func introduction(_ sentence: String) -> String {
        guard let last = sentence.last else { return sentence }
        if last == "." || last == "," || last == ";" { return sentence.dropLast() + ":" }
        if last == ":" || last == "?" || last == "!" { return sentence }
        return sentence + ":"
    }
}
