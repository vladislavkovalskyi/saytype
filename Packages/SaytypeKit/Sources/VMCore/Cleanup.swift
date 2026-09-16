import Foundation

/// Deterministic text fixes that never change meaning: filler removal and
/// trailing punctuation for short commands.
public enum Cleanup {
    static let hesitations: Set<String> = ["э", "ээ", "эээ", "ээээ", "эм", "эмм", "м", "мм", "ммм", "мммм", "а-а", "ааа", "аааа", "хм", "хмм"]
    static let fillerWords: Set<String> = ["ну", "типа", "короче"]
    static let fillerPhrases: [[String]] = [["как", "бы"], ["в", "общем"]]

    public static func removeFillers(_ text: String, mode: AppSettings.FillerMode) -> String {
        guard mode != .keep else { return text }
        let words = Words.split(text)
        var result: [String] = []
        var capitalizeNext = false
        var i = 0
        while i < words.count {
            let word = words[i]
            let key = Words.key(word)
            var span = 0
            if hesitations.contains(key) {
                span = 1
            } else if mode == .all {
                if fillerWords.contains(key) {
                    span = 1
                } else if let phrase = fillerPhrases.first(where: { phrase in
                    i + phrase.count <= words.count && zip(phrase, words[i..<i + phrase.count]).allSatisfy { $0 == Words.key($1) }
                }) {
                    span = phrase.count
                }
            }
            guard span > 0 else {
                result.append(capitalizeNext ? capitalizeFirst(word) : word)
                capitalizeNext = false
                i += 1
                continue
            }
            let removed = words[i..<i + span]
            let wasSentenceStart = removed.first?.first?.isUppercase == true
            let endPunctuation = String(removed.last!.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
            // Keep sentence-ending punctuation of a removed word by moving it back.
            if endPunctuation.contains(where: { ".!?…".contains($0) }), let last = result.popLast() {
                result.append(last.trimmingCharacters(in: CharacterSet(charactersIn: ",")) + endPunctuation.filter { ".!?…".contains($0) })
                capitalizeNext = true
            } else if wasSentenceStart {
                capitalizeNext = true
            }
            i += span
        }
        return result.joined(separator: " ")
    }

    /// "Открой настройки." → "Открой настройки" for phrases up to `maxWords` long.
    public static func dropTrailingPeriod(_ text: String, maxWords: Int = 6) -> String {
        guard Words.split(text).count <= maxWords, text.hasSuffix("."), !text.hasSuffix("..") else { return text }
        return String(text.dropLast())
    }

    static func capitalizeFirst(_ word: String) -> String {
        guard let first = word.first, first.isLowercase else { return word }
        return first.uppercased() + word.dropFirst()
    }
}
