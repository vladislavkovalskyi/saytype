import Foundation

/// Rewrites terms Whisper split or capitalised differently to their canonical
/// spelling: "Use Effect" and "UseEffect" become "useEffect".
///
/// Matches up to three consecutive words whose letters, ignoring case, spaces,
/// dots and hyphens, equal a term. Punctuation after the last word is kept.
public struct TermCanonicalizer: Sendable {
    private let terms: [String: String]
    private let longestTerm: Int

    public init(terms: [String]) {
        var map: [String: String] = [:]
        var longest = 1
        for term in terms {
            let key = Self.squash(term)
            guard !key.isEmpty else { continue }
            map[key] = term
            longest = max(longest, Words.split(term).count + 1)
        }
        self.terms = map
        self.longestTerm = min(longest, 3)
    }

    public func apply(to text: String) -> String {
        let words = Words.split(text)
        guard !words.isEmpty, !terms.isEmpty else { return text }
        var output: [String] = []
        var i = 0
        while i < words.count {
            var matched = false
            for span in stride(from: min(longestTerm, words.count - i), through: 1, by: -1) {
                let slice = words[i..<i + span]
                // "docker, compose" is two separate words, not one term.
                let innerBoundariesClean = slice.dropLast().allSatisfy { $0.last?.isLetter == true || $0.last?.isNumber == true }
                    && slice.dropFirst().allSatisfy { $0.first?.isLetter == true || $0.first?.isNumber == true }
                guard innerBoundariesClean else { continue }
                let (leading, trailing) = Self.edgePunctuation(first: slice.first!, last: slice.last!)
                let key = Self.squash(slice.joined())
                if let term = terms[key] {
                    output.append(leading + term + trailing)
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

    static func squash(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func edgePunctuation(first: String, last: String) -> (String, String) {
        let leading = String(first.prefix { !$0.isLetter && !$0.isNumber })
        let trailing = String(last.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
        return (leading, trailing)
    }
}
