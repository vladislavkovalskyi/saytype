import Foundation

/// Turns a raw transcript into the text that gets inserted. Every step keeps the
/// spoken words; it only fixes spelling of terms, removes fillers and adds structure.
public enum TextFormatter {
    /// A pause at least this long after a finished sentence starts a new paragraph.
    public static let paragraphPause: Double = 1.5

    /// - Parameter projectTerms: identifiers from the user's code folders, best first.
    public static func format(_ transcript: Transcript, settings: AppSettings, projectTerms: [String] = []) -> String {
        let style = settings.punctuationStyle
        let paragraphs = style == .none
            ? [transcript.text]
            : Paragraphs.split(transcript, pause: paragraphPause)
        let rewriter = settings.latinTerms
            ? DictionaryRewriter.cached(entries: settings.dictionary, builtIn: settings.builtInDictionary, projectTerms: projectTerms)
            : nil

        let keptTerms = settings.letterCase == .lowercase
            ? settings.dictionary.map(\.written) + (settings.builtInDictionary ? BuiltInDictionary.terms.map(\.written) : []) + projectTerms
            : []

        var result: [String] = []
        for paragraph in paragraphs {
            var text = paragraph
            if let rewriter { text = rewriter.apply(to: text) }
            text = Cleanup.removeFillers(text, mode: settings.fillerMode)
            if !settings.wordFilters.isEmpty { text = WordFilter.remove(settings.wordFilters, from: text) }
            if settings.censorProfanity { text = WordFilter.censorProfanity(text) }
            switch style {
            case .full: if settings.smartStructure { text = Lists.format(text) }
            case .commas: text = Punctuation.strip(text, keeping: [","])
            case .none: text = Punctuation.strip(text)
            }
            if settings.letterCase == .lowercase { text = Letters.lowercase(text, keeping: keptTerms) }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(text) }
        }
        var text = result.joined(separator: "\n\n")
        if settings.dropTrailingPeriodInShortPhrases, style == .full, result.count == 1 {
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
    /// Marks in `keeping` stay, e.g. commas for chat style.
    public static func strip(_ text: String, keeping: Set<Character> = []) -> String {
        Words.split(text).compactMap { word in
            var w = Substring(word)
            var kept = ""
            while let last = w.last, ",.;:!?…".contains(last) {
                if keeping.contains(last), kept.isEmpty { kept = String(last) }
                w = w.dropLast()
            }
            return w.isEmpty ? nil : String(w) + kept
        }
        .joined(separator: " ")
    }
}

public enum Letters {
    /// "Привет, Я в React" → "привет, я в React". Acronyms and mixed-case words (API, useEffect,
    /// GitHub) keep their case, and so do Latin words from `terms`. Line breaks stay.
    public static func lowercase(_ text: String, keeping terms: [String] = []) -> String {
        let kept = Set(terms.flatMap { $0.split(separator: " ").map(String.init) }.filter { word in
            word.contains { $0.isASCII && $0.isLetter }
        })
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.split(separator: " ", omittingEmptySubsequences: false).map { raw in
                let word = String(raw)
                let letters = word.filter(\.isLetter)
                guard let first = letters.first, first.isUppercase, letters.dropFirst().allSatisfy(\.isLowercase),
                      !kept.contains(core(word)),
                      let index = word.firstIndex(of: first) else { return word }
                return word.replacingCharacters(in: index...index, with: String(first).lowercased())
            }
            .joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    private static func core(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }
}
