import Foundation

/// A phrase that inserts saved text: "мой имейл" → the address, "шаблон ревью" → a prompt.
public struct Snippet: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Any of these, said alone or inside a phrase, inserts `text`. Written the way Whisper
    /// hears them; case, punctuation, spaces and hyphens do not matter.
    public var triggers: [String]
    /// Inserted as written. {clipboard}, {selection}, {date} and {time} are filled in on the way.
    public var text: String

    public init(id: UUID = UUID(), triggers: [String] = [], text: String = "") {
        self.id = id
        self.triggers = triggers
        self.text = text
    }

    public init(from decoder: any Decoder) throws {
        // Field by field, like AppSettings: a snippet saved by another version still loads.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        triggers = try c.decodeIfPresent([String].self, forKey: .triggers) ?? []
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    }

    /// The text that goes in: variables filled, whitespace at the edges dropped. A newline typed
    /// by accident at the end must not send a line in a terminal.
    public func insertion(_ values: SnippetValues) -> String {
        SnippetVariables.expand(text, values: values).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: Matching

/// Finds trigger phrases in what Whisper heard.
///
/// A word is a run of letters and digits, compared without case or diacritics (ё is е). A
/// trigger matches consecutive whole words whose letters, joined, are the trigger's letters,
/// joined: "шаблон ревью" matches "Шаблон, ревью", "шаблон-ревью" and "шаблонревью", never
/// "шаблоны ревью". A match does not run across the end of a sentence or a line.
///
/// Left to right, the longest trigger wins at each word; two snippets with the same trigger go
/// to the one earlier in the list.
public struct SnippetMatcher: Sendable {
    struct Trigger: Sendable {
        let key: String
        let snippet: Snippet
    }

    /// Longest first, list order among equals; each key once.
    let triggers: [Trigger]

    /// Triggers with fewer letters than this are ignored, so a stray "я" never fires.
    public static let minimumLetters = 2

    public init(_ snippets: [Snippet]) {
        var seen = Set<String>()
        var triggers: [(order: Int, trigger: Trigger)] = []
        for snippet in snippets {
            for phrase in snippet.triggers {
                let key = Self.key(phrase)
                guard key.count >= Self.minimumLetters, seen.insert(key).inserted else { continue }
                triggers.append((triggers.count, Trigger(key: key, snippet: snippet)))
            }
        }
        self.triggers = triggers.sorted { a, b in
            a.trigger.key.count != b.trigger.key.count ? a.trigger.key.count > b.trigger.key.count : a.order < b.order
        }.map(\.trigger)
    }

    public var isEmpty: Bool { triggers.isEmpty }

    /// Each trigger said in `text`, in reading order, with the range of the words that said it.
    public func matches(in text: String) -> [(snippet: Snippet, range: Range<String.Index>)] {
        guard !triggers.isEmpty else { return [] }
        let words = Self.words(in: text)
        var result: [(snippet: Snippet, range: Range<String.Index>)] = []
        var i = 0
        next: while i < words.count {
            for trigger in triggers {
                guard let end = Self.end(of: trigger.key, in: words, from: i) else { continue }
                result.append((trigger.snippet, words[i].range.lowerBound..<words[end].range.upperBound))
                i = end + 1
                continue next
            }
            i += 1
        }
        return result
    }

    /// `text` with every trigger replaced by a marker. The snippets are appended to `found`, and
    /// each marker is numbered by its snippet's place there: ⟦1⟧ is `found[0]`.
    public func replacing(in text: String, found: inout [Snippet]) -> String {
        let matches = matches(in: text)
        guard !matches.isEmpty else { return text }
        var result = ""
        var position = text.startIndex
        for match in matches {
            result += text[position..<match.range.lowerBound]
            found.append(match.snippet)
            result += SnippetMarker.marker(found.count)
            position = match.range.upperBound
        }
        return result + text[position...]
    }

    // MARK: Words

    struct Word {
        let range: Range<String.Index>
        let key: String
        /// A sentence end or a line break stands between this word and the one before.
        let afterBreak: Bool
    }

    /// Folded letters of a phrase, the form triggers are compared in: "Шаблон-ревью!" → "шаблонревью".
    public static func key(_ phrase: String) -> String {
        words(in: phrase).map(\.key).joined()
    }

    static func words(in text: String) -> [Word] {
        var words: [Word] = []
        var start: String.Index?
        var pendingBreak = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character.isLetter || character.isNumber {
                if start == nil { start = index }
            } else {
                if let wordStart = start {
                    words.append(Word(range: wordStart..<index, key: fold(text[wordStart..<index]), afterBreak: pendingBreak))
                    pendingBreak = false
                    start = nil
                }
                // "Next.js" is one term; "мой. Имейл" is two sentences.
                if character.isNewline || (sentenceEnds.contains(character) && (next == text.endIndex || text[next].isWhitespace)) {
                    pendingBreak = true
                }
            }
            index = next
        }
        if let wordStart = start {
            words.append(Word(range: wordStart..<text.endIndex, key: fold(text[wordStart...]), afterBreak: pendingBreak))
        }
        return words
    }

    private static let sentenceEnds: Set<Character> = [".", "!", "?", "…"]

    private static func fold(_ word: Substring) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Index of the last word of a match of `key` that starts at `start`.
    private static func end(of key: String, in words: [Word], from start: Int) -> Int? {
        var joined = ""
        var index = start
        while index < words.count {
            if index > start, words[index].afterBreak { return nil }
            joined += words[index].key
            if joined == key { return index }
            guard joined.count < key.count, key.hasPrefix(joined) else { return nil }
            index += 1
        }
        return nil
    }
}

/// Why a trigger phrase never fires.
public enum SnippetTriggerIssue: Equatable, Sendable {
    /// Fewer than `SnippetMatcher.minimumLetters` letters.
    case tooShort
    /// A voice command takes these words first.
    case voiceCommand
    /// A snippet higher in the list, or an earlier phrase of this one, has the same words.
    case duplicate
}

extension Snippet {
    /// Why phrase `trigger` of `snippets[index]` would never fire, or `nil` when it can.
    public static func issue(trigger: Int, of index: Int, in snippets: [Snippet], voiceCommands: Bool) -> SnippetTriggerIssue? {
        let phrase = snippets[index].triggers[trigger]
        let key = SnippetMatcher.key(phrase)
        guard key.count >= SnippetMatcher.minimumLetters else { return .tooShort }
        if voiceCommands, VoiceCommands.parse(phrase).contains(where: { if case .command = $0 { true } else { false } }) {
            return .voiceCommand
        }
        for other in 0...index {
            // In this snippet, only the phrases before this one count.
            let phrases = other < index ? snippets[other].triggers : Array(snippets[other].triggers.prefix(trigger))
            if phrases.contains(where: { SnippetMatcher.key($0) == key }) { return .duplicate }
        }
        return nil
    }
}

// MARK: Markers

/// Stand-ins for snippets while the rest of the dictation is formatted and rewritten: ⟦1⟧, ⟦2⟧…
///
/// A marker has no letters, so letter case, the dictionary, the term canonicalizer and backticks
/// leave it alone, and punctuation steps only strip the marks after it.
public enum SnippetMarker {
    public static func marker(_ number: Int) -> String { "⟦\(number)⟧" }

    private static let pattern = try! NSRegularExpression(pattern: #"⟦(\d{1,3})⟧"#)

    public static func contains(_ text: String) -> Bool {
        text.contains("⟦") || text.contains("⟧")
    }

    /// Numbers of the markers in `text`, in reading order.
    public static func numbers(in text: String) -> [Int] {
        guard contains(text) else { return [] }
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) }
        }
    }

    /// Nothing but markers, whitespace and sentence punctuation: a dictation made of snippets.
    public static func isOnlyMarkers(_ text: String) -> Bool {
        guard contains(text) else { return false }
        return removingMarkers(text).allSatisfy { $0.isWhitespace || tidyMarks.contains($0) }
    }

    /// A marker of `original` that `candidate` lost, repeated or changed, or one it made up.
    /// `nil` when both hold the same markers.
    public static func mismatch(original: String, candidate: String) -> (marker: String, missing: Bool)? {
        let before = numbers(in: original)
        let after = numbers(in: candidate)
        var left = after
        for number in before {
            guard let index = left.firstIndex(of: number) else { return (marker(number), true) }
            left.remove(at: index)
        }
        if let extra = left.first { return (marker(extra), false) }
        // A bracket that is not part of a whole marker: "⟦ 1 ⟧", "⟦1".
        let stray = removingMarkers(candidate)
        if stray.contains("⟦") || stray.contains("⟧") { return ("⟦", false) }
        return nil
    }

    static func removingMarkers(_ text: String) -> String {
        pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    /// Marks the formatter may put next to a snippet that stands alone.
    static let tidyMarks: Set<Character> = [".", ",", ";", ":", "!", "?", "…"]
}

// MARK: Placement

/// Puts the snippets' text where their markers are.
public enum SnippetPlacement {
    /// `text` with each ⟦n⟧ replaced by `texts[n - 1]`.
    ///
    /// - A line of nothing but snippets loses the marks the formatter put around them, so
    ///   "мой имейл" gives the address, not "address.".
    /// - Inside a sentence, a mark right after a snippet that already ends a sentence is dropped:
    ///   no "bugs.." or "bugs.,".
    /// - An empty snippet takes the space next to it.
    public static func resolve(_ text: String, texts: [String]) -> String {
        guard SnippetMarker.contains(text) else { return text }
        let texts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let line = String(line)
            guard SnippetMarker.contains(line) else { return line }
            return SnippetMarker.isOnlyMarkers(line) ? standalone(line, texts: texts) : inSentence(line, texts: texts)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func standalone(_ line: String, texts: [String]) -> String {
        let bare = String(line.filter { !SnippetMarker.tidyMarks.contains($0) })
        let parts = SnippetMarker.numbers(in: bare).map { text(for: $0, in: texts) }.filter { !$0.isEmpty }
        let indent = String(bare.prefix { $0 == " " || $0 == "\t" })
        return parts.isEmpty ? "" : indent + parts.joined(separator: " ")
    }

    private static func inSentence(_ line: String, texts: [String]) -> String {
        var result = ""
        var rest = Substring(line)
        while let open = rest.firstIndex(of: "⟦") {
            result += rest[..<open]
            let tail = rest[open...]
            guard let close = tail.firstIndex(of: "⟧"),
                  let number = Int(tail[tail.index(after: open)..<close]) else {
                // A lone bracket stays text.
                result.append("⟦")
                rest = rest[rest.index(after: open)...]
                continue
            }
            rest = rest[rest.index(after: close)...]
            let insert = text(for: number, in: texts)
            if insert.isEmpty {
                // "Вставь ⟦1⟧, пожалуйста" with nothing to insert: "Вставь, пожалуйста".
                if result.last == " ", rest.first == " " || rest.first.map(SnippetMarker.tidyMarks.contains) == true {
                    result.removeLast()
                }
                continue
            }
            result += insert
            if let last = insert.last, sentenceEnds.contains(last), let next = rest.first, [".", ",", ";", ":"].contains(next) {
                rest = rest.dropFirst()
            }
        }
        return result + rest
    }

    private static func text(for number: Int, in texts: [String]) -> String {
        texts.indices.contains(number - 1) ? texts[number - 1] : ""
    }

    private static let sentenceEnds: Set<Character> = [".", "!", "?", "…"]
}

// MARK: Variables

/// A value filled into snippet text.
public enum SnippetVariable: String, CaseIterable, Sendable {
    case clipboard
    case selection
    case date
    case time

    /// "{date}"
    public var token: String { "{\(rawValue)}" }
}

/// What the variables stand for at the moment of insertion.
public struct SnippetValues: Sendable {
    public var clipboard: String?
    public var selection: String?
    public var now: Date
    public var locale: Locale
    public var timeZone: TimeZone

    public init(clipboard: String? = nil, selection: String? = nil, now: Date = Date(), locale: Locale = .current, timeZone: TimeZone = .current) {
        self.clipboard = clipboard
        self.selection = selection
        self.now = now
        self.locale = locale
        self.timeZone = timeZone
    }

    /// "23 сентября 2026 г.", "September 23, 2026".
    public var date: String {
        now.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: locale, calendar: locale.calendar, timeZone: timeZone))
    }

    /// "14:05", "2:05 PM".
    public var time: String {
        now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: locale.calendar, timeZone: timeZone))
    }

    public func value(of variable: SnippetVariable) -> String {
        switch variable {
        case .clipboard: clipboard ?? ""
        case .selection: selection ?? ""
        case .date: date
        case .time: time
        }
    }
}

/// {clipboard}, {selection}, {date} and {time} in snippet text. Names ignore case; anything else
/// in braces stays as written, so code like `{ id }` or `{name}` survives.
public enum SnippetVariables {
    private static let pattern = try! NSRegularExpression(pattern: #"\{([A-Za-z]+)\}"#)

    /// The variables `text` uses.
    public static func used(in text: String) -> Set<SnippetVariable> {
        guard text.contains("{") else { return [] }
        return Set(pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { SnippetVariable(rawValue: text[$0].lowercased()) }
        })
    }

    public static func expand(_ text: String, values: SnippetValues) -> String {
        guard text.contains("{") else { return text }
        var result = ""
        var position = text.startIndex
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let name = Range(match.range(at: 1), in: text),
                  let variable = SnippetVariable(rawValue: text[name].lowercased()) else { continue }
            result += text[position..<whole.lowerBound]
            result += values.value(of: variable)
            position = whole.upperBound
        }
        return result + text[position...]
    }
}
