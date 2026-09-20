import Foundation

/// Checks a language model's rewrite before it replaces the formatted dictation. The model may
/// reword, restructure and translate; it may not lose code, numbers, links, paths or dictionary
/// terms, make up links, paths or numbers, answer in the wrong language or run on.
public enum RewriteValidator {
    public enum Verdict: Equatable, Sendable {
        case accepted
        case rejected(Reason)

        public var isAccepted: Bool { self == .accepted }
    }

    public enum Reason: Equatable, Sendable, CustomStringConvertible {
        case empty
        case tooLong
        case tooShort
        /// A protected token of the dictation is missing from the rewrite.
        case dropped(String)
        /// The rewrite has a link, a path, a call or a number the dictation did not.
        case invented(String)
        case wrongLanguage
        case notConventionalCommit

        public var description: String {
            switch self {
            case .empty: "empty"
            case .tooLong: "too long"
            case .tooShort: "too short"
            case .dropped(let token): "dropped \(token)"
            case .invented(let token): "invented \(token)"
            case .wrongLanguage: "wrong language"
            case .notConventionalCommit: "not a conventional commit"
            }
        }
    }

    /// - Parameter terms: dictionary spellings such as "Vercel"; the ones the dictation uses must stay.
    public static func check(original: String, candidate: String, request: RewriteRequest, terms: [String] = []) -> Verdict {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return .rejected(.empty) }

        let length = Double(original.count)
        let (ratio, slack) = lengthLimit(request.style)
        if Double(candidate.count) > length * ratio + slack { return .rejected(.tooLong) }
        if let minimum = minimumRatio(request.style), length >= 60, Double(candidate.count) < length * minimum {
            return .rejected(.tooShort)
        }
        // A selection edit is asked for in words: which words change, and into what language, is
        // the instruction's business. Only an empty or runaway answer is rejected.
        if request.style == .selection { return .accepted }
        if request.style == .commit, !isConventionalHeader(candidate) { return .rejected(.notConventionalCommit) }
        if !languageMatches(original: original, candidate: candidate, request: request) { return .rejected(.wrongLanguage) }

        let latinTerms = terms.filter { term in
            term.count >= 2 && term.unicodeScalars.allSatisfy(\.isASCII) && term.contains(where: \.isLetter)
        }
        let body = withoutListMarkers(request.style == .commit ? withoutCommitType(candidate) : candidate)
        let candidateText = normalized(body)
        let originalText = normalized(original)
        let originalWords = Words.split(original)
        // Everything but a plain translation may resolve "не X, а Y" to Y.
        let correctionsAllowed = request.style != .none

        let protected = protectedTokens(in: original, terms: latinTerms)
        var dropped: [Token] = []
        for token in protected where !token.keys.contains(where: { contains(candidateText, $0) }) {
            if correctionsAllowed, token.wordIndices.allSatisfy({ isNearCorrection(originalWords, at: $0) }) { continue }
            dropped.append(token)
        }
        // A commit message summarizes: it may leave out context such as "SwiftUI" or an old port,
        // as long as most of what the dictation named is there.
        let droppable = request.style == .commit ? Int(Double(protected.count) * commitDroppableShare) : 0
        if dropped.count > droppable, let first = dropped.first {
            return .rejected(.dropped(first.text))
        }
        let termKeys = Set(latinTerms.map(normalized))
        let spokenNumbers = NumberWords.values(in: originalText)
        for token in protectedTokens(in: body, terms: []) where inventable(token) && !contains(originalText, token.key) {
            if termKeys.contains(token.key) { continue }
            // "восемнадцатую" became 18, "12 тысяч" became 12,000.
            if token.kind == .number, let value = Double(token.key), spokenNumbers.contains(value) { continue }
            return .rejected(.invented(token.text))
        }
        return .accepted
    }

    /// Share of the dictation's code, paths, numbers and terms a commit message may leave out.
    static let commitDroppableShare = 0.5

    // MARK: Length, format and language

    /// Longest acceptable rewrite: a multiple of the dictation's length plus a few characters.
    static func lengthLimit(_ style: DictationMode.Rewrite) -> (ratio: Double, slack: Double) {
        switch style {
        case .prompt: (1.7, 140)
        case .commit: (1.5, 80)
        case .cleaner: (1.15, 40)
        case .custom: (3, 240)
        case .selection: (3, 240)
        case .none: (1.6, 40)
        }
    }

    /// Cleanup and translation keep nearly everything; a much shorter answer lost content.
    static func minimumRatio(_ style: DictationMode.Rewrite) -> Double? {
        switch style {
        case .cleaner: 0.4
        case .none: 0.45
        case .prompt: 0.3
        case .commit, .custom, .selection: nil
        }
    }

    static func isConventionalHeader(_ text: String) -> Bool {
        let first = text.prefix { $0 != "\n" }
        return first.range(of: #"^[a-z]+(\([^)\n]+\))?!?: \S"#, options: .regularExpression) != nil
    }

    /// "feat(smart-structure): add lists" → " add lists": the scope is the model's own label.
    static func withoutCommitType(_ text: String) -> String {
        text.replacingOccurrences(of: #"^[a-z]+(\([^)\n]+\))?!?:"#, with: "", options: .regularExpression)
    }

    static func withoutListMarkers(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?m)^\s*\d{1,2}[.)]\s"#, with: "", options: .regularExpression)
    }

    /// English when translating or writing a commit, otherwise the script of the dictation.
    /// Latin words the dictation already had (terms, code) say nothing about the language.
    static func languageMatches(original: String, candidate: String, request: RewriteRequest) -> Bool {
        let kept = Set(Words.split(original).map(Words.key).filter { $0.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) } })
        func letters(_ text: String) -> (cyrillic: Int, latin: Int) {
            var cyrillic = 0, latin = 0
            for word in Words.split(text) {
                let key = Words.key(word)
                guard !kept.contains(key) else { continue }
                for scalar in key.unicodeScalars {
                    if (0x0400...0x04FF).contains(scalar.value) {
                        cyrillic += 1
                    } else if scalar.isASCII, CharacterSet.letters.contains(scalar) {
                        latin += 1
                    }
                }
            }
            return (cyrillic, latin)
        }
        let after = letters(candidate)
        if request.answersInEnglish {
            return Double(after.cyrillic) <= Double(after.cyrillic + after.latin) * 0.15
        }
        // Another target: Ukrainian is Cyrillic and Polish is Latin, so the script of the answer
        // says nothing about whether the model translated.
        if request.translate { return true }
        let before = letters(original)
        return before.cyrillic > before.latin ? after.cyrillic >= after.latin : after.cyrillic <= after.latin
    }

    // MARK: Protected tokens

    enum Kind: Equatable {
        case backticked, url, path, call, code, acronym, number, term
    }

    struct Token: Equatable {
        let text: String
        /// Lowercase comparison form with decimal points.
        let key: String
        let kind: Kind
        /// Positions in `Words.split` of the text, for self-corrections.
        var wordIndices: [Int]
        /// Other spellings that count as kept: "12 тысяч" is kept as 12000.
        var alternates: [String] = []

        var keys: [String] { [key] + alternates }
    }

    /// Links, paths and calls a model makes up do harm; a translated "GitHub" or "re-render" does not.
    static func inventable(_ token: Token) -> Bool {
        switch token.kind {
        case .url, .path, .call: true
        case .number: token.key.count > 1 && Int(token.key).map { $0 > 10 } ?? true
        default: false
        }
    }

    /// Code, links, paths, numbers and known terms of the text, each once, in reading order.
    static func protectedTokens(in text: String, terms: [String]) -> [Token] {
        var tokens: [Token] = []
        func add(_ raw: String, _ kind: Kind, word: Int) {
            let key = normalized(raw)
            guard !key.isEmpty else { return }
            if let i = tokens.firstIndex(where: { $0.key == key }) {
                if !tokens[i].wordIndices.contains(word) { tokens[i].wordIndices.append(word) }
            } else {
                tokens.append(Token(text: raw, key: key, kind: kind, wordIndices: [word]))
            }
        }

        for (inner, offset) in matchesWithOffsets(#"`([^`\n]+)`"#, in: text) {
            add(inner, .backticked, word: Words.split(String(text.prefix(offset))).count)
        }

        let words = Words.split(text)
        for (index, word) in words.enumerated() {
            let core = trimmed(word)
            guard !core.isEmpty else { continue }
            if core.range(of: #"^(?i)(https?://|www\.)\S+"#, options: .regularExpression) != nil {
                add(core, .url, word: index)
                continue
            }
            if core.unicodeScalars.allSatisfy(\.isASCII), core.contains(where: \.isLetter) {
                if core.contains("/"), core.range(of: #"^(~|\.{1,2})?/?[\w.@-]+(/[\w.@-]+)+/?$"#, options: .regularExpression) != nil {
                    add(core, .path, word: index)
                } else if core.range(of: #"^[\w-]{2,}\.[A-Za-z][A-Za-z0-9]{1,9}$"#, options: .regularExpression) != nil {
                    add(core, .path, word: index)
                } else if word.range(of: #"\w\(\)"#, options: .regularExpression) != nil {
                    add(core, .call, word: index)
                } else if Words.isCodeLike(core)
                    || core.range(of: #"^[A-Za-z]\w*_\w+$"#, options: .regularExpression) != nil
                    || core.range(of: #"^[A-Za-z]+[\w-]*\d[\w-]*$"#, options: .regularExpression) != nil
                    || core.range(of: #"^[vV]\d+(\.\d+)+$"#, options: .regularExpression) != nil
                    || core.range(of: #"^[a-z]+(-[a-z0-9]+)+$"#, options: .regularExpression) != nil {
                    add(core, .code, word: index)
                } else if (2...6).contains(core.count), core.allSatisfy({ $0.isUppercase || $0.isNumber }) {
                    add(core, .acronym, word: index)
                }
            }
            for (number, _) in matchesWithOffsets(#"(?<![\p{L}\p{N}_.,])(\d+(?:[.,:]\d+)*)"#, in: core) {
                add(number, .number, word: index)
                if index + 1 < words.count, let value = Int(number), let scale = NumberWords.value(Words.key(words[index + 1])),
                   NumberWords.multipliers.contains(scale), let i = tokens.firstIndex(where: { $0.key == number }) {
                    let scaled = String(value * Int(scale))
                    if !tokens[i].alternates.contains(scaled) { tokens[i].alternates.append(scaled) }
                }
            }
        }

        let lower = normalized(text)
        for term in terms {
            let key = normalized(term)
            // "ID" and "UI" are terms; "id" in "это id лида" is a word.
            let acronym = term.allSatisfy { !$0.isLetter || $0.isUppercase }
            guard !tokens.contains(where: { $0.key == key }), acronym ? contains(text, term) : contains(lower, key) else { continue }
            let first = String(key.split(separator: " ").first ?? "")
            let indices = words.indices.filter { normalized(trimmed(words[$0])).hasPrefix(first) }
            tokens.append(Token(text: term, key: key, kind: .term, wordIndices: indices.isEmpty ? [0] : indices))
        }
        return tokens
    }

    /// Whole-token search: no letter, digit or underscore touches the match, and a number is
    /// not part of a longer number ("5" is not in "5.1" or "15"). A unit may follow a number: "48px".
    static func contains(_ haystack: String, _ needle: String) -> Bool {
        let numeric = needle.first?.isNumber == true
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, range: searchRange) {
            let before = range.lowerBound > haystack.startIndex ? haystack[haystack.index(before: range.lowerBound)] : nil
            let after = range.upperBound < haystack.endIndex ? haystack[range.upperBound] : nil
            let afterNext = range.upperBound < haystack.endIndex ? haystack[haystack.index(after: range.upperBound)...].first : nil
            let touches = { (c: Character?) in c.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false }
            let touchesAfter = numeric ? after.map { $0.isNumber || $0 == "_" } ?? false : touches(after)
            var whole = !touches(before) && !touchesAfter
            if numeric, whole {
                let decimalBefore = before == "." && range.lowerBound > haystack.index(after: haystack.startIndex)
                    && haystack[haystack.index(range.lowerBound, offsetBy: -2)].isNumber
                let decimalAfter = (after == "." || after == ":") && afterNext?.isNumber == true
                whole = !decimalBefore && !decimalAfter
            }
            if whole { return true }
            searchRange = haystack.index(after: range.lowerBound)..<haystack.endIndex
        }
        return false
    }

    /// Lowercase, ё as е, "12,000" as 12000, "3,5" as 3.5 and "08:00" as 8:00.
    static func normalized(_ text: String) -> String {
        var result = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        if result.contains(",") {
            result = result.replacingOccurrences(of: #"(?<=\d),(?=\d{3}(?!\d))"#, with: "", options: .regularExpression)
            result = result.replacingOccurrences(of: #"(?<=\d),(?=\d)"#, with: ".", options: .regularExpression)
        }
        if result.contains(":") {
            result = result.replacingOccurrences(of: #"(?<![\d.])0(?=\d:\d)"#, with: "", options: .regularExpression)
        }
        return result
    }

    static func trimmed(_ word: String) -> String {
        var core = word.trimmingCharacters(in: CharacterSet(charactersIn: ",;:!?…«»\"'“”()[]{}*`").union(.whitespaces))
        while let last = core.last, last == "." || last == "," || last == ":" { core.removeLast() }
        return core
    }

    /// First capture group of every match, with the match's character offset.
    static func matchesWithOffsets(_ pattern: String, in text: String) -> [(String, Int)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let group = Range(match.range(at: 1), in: text), let whole = Range(match.range, in: text) else { return nil }
            return (String(text[group]), text.distance(from: text.startIndex, to: whole.lowerBound))
        }
    }

    // MARK: Self-corrections

    static let correctionCues: Set<String> = [
        "нет", "вернее", "точнее", "подожди", "погоди", "стоп", "ой", "извини", "наоборот", "поправка",
        "no", "wait", "sorry", "actually", "rather", "mean",
    ]

    /// "поставь 5, нет, подожди, 10" and "не в Vercel, а в Netlify": a model resolving the
    /// correction drops what the speaker took back.
    static func isNearCorrection(_ words: [String], at index: Int) -> Bool {
        guard words.indices.contains(index) else { return false }
        let keys = words.map(Words.key)
        let window = max(0, index - 5)...min(keys.count - 1, index + 5)
        if window.contains(where: { correctionCues.contains(keys[$0]) }) { return true }
        let before = max(0, index - 3)..<index
        let after = min(keys.count, index + 1)..<min(keys.count, index + 5)
        return before.contains { keys[$0] == "не" } && after.contains { keys[$0] == "а" }
    }
}
