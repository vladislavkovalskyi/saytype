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
