import Foundation

/// Turns a hand-edited dictation into dictionary entries, so the same words come out right the
/// next time they are spoken.
///
/// Only fixes of *spelling* are learned. A dictionary entry is a rule applied to every future
/// dictation, so a rewritten sentence must not become one: "поправь это" → "fix this" is a
/// translation, not a rule. A fix counts when the two sides are the same term written differently:
/// they differ in case only ("github" → "GitHub"), or they sound alike across scripts
/// ("хедер" → "Header", "юз эффект" → "useEffect").
public enum EditLearning {
    /// At most this many entries come from one edit.
    public static let entryLimit = 5
    /// Longer runs are a rewrite, not a term.
    static let wordLimit = 3
    static let lengthLimit = 40
    /// A term the app already knows only has to sound roughly right; an unknown one must match well.
    static let similarityLimit = 0.5
    static let knownTermSimilarityLimit = 0.3
    /// Within one script a fix is learned only word for word, and only when it is close to a typo.
    static let sameScriptSimilarityLimit = 0.7

    /// Dictionary entries for the spelling fixes in `edited`, newest first.
    ///
    /// - Parameters:
    ///   - raw: the transcript as Whisper wrote it; the entries' "heard" side comes from it.
    ///   - text: what the dictation inserted, before the edit.
    ///   - edited: the text after the user edited it.
    ///   - knownTerms: spellings the app already knows: the user's dictionary, the built-in one
    ///     and identifiers from the user's code folders.
    public static func corrections(raw: String, text: String, edited: String, knownTerms: [String] = []) -> [DictionaryEntry] {
        let known = Set(knownTerms.map(TermCanonicalizer.squash).filter { !$0.isEmpty })
        var entries: [DictionaryEntry] = []
        var seen = Set<String>()
        for change in changes(from: text, to: edited) {
            guard entries.count < entryLimit else { break }
            let heard = HistoryCorrection.heard(raw: raw, text: text, words: change.before)
            let written = spelling(of: change.after, in: edited)
            guard isSpellingFix(heard: heard, written: written, knownTerms: known),
                  let entry = HistoryCorrection.entry(heard: heard, written: written),
                  seen.insert(entry.heard.lowercased() + "→" + entry.written.lowercased()).inserted
            else { continue }
            entries.append(entry)
        }
        return entries
    }

    /// A run of words replaced by other words. Runs where one side is empty — words only added or
    /// only removed — are left out: they map no spelling onto another.
    struct Change: Equatable {
        var before: ClosedRange<Int>
        var after: ClosedRange<Int>
    }

    /// Words are lined up by their comparison key, so a word rewritten in another case lines up
    /// with itself; it is reported as a change all the same, for "github" → "GitHub".
    static func changes(from text: String, to edited: String) -> [Change] {
        let before = Words.split(text)
        let after = Words.split(edited)
        guard !before.isEmpty, !after.isEmpty else { return [] }
        let pairs = Words.alignment(before.map(Words.key), after.map(Words.key))
        var changes: [Change] = []
        var beforeStart = 0
        var afterStart = 0
        for (b, a) in pairs + [(before.count, after.count)] {
            if b > beforeStart, a > afterStart {
                changes.append(Change(before: beforeStart...(b - 1), after: afterStart...(a - 1)))
            }
            if b < before.count, a < after.count, before[b] != after[a] {
                changes.append(Change(before: b...b, after: a...a))
            }
            beforeStart = b + 1
            afterStart = a + 1
        }
        return changes
    }

    /// The edited words as they should be written: surrounding punctuation dropped, so a fix
    /// typed as "Header." teaches "Header". Inner marks stay, for "Next.js" and "feature/auth".
    private static func spelling(of range: ClosedRange<Int>, in edited: String) -> String {
        Words.split(edited)[range]
            .map { $0.trimmingCharacters(in: edgeMarks) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static let edgeMarks = CharacterSet(charactersIn: ".,!?;:…«»\"'()[]{}")

    // MARK: The filter

    static func isSpellingFix(heard: String, written: String, knownTerms: Set<String>) -> Bool {
        guard !heard.isEmpty, !written.isEmpty else { return false }
        guard heard.count <= lengthLimit, written.count <= lengthLimit else { return false }
        let heardWords = Words.split(heard)
        let writtenWords = Words.split(written)
        guard heardWords.count <= wordLimit, writtenWords.count <= wordLimit else { return false }
        let isTerm = isTermLike(written, words: writtenWords, knownTerms: knownTerms)
        if heard.lowercased() == written.lowercased() {
            // "github" → "GitHub": only the spelling changed. Learned for a term, never for a
            // plain word: "fix" → "Fix" is the start of a sentence, not a rule.
            return heard != written && isTerm
        }

        let similarity = similarity(heard, written)
        guard written.contains(where: { $0.isASCII && $0.isLetter }) else {
            // Both sides in the same script: a typo-level fix of one word, never a reworded phrase.
            return heardWords.count == 1 && writtenWords.count == 1 && similarity >= sameScriptSimilarityLimit
        }
        return similarity >= (isTerm ? knownTermSimilarityLimit : similarityLimit)
    }

    /// A term rather than a plain word: one the app already knows, an identifier, or a spelling
    /// with a capital inside it like GitHub, API or iOS.
    private static func isTermLike(_ written: String, words: [String], knownTerms: Set<String>) -> Bool {
        knownTerms.contains(TermCanonicalizer.squash(written))
            || words.allSatisfy(Words.isCodeLike)
            || written.dropFirst().contains(where: \.isUppercase)
    }

    /// How close two spellings sound, 0…1. Cyrillic is transliterated first, so "хедер" and
    /// "Header" are compared as "heder" and "header".
    static func similarity(_ a: String, _ b: String) -> Double {
        let left = sound(a)
        let right = sound(b)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let distance = distance(Array(left), Array(right))
        return 1 - Double(distance) / Double(max(left.count, right.count))
    }

    /// Lowercase latin letters and digits: Cyrillic by sound, everything else as written.
    static func sound(_ text: String) -> String {
        var result = ""
        for character in text.lowercased() {
            if let latin = Self.latin[character] {
                result += latin
            } else if character.isLetter || character.isNumber {
                result.append(character)
            }
        }
        return result
    }

    private static let latin: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh",
        "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o",
        "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "ts",
        "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu",
        "я": "ya",
    ]

    private static func distance(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty else { return b.count }
        var row = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var previous = row[0]
            row[0] = i + 1
            for (j, right) in b.enumerated() {
                let insert = row[j + 1] + 1
                let delete = row[j] + 1
                let replace = previous + (left == right ? 0 : 1)
                previous = row[j + 1]
                row[j + 1] = min(insert, delete, replace)
            }
        }
        return row[b.count]
    }
}
