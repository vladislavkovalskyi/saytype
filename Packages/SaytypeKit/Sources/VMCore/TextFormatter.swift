import Foundation

/// Turns a raw transcript into the text that gets inserted. Every step keeps the
/// spoken words; it only fixes spelling of terms, removes fillers and adds structure.
public enum TextFormatter {
    /// A pause at least this long after a finished sentence starts a new paragraph.
    public static let paragraphPause: Double = 1.5

    public static func format(_ transcript: Transcript, settings: AppSettings) -> String {
        let paragraphs = settings.punctuation
            ? Paragraphs.split(transcript, pause: paragraphPause)
            : [transcript.text]
        let rewriter = settings.latinTerms ? DictionaryRewriter(entries: settings.dictionary, builtIn: settings.builtInDictionary) : nil

        var result: [String] = []
        for paragraph in paragraphs {
            var text = paragraph
            if let rewriter { text = rewriter.apply(to: text) }
            text = Cleanup.removeFillers(text, mode: settings.fillerMode)
            if !settings.wordFilters.isEmpty { text = WordFilter.remove(settings.wordFilters, from: text) }
            if settings.censorProfanity { text = WordFilter.censorProfanity(text) }
            if !settings.punctuation { text = Punctuation.strip(text) }
            if settings.smartStructure { text = Lists.format(text) }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(text) }
        }
        var text = result.joined(separator: "\n\n")
        if settings.dropTrailingPeriodInShortPhrases, result.count == 1 {
            text = Cleanup.dropTrailingPeriod(text)
        }
        return text
    }
}

public enum Paragraphs {
    /// Splits at long pauses that follow sentence-ending punctuation. Falls back to
    /// the plain text when word timings do not match it (e.g. after hallucination cleanup).
    public static func split(_ transcript: Transcript, pause: Double) -> [String] {
        let words = transcript.words.filter { !$0.text.isEmpty }
        guard words.count > 1, Words.keys(words.map(\.text).joined(separator: " ")) == Words.keys(transcript.text) else {
            return [transcript.text]
        }
        var paragraphs: [[String]] = [[]]
        for (i, word) in words.enumerated() {
            paragraphs[paragraphs.count - 1].append(word.text)
            guard i + 1 < words.count else { break }
            let gap = words[i + 1].start - word.end
            let endsSentence = word.text.last.map { ".!?…".contains($0) } ?? false
            if gap >= pause, endsSentence {
                paragraphs.append([])
            }
        }
        return paragraphs.map { $0.joined(separator: " ") }.filter { !$0.isEmpty }
    }
}

public enum Lists {
    static let ordinals = ["во-первых", "во-вторых", "в-третьих", "в-четвертых", "в-четвёртых", "в-пятых", "в-шестых"]

    /// "Сегодня три дела. Во-первых, X. Во-вторых, Y." → intro plus a numbered list.
    public static func format(_ text: String) -> String {
        let pattern = #"(?i)(?<![\p{L}-])("# + ordinals.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + #")(?![\p{L}])[,:]?\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else { return text }

        var intro = ns.substring(to: matches[0].range.location).trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [String] = []
        for (i, match) in matches.enumerated() {
            let start = match.range.location + match.range.length
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let item = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
            guard !item.isEmpty else { return text }
            items.append(Cleanup.capitalizeFirst(item.hasSuffix(".") || item.hasSuffix("!") || item.hasSuffix("?") ? item : item + "."))
        }
        if !intro.isEmpty {
            intro = intro.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:—- "))
            intro += ":"
        }
        let list = items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return intro.isEmpty ? list : intro + "\n" + list
    }
}

public enum Punctuation {
    /// Removes sentence punctuation but keeps terms like Next.js and feature/auth intact.
    public static func strip(_ text: String) -> String {
        Words.split(text).map { word in
            var w = Substring(word)
            while let last = w.last, ",.;:!?…".contains(last) { w = w.dropLast() }
            return String(w)
        }
        .joined(separator: " ")
    }
}
