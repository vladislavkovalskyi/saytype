import Foundation

/// Developer, AI and design terms shipped with saytype: how they sound in Russian speech
/// and how they are written. Generated from design/dictionary/terms.txt.
public enum BuiltInDictionary {
    public struct Term: Identifiable, Hashable, Sendable {
        public let written: String
        /// Base heard forms as listed in the source, without generated case endings.
        public let heard: [String]
        public let category: String
        public var id: String { written }
    }

    public struct Category: Identifiable, Hashable, Sendable {
        public let key: String
        public let title: String
        public var id: String { key }
    }

    public static let categories: [Category] = categoryData.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        return parts.count == 2 ? Category(key: parts[0], title: parts[1]) : nil
    }

    public static let terms: [Term] = catalogData.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return nil }
        return Term(written: parts[1], heard: parts[2].split(separator: "|").map(String.init), category: parts[0])
    }

    /// Normalized heard form, including case endings → written term.
    static let lookup: [String: String] = {
        var map: [String: String] = [:]
        for line in lookupData.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            if parts.count == 2 { map[parts[0]] = parts[1] }
        }
        return map
    }()

    static let longestHeard: Int = lookup.keys.map { $0.split(separator: " ").count }.max() ?? 1

    /// Terms whose Latin spelling is distinctive enough to fix variants like "next js" or
    /// "github". Plain capitalised words (React, Stripe, Swift) are left alone: in English
    /// speech they are often ordinary words.
    public static let canonicalTerms: [String] = terms.map(\.written).filter(isDistinctive)

    static func isDistinctive(_ term: String) -> Bool {
        let letters = term.filter(\.isLetter)
        // ".env" and "C++" start or end with punctuation the canonicalizer would double.
        guard letters.count >= 2, term.first?.isLetter == true, term.last.map({ $0.isLetter || $0.isNumber }) == true else { return false }
        if term.contains(where: { " ./#+-_0123456789".contains($0) }) { return true }
        if letters.allSatisfy(\.isUppercase) { return true }
        return term.dropFirst().contains(where: \.isUppercase)
    }

    /// First word of every heard form: most dictated words start none and are skipped at once.
    static let firstWords: Set<Substring> = Set(lookup.keys.map { $0.prefix { $0 != " " } })

    /// Replaces heard forms with written terms: "поправь юз эффект в реакте" →
    /// "поправь useEffect в React". Punctuation around a match is kept.
    public static func apply(to text: String) -> String {
        let words = Words.split(text)
        guard !words.isEmpty else { return text }
        // Each word is normalised once; a span's key joins these.
        let keys = words.map(normalize)
        let startsClean = words.map { $0.first.map { $0.isLetter || $0.isNumber } ?? false }
        let endsClean = words.map { $0.last.map { $0.isLetter || $0.isNumber } ?? false }
        var output: [String] = []
        output.reserveCapacity(words.count)
        var i = 0
        while i < words.count {
            var matched = false
            if !keys[i].isEmpty, firstWords.contains(keys[i].prefix { $0 != " " }) {
                for span in stride(from: min(longestHeard, words.count - i), through: 1, by: -1) {
                    // "докер, композ" is two separate words, not one term.
                    let last = i + span - 1
                    guard (i..<last).allSatisfy({ endsClean[$0] }), (i + 1..<last + 1).allSatisfy({ startsClean[$0] }) else { continue }
                    let key = span == 1 ? keys[i] : keys[i...last].joined(separator: " ")
                    guard let written = lookup[key] else { continue }
                    let leading = words[i].prefix { !$0.isLetter && !$0.isNumber }
                    let trailing = String(words[last].reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
                    output.append(leading + written + trailing)
                    i += span
                    matched = true
                    break
                }
            }
            if !matched {
                output.append(words[i])
                i += 1
            }
        }
        return output.joined(separator: " ")
    }

    private static func normalize(_ word: String) -> String {
        core(word)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func core(_ word: String) -> String {
        let start = word.firstIndex { $0.isLetter || $0.isNumber } ?? word.endIndex
        let end = word.lastIndex { $0.isLetter || $0.isNumber }.map { word.index(after: $0) } ?? start
        return start < end ? String(word[start..<end]) : ""
    }
}
