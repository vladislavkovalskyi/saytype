import Foundation

/// Rewrites terms Whisper split or capitalised differently to their canonical
/// spelling: "Use Effect" and "UseEffect" become "useEffect".
///
/// Matches up to three consecutive words whose letters, ignoring case, spaces,
/// dots and hyphens, equal a term. Punctuation after the last word is kept.
///
/// Project identifiers match more strictly, since they are many and made of plain English
/// words: "use user data" becomes useUserData, but a single word only when it already looks
/// like code ("useUserdata"), so "database" never turns into a project's `DataBase`.
public struct TermCanonicalizer: Sendable {
    private let terms: [String: String]
    private let longestTerm: Int
    /// Squashed key → identifier and the number of its camelCase or snake_case parts.
    private let projectTerms: [String: (term: String, parts: Int)]
    private let longestProjectTerm: Int

    /// Spoken as separate words, a project identifier needs at least this many letters.
    static let minimumSpokenProjectKey = 8
    static let maximumProjectSpan = 4

    public init(terms: [String], projectTerms: [String] = []) {
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

        var projectMap: [String: (term: String, parts: Int)] = [:]
        var longestProject = 0
        for term in projectTerms where DeveloperText.isASCII(term) && !term.contains(" ") {
            let key = Self.squash(term)
            let parts = DeveloperText.parts(of: term).count
            // Single words ("Header", "zod") stay as spoken; the built-in terms win over a project's spelling.
            guard parts >= 2, key.count >= 4, map[key] == nil, projectMap[key] == nil else { continue }
            projectMap[key] = (term, parts)
            longestProject = max(longestProject, min(parts, Self.maximumProjectSpan))
        }
        self.projectTerms = projectMap
        self.longestProjectTerm = longestProject
    }

    public func apply(to text: String) -> String {
        let words = Words.split(text)
        guard !words.isEmpty, !terms.isEmpty || !projectTerms.isEmpty else { return text }
        // Keys and word edges once per word; a span's key is its words' keys joined.
        let keys = words.map(Self.squash)
        let startsClean = words.map { $0.first?.isLetter == true || $0.first?.isNumber == true }
        let endsClean = words.map { $0.last?.isLetter == true || $0.last?.isNumber == true }
        let longest = max(longestTerm, longestProjectTerm)
        var output: [String] = []
        output.reserveCapacity(words.count)
        var i = 0
        while i < words.count {
            var matched = false
            for span in stride(from: min(longest, words.count - i), through: 1, by: -1) {
                let slice = words[i..<i + span]
                // "docker, compose" is two separate words, not one term.
                guard (i..<i + span - 1).allSatisfy({ endsClean[$0] && startsClean[$0 + 1] }) else { continue }
                let key = span == 1 ? keys[i] : keys[i..<i + span].joined()
                guard !key.isEmpty else { continue }
                let term: String?
                if span <= longestTerm, let known = terms[key] {
                    term = known
                } else if let project = projectTerms[key], span <= project.parts,
                          span == 1 ? Self.looksLikeCode(slice.first!) : key.count >= Self.minimumSpokenProjectKey {
                    term = project.term
                } else {
                    term = nil
                }
                if let term {
                    let (leading, trailing) = Self.edgePunctuation(first: slice.first!, last: slice.last!)
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

    /// "useUserdata", "use_user_data", "UseUserData": a capital inside the word or a joining mark.
    private static func looksLikeCode(_ word: String) -> Bool {
        let letters = word.drop { !$0.isLetter }
        return letters.dropFirst().contains(where: \.isUppercase) || word.contains("_") || word.contains("-")
    }

    private static func edgePunctuation(first: String, last: String) -> (String, String) {
        let leading = String(first.prefix { !$0.isLetter && !$0.isNumber })
        let trailing = String(last.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
        return (leading, trailing)
    }
}
