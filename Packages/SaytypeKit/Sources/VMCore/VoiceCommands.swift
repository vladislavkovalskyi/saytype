import Foundation

/// A spoken command inside a dictation.
public enum VoiceCommand: Equatable, Sendable {
    /// "новая строка", "new line"
    case newLine
    /// "новый абзац", "new paragraph"
    case newParagraph
    /// "удали последнее предложение", "delete last sentence"
    case deleteLastSentence
    /// "отправь", "send it": Return after the paste.
    case send
}

/// Dictated text split at voice commands.
public enum DictationPiece: Equatable, Sendable {
    case text(String)
    case command(VoiceCommand)
}

/// Finds spoken commands in a transcript.
///
/// A phrase is a command only when it stands as its own clause: at the start or the end of the
/// transcript, or next to a clause mark (. ! … ; : newline, or a comma or dash). So
/// "Привет. Новая строка. Как дела?" breaks the line, while "Это новая строка кода." and
/// "Добавь новую строку в таблицу." stay text. A question is never a command: "Отправить?".
///
/// When Whisper leaves a transcript without any punctuation, the neighbouring words decide:
/// a preposition, conjunction, pronoun or modal verb next to the phrase keeps it text
/// ("это новая строка кода", "новый абзац в договоре", "можешь отправить").
///
/// "отправь" counts only as the very last words, so "Отправь письмо Васе." stays text.
/// Quotes need both halves: "открой кавычки … закрой кавычки" → «…», or "…" in English text.
public enum VoiceCommands {
    /// Splits a transcript at spoken commands. Text without commands comes back as one piece.
    public static func parse(_ text: String) -> [DictationPiece] {
        var source = text as NSString
        var matches = candidates(in: text)
        guard !matches.isEmpty else { return [.text(text)] }

        if matches.contains(where: { $0.kind == .openQuote }), let quoted = replacingQuotes(in: source, matches: matches) {
            source = quoted as NSString
            matches = candidates(in: quoted)
        }
        matches.removeAll { $0.kind == .openQuote || $0.kind == .closeQuote }

        let context = Context(text: source, matches: matches)
        let accepted = matches.indices.filter { context.isCommand(at: $0) }
        guard !accepted.isEmpty else { return [.text(source as String)] }

        var pieces: [DictationPiece] = []
        var position = 0
        for index in accepted {
            let match = matches[index]
            let before = context.clause(from: position, to: match.range.location, afterCommand: position > 0)
            if !before.isEmpty { pieces.append(.text(before)) }
            pieces.append(.command(match.kind.command!))
            position = match.range.location + match.range.length
        }
        let rest = context.clause(from: position, to: source.length, afterCommand: true)
        if !rest.isEmpty { pieces.append(.text(rest)) }
        return pieces
    }

    /// `text` without its last sentence, for "удали последнее предложение". A line break before
    /// the sentence stays, so the next words start on that line.
    public static func droppingLastSentence(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex, text[text.index(before: end)].isWhitespace { end = text.index(before: end) }
        while end > text.startIndex, sentenceEnds.contains(text[text.index(before: end)]) || closingMarks.contains(text[text.index(before: end)]) {
            end = text.index(before: end)
        }
        var cut = text.startIndex
        var i = end
        while i > text.startIndex {
            let previous = text.index(before: i)
            let character = text[previous]
            if character.isNewline {
                cut = i
                break
            }
            // A sentence ends at . ! ? … (maybe inside a closing quote) followed by a space,
            // but not at "Next.js" or a list number like "2.".
            if i < text.endIndex, text[i].isWhitespace, sentenceEnds.contains(character) || (closingMarks.contains(character) && previous > text.startIndex && sentenceEnds.contains(text[text.index(before: previous)])),
               !isListNumber(text[..<previous]) {
                cut = i
                break
            }
            i = previous
        }
        var result = text[..<cut]
        while let last = result.last, last == " " || last == "\t" { result = result.dropLast() }
        return String(result)
    }

    // MARK: Matching

    enum Kind: Int {
        case newLine = 1, newParagraph, deleteLastSentence, send, openQuote, closeQuote

        var command: VoiceCommand? {
            switch self {
            case .newLine: .newLine
            case .newParagraph: .newParagraph
            case .deleteLastSentence: .deleteLastSentence
            case .send: .send
            case .openQuote, .closeQuote: nil
            }
        }
    }

    struct Match {
        let kind: Kind
        let range: NSRange
    }

    /// One pattern for every phrase, a capture group per kind in `Kind` order.
    private static let pattern: NSRegularExpression = {
        let groups = [
            #"новая\s+строка|с\s+новой\s+строки|new\s+line"#,
            #"новый\s+абзац|с\s+нового\s+абзаца|new\s+paragraph"#,
            #"удали(?:ть)?\s+последнее\s+предложение|delete\s+(?:the\s+)?last\s+sentence"#,
            #"отправь|отправить|send\s+it"#,
            #"открой\s+кавычки|open\s+quotes?"#,
            #"закрой\s+кавычки|close\s+quotes?"#,
        ]
        let body = groups.map { "(" + $0 + ")" }.joined(separator: "|")
        // The phrases were written by hand and compile; a failure here is a programming error.
        return try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_-])(?:"# + body + #")(?![\p{L}\p{N}_-])"#, options: [.caseInsensitive])
    }()

    static func candidates(in text: String) -> [Match] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { result in
            for group in 1..<result.numberOfRanges where result.range(at: group).location != NSNotFound {
                return Kind(rawValue: group).map { Match(kind: $0, range: result.range) }
            }
            return nil
        }
    }

    // MARK: Quotes

    /// "Он сказал открой кавычки привет закрой кавычки" → "Он сказал «привет»". `nil` without a full pair.
    private static func replacingQuotes(in text: NSString, matches: [Match]) -> String? {
        // Russian text gets «ёлочки»; the command words themselves don't count.
        var russian = false
        var unit = 0
        for match in matches where match.kind == .openQuote || match.kind == .closeQuote {
            russian = russian || containsCyrillic(text, from: unit, to: match.range.location)
            unit = match.range.location + match.range.length
        }
        russian = russian || containsCyrillic(text, from: unit, to: text.length)
        let (open, close) = russian ? ("«", "»") : ("\"", "\"")
        var result = ""
        var position = 0
        var pendingOpen: Match?
        var replaced = false
        for match in matches {
            switch match.kind {
            case .openQuote:
                pendingOpen = match
            case .closeQuote:
                guard let start = pendingOpen else { continue }
                pendingOpen = nil
                let innerStart = start.range.location + start.range.length
                let inner = text.substring(with: NSRange(location: innerStart, length: match.range.location - innerStart))
                    .trimmingCharacters(in: quoteInnerTrim)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !inner.isEmpty else { continue }
                var prefix = text.substring(with: NSRange(location: position, length: start.range.location - position))
                while let last = prefix.last, last.isWhitespace || last == "," { prefix.removeLast() }
                if let last = prefix.last, !"(«\"".contains(last) { prefix += " " }
                result += prefix + open + inner + close
                position = match.range.location + match.range.length
                replaced = true
            default:
                continue
            }
        }
        guard replaced else { return nil }
        return result + text.substring(from: position)
    }

    private static func containsCyrillic(_ text: NSString, from start: Int, to end: Int) -> Bool {
        guard end > start else { return false }
        return (start..<end).contains { (0x0400...0x04FF).contains(text.character(at: $0)) }
    }

    /// Marks Whisper puts at the edges of quoted words; ! ? … stay.
    private static let quoteInnerTrim = CharacterSet(charactersIn: ",.;:—–- \n\t")

    // MARK: Boundaries

    private static let sentenceEnds: Set<Character> = [".", "!", "?", "…"]
    private static let closingMarks: Set<Character> = ["»", "\"", ")", "”"]

    private static func isListNumber(_ line: Substring) -> Bool {
        let start = line.lastIndex(where: \.isNewline).map { line.index(after: $0) } ?? line.startIndex
        let number = line[start...].drop { $0 == " " }
        return !number.isEmpty && number.allSatisfy(\.isNumber)
    }

    /// Clause checks on UTF-16 units, the same units `NSRegularExpression` ranges use.
    private struct Context {
        let text: NSString
        let matches: [Match]
        /// No clause marks at all: Whisper left the transcript bare, so words decide.
        let isBare: Bool

        init(text: NSString, matches: [Match]) {
            self.text = text
            self.matches = matches
            var bare = true
            for i in 0..<text.length where Marks.clause.contains(text.character(at: i)) {
                if i + 1 == text.length || Marks.isSpace(text.character(at: i + 1)) || Marks.isNewline(text.character(at: i + 1)) {
                    bare = false
                    break
                }
            }
            isBare = bare
        }

        func isCommand(at index: Int) -> Bool {
            let match = matches[index]
            let start = match.range.location
            let end = start + match.range.length
            guard leftBoundary(before: start, index: index), rightBoundary(after: end, index: index) else { return false }
            if match.kind == .send {
                // Only the closing words: nothing but marks may follow.
                var i = end
                while i < text.length {
                    let unit = text.character(at: i)
                    guard Marks.isSpace(unit) || Marks.isNewline(unit) || Marks.sentenceEnd.contains(unit) else { return false }
                    i += 1
                }
            }
            return true
        }

        private func leftBoundary(before start: Int, index: Int) -> Bool {
            var i = start - 1
            while i >= 0, Marks.isSpace(text.character(at: i)) { i -= 1 }
            guard i >= 0 else { return true }
            let unit = text.character(at: i)
            if Marks.isNewline(unit) || Marks.strong.contains(unit) || unit == Marks.question || Marks.weak.contains(unit) { return true }
            if index > 0, matches[index - 1].range.location + matches[index - 1].range.length == i + 1 { return true }
            return isBare && !Glue.before.contains(word(endingAt: i))
        }

        private func rightBoundary(after end: Int, index: Int) -> Bool {
            var i = end
            while i < text.length, Marks.isSpace(text.character(at: i)) { i += 1 }
            guard i < text.length else { return true }
            let unit = text.character(at: i)
            if Marks.isNewline(unit) || Marks.strong.contains(unit) { return true }
            if index + 1 < matches.count, matches[index + 1].range.location == i { return true }
            if Marks.weak.contains(unit) {
                return !Glue.afterComma.contains(word(startingAt: i + 1))
            }
            return isBare && !Glue.after.contains(word(startingAt: i))
        }

        /// The lowercased word whose last unit is at or before `index`, without marks around it.
        private func word(endingAt index: Int) -> String {
            var end = index
            while end >= 0, Marks.isSpace(text.character(at: end)) { end -= 1 }
            var start = end
            while start > 0, !Marks.isSpace(text.character(at: start - 1)), !Marks.isNewline(text.character(at: start - 1)) { start -= 1 }
            guard end >= start, end >= 0 else { return "" }
            return Self.core(text.substring(with: NSRange(location: start, length: end - start + 1)))
        }

        private func word(startingAt index: Int) -> String {
            var start = index
            while start < text.length, Marks.isSpace(text.character(at: start)) { start += 1 }
            var end = start
            while end < text.length, !Marks.isSpace(text.character(at: end)), !Marks.isNewline(text.character(at: end)) { end += 1 }
            guard end > start else { return "" }
            return Self.core(text.substring(with: NSRange(location: start, length: end - start)))
        }

        private static func core(_ word: String) -> String {
            word.trimmingCharacters(in: .punctuationCharacters.union(.symbols)).lowercased()
        }

        /// The text between two commands, without the marks that belonged to the commands:
        /// "Привет, новая строка." → "Привет". Sentence ends before a command stay.
        func clause(from start: Int, to end: Int, afterCommand: Bool) -> String {
            var lower = start
            var upper = end
            if afterCommand {
                while lower < upper, Marks.isSpace(text.character(at: lower)) || Marks.isNewline(text.character(at: lower)) || Marks.trailing.contains(text.character(at: lower)) {
                    lower += 1
                }
            }
            while upper > lower, Marks.isSpace(text.character(at: upper - 1)) || Marks.isNewline(text.character(at: upper - 1)) || Marks.weak.contains(text.character(at: upper - 1)) {
                upper -= 1
            }
            while lower < upper, Marks.isSpace(text.character(at: lower)) || Marks.isNewline(text.character(at: lower)) { lower += 1 }
            guard upper > lower else { return "" }
            return text.substring(with: NSRange(location: lower, length: upper - lower))
        }
    }

    /// UTF-16 units of the marks around commands.
    private enum Marks {
        /// Marks that end a clause for certain.
        static let strong: Set<unichar> = units(".!…;:")
        /// A comma or a dash: a clause break, unless the words after it carry the sentence on.
        static let weak: Set<unichar> = units(",—–-")
        static let question = unichar(0x3F)
        static let sentenceEnd: Set<unichar> = units(".!…")
        /// A command's own marks that are dropped with it.
        static let trailing: Set<unichar> = units(".!…,;:—–-")
        /// Any of these followed by a space means Whisper punctuated the transcript.
        static let clause: Set<unichar> = units(".,!?…;:")

        static func isSpace(_ unit: unichar) -> Bool { unit == 0x20 || unit == 0x09 || unit == 0xA0 }
        static func isNewline(_ unit: unichar) -> Bool { unit == 0x0A || unit == 0x0D }

        private static func units(_ string: String) -> Set<unichar> { Set(string.utf16) }
    }

    /// Words that bind a phrase into an ordinary sentence.
    private enum Glue {
        /// Before the phrase: "это новая строка", "можешь отправить", "add a new line".
        static let before: Set<String> = [
            "и", "а", "но", "или", "да", "не", "ни", "это", "эта", "этот", "эту", "вот", "тут", "там", "здесь",
            "есть", "был", "была", "было", "будет", "как", "где", "что", "чтобы", "когда", "если", "куда", "кому",
            "в", "во", "на", "с", "со", "для", "из", "под", "по", "после", "перед", "над", "у", "к", "ко", "от", "до",
            "без", "про", "через", "между", "каждая", "каждый", "каждую", "каждое", "одна", "один", "ещё", "еще",
            "такая", "какая", "моя", "твоя", "наша", "ваша", "его", "её", "ее", "их", "я", "ты", "он", "она", "мы",
            "вы", "они", "мне", "тебе", "ему", "ей", "нам", "вам", "им", "нужно", "надо", "нужна", "нужен", "можно",
            "можешь", "может", "могу", "можете", "хочу", "хочешь", "хотел", "хотела", "забыл", "забыла", "пора",
            "пиши", "напиши", "писать", "начни", "начинай", "начать", "начинается", "начинать", "продолжи",
            "продолжай", "перенеси", "переноси", "вставь", "добавь", "появилась", "получилась",
            "a", "an", "the", "this", "that", "these", "those", "is", "was", "are", "be", "been", "to", "of", "in",
            "on", "at", "for", "with", "and", "or", "but", "not", "no", "each", "every", "per", "one", "another",
            "can", "could", "will", "would", "should", "must", "may", "might", "i", "we", "you", "they", "he",
            "she", "it", "my", "your", "our", "their", "his", "her", "its", "don't", "didn't", "add", "insert",
            "start", "starts", "begin", "begins", "want", "need", "gonna", "let's", "just",
        ]

        /// After the phrase: "новая строка кода", "новый абзац в договоре", "new line character".
        static let after: Set<String> = [
            "в", "во", "на", "с", "со", "для", "из", "под", "по", "после", "перед", "над", "у", "к", "от", "до",
            "без", "про", "через", "между", "и", "или", "а", "но", "не", "это", "был", "была", "было", "будет",
            "есть", "уже", "тоже", "ещё", "еще", "же", "ли", "бы", "который", "которая", "которое", "которую",
            "которой", "кода", "текста", "таблицы", "файла", "документа", "договора", "списка", "письма",
            "сообщения", "получился", "получилась", "появилась", "появился",
            "of", "in", "on", "at", "for", "with", "and", "or", "but", "is", "was", "will", "has", "had", "to",
            "from", "that", "which", "after", "before", "here", "there", "character", "characters", "break",
            "breaks", "feed", "symbol",
        ]

        /// After a comma that follows the phrase: "Новая строка, а не старая", "Новый абзац, который ты прислал".
        static let afterComma: Set<String> = [
            "а", "но", "не", "и", "или", "да", "же", "ли", "который", "которая", "которое", "которую", "которой",
            "которые", "которых", "and", "or", "but", "not", "which", "that", "who",
        ]
    }
}
