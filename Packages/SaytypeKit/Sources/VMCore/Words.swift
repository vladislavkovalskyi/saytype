import Foundation

public enum Words {
    /// Splits text into words on whitespace, keeping punctuation attached.
    public static func split(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Comparison key: lowercase, ё→е, no surrounding punctuation.
    public static func key(_ word: String) -> String {
        let trimmed = word.trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
        return trimmed.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    public static func keys(_ text: String) -> [String] {
        split(text).map(key).filter { !$0.isEmpty }
    }
}

extension Words {
    /// True for identifiers worth showing in a code font: `useEffect`, `Next.js`,
    /// `feature/auth`, `OPENAI_API_KEY`, `localhost:3000`. Plain words like `Vercel` stay prose.
    public static func isCodeLike(_ word: String) -> Bool {
        let core = word.trimmingCharacters(in: CharacterSet(charactersIn: ",;:!?…«»\"'()[]").union(.whitespaces))
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        guard core.count > 1, core.unicodeScalars.allSatisfy({ $0.isASCII }),
              core.contains(where: { $0.isLetter }) else { return false }
        if core.range(of: #"[a-z][A-Z]"#, options: .regularExpression) != nil { return true }
        if core.filter(\.isLetter).count >= 3, core.range(of: #"[A-Za-z0-9][./_:][A-Za-z0-9]"#, options: .regularExpression) != nil { return true }
        if core.hasPrefix("/") || core.hasPrefix("."), core.count > 2 { return true }
        return false
    }
}

extension Words {
    /// Index pairs of a longest common subsequence of two word lists, in order. Used to line up
    /// what was heard, what was written and what the user edited.
    public static func alignment(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let n = a.count
        let m = b.count
        guard n > 0, m > 0 else { return [] }
        var table = [Int32](repeating: 0, count: (n + 1) * (m + 1))
        for x in stride(from: n - 1, through: 0, by: -1) {
            for y in stride(from: m - 1, through: 0, by: -1) {
                table[x * (m + 1) + y] = a[x] == b[y]
                    ? table[(x + 1) * (m + 1) + y + 1] + 1
                    : max(table[(x + 1) * (m + 1) + y], table[x * (m + 1) + y + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var x = 0
        var y = 0
        while x < n, y < m {
            if a[x] == b[y] {
                pairs.append((x, y))
                x += 1
                y += 1
            } else if table[(x + 1) * (m + 1) + y] >= table[x * (m + 1) + y + 1] {
                x += 1
            } else {
                y += 1
            }
        }
        return pairs
    }
}
