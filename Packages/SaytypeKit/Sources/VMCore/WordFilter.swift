import Foundation

/// User filters: words and phrases removed from dictations, and optional masking of swear words.
public enum WordFilter {
    /// Removes each filter as a whole word or phrase, ignoring case; spacing and a comma
    /// left hanging after the removal are tidied up.
    public static func remove(_ filters: [String], from text: String) -> String {
        var result = text
        for filter in filters {
            let words = Words.split(filter.lowercased()).map { NSRegularExpression.escapedPattern(for: $0) }
            guard !words.isEmpty else { continue }
            let pattern = #"(?<![\p{L}\p{N}])"# + words.joined(separator: #"[\s-]+"#) + #"(?![\p{L}\p{N}])[,]?"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        guard result != text else { return text }
        return tidy(result, capitalize: text.first?.isUppercase == true)
    }

    /// "бля, это не работает" → "б**, это не работает". Covers common Russian and English stems.
    public static func censorProfanity(_ text: String) -> String {
        Words.split(text).map { word in
            let core = Words.key(word)
            guard isProfane(core), let first = core.first else { return word }
            let masked = String(first) + String(repeating: "*", count: max(2, core.count - 1))
            return word.replacingOccurrences(of: core, with: masked, options: [.caseInsensitive])
        }
        .joined(separator: " ")
    }

    static func isProfane(_ key: String) -> Bool {
        guard key.count >= 3 else { return false }
        if profaneWords.contains(key) { return true }
        return profaneStems.contains { stem in
            key.hasPrefix(stem.prefix) && !stem.exceptions.contains(where: key.hasPrefix)
        }
    }

    private static let profaneWords: Set<String> = [
        "бля", "блять", "блядь", "бляха", "сука", "суки", "суке", "суку", "сучка", "нах", "нахер", "нахрен", "хер",
        "fuck", "fucking", "fucked", "shit", "bitch", "asshole", "dick", "cunt", "motherfucker", "bullshit",
    ]

    private static let profaneStems: [(prefix: String, exceptions: [String])] = [
        ("хуй", []), ("хуе", ["хуел"]), ("хуё", []), ("хуя", []), ("хуи", []),
        ("пизд", []), ("ебан", []), ("ебат", []), ("ебал", []), ("ебу", []), ("ёб", []), ("еб", ["ебенд"]),
        ("заеб", []), ("заёб", []), ("выеб", []), ("уеб", []), ("уёб", []), ("проеб", []), ("проёб", []), ("наеб", []), ("наёб", []),
        ("отъеб", []), ("разъеб", []), ("долбоеб", []), ("долбоёб", []), ("мудак", []), ("мудил", []), ("пидор", []), ("пидар", []),
        ("блядс", []), ("бляд", []), ("fuck", []), ("shitt", []),
    ]

    static func tidy(_ text: String, capitalize: Bool) -> String {
        var result = text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+([,.!?…:;])"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"^[\s,]+"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #",([.!?…])"#, with: "$1", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespaces)
        if let first = result.first, first.isLowercase, capitalize {
            result = first.uppercased() + result.dropFirst()
        }
        return result
    }
}
