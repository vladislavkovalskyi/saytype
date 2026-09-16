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
