import Foundation

/// Removes phrases Whisper invents on silence or noise. Most come from the
/// subtitles of its Russian training data.
public enum HallucinationFilter {
    static let phrases: [String] = [
        "субтитры сделал dimatorzok",
        "субтитры делал dimatorzok",
        "субтитры создавал dimatorzok",
        "субтитры подготовил dimatorzok",
        "субтитры by dimatorzok",
        "редактор субтитров а.семкин корректор а.егорова",
        "продолжение следует",
        "спасибо за просмотр",
        "ставьте лайки и подписывайтесь на канал",
        "подписывайтесь на канал",
        "до новых встреч",
        "thank you for watching",
        "thanks for watching",
    ]

    /// What Whisper answers to a breath, a click or silence when it decodes one anyway, in any
    /// case and with any punctuation. Only a whole result counts.
    static let standalone: Set<String> = [
        "thank you",
        "thank you very much",
        "thank you so much",
    ]

    /// True when the whole result is one of Whisper's answers to silence. The caller drops it
    /// and the user sees "Nothing heard"; the cost is that a dictation of only "thank you" in
    /// English is lost. "Thank you, see you tomorrow" is kept. Not for Whisper's own
    /// translation, where «спасибо» really is "Thank you."
    public static func isStandalone(_ text: String) -> Bool {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        return standalone.contains(words.joined(separator: " "))
    }

    /// Removes the invented phrases wherever they occur in the text.
    public static func clean(_ text: String) -> String {
        var result = text
        for phrase in phrases {
            result = remove(phrase, from: result)
        }
        result = result
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let meaningful = result.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return meaningful.isEmpty ? "" : result
    }

    private static func remove(_ phrase: String, from text: String) -> String {
        // "а.семкин" may come back as "А. Семкин": allow optional spaces after dots.
        let words = phrase.split(separator: " ").map { word in
            NSRegularExpression.escapedPattern(for: String(word)).replacingOccurrences(of: #"\."#, with: #"\.\s*"#)
        }
        let pattern = #"[\s,]*"# + words.joined(separator: #"\s+"#) + #"[.!…]*"#
        return text.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
    }
}
