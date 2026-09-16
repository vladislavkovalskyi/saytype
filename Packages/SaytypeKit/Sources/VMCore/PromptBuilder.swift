import Foundation

/// Builds the text Whisper sees as "what came before" the recording.
///
/// Listing terms in Latin makes Whisper spell them that way. Every prompt token
/// is decoded one by one before the audio, so the prompt stays short: on an M3 Pro
/// 16 terms add about half a second, a full punctuated sample adds a second.
public enum PromptBuilder {
    static let characterLimit = 240
    /// Whisper keeps at most 224 prompt tokens. The character limit is usually tighter; the token
    /// estimate guards Cyrillic entries and long camelCase names, which take more tokens per letter.
    static let tokenLimit = 224
    /// Project identifiers offered to the prompt, best first; the character limit decides how many stay.
    public static let projectTermLimit = 24

    public static func prompt(glossary: [String]) -> String? {
        var list = ""
        var tokens = 1
        for term in glossary {
            let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            let next = list.isEmpty ? term : list + ", " + term
            let nextTokens = tokens + estimatedTokens(term) + (list.isEmpty ? 0 : 1)
            if next.count + 1 > characterLimit || nextTokens > tokenLimit { break }
            list = next
            tokens = nextTokens
        }
        return list.isEmpty ? nil : list + "."
    }

    /// A pessimistic count of GPT-2 byte-pair tokens: a token per camelCase part or four Latin
    /// letters, per mark, and per Cyrillic letter.
    static func estimatedTokens(_ term: String) -> Int {
        var count = 0
        var run = 0
        var previousLower = false
        func flush() {
            count += (run + 3) / 4
            run = 0
        }
        for scalar in term.unicodeScalars {
            let value = scalar.value
            let isUpper = value >= 0x41 && value <= 0x5A
            let isLower = value >= 0x61 && value <= 0x7A
            let isDigit = value >= 0x30 && value <= 0x39
            if isUpper || isLower || isDigit {
                if isUpper && previousLower { flush() }
                run += 1
            } else {
                flush()
                if value != 0x20 { count += 1 }
            }
            previousLower = isLower
        }
        flush()
        return max(count, 1)
    }

    /// Terms developers dictate most often. The user's dictionary goes first.
    public static let builtInTerms = [
        "Claude Code", "ChatGPT", "Cursor", "useEffect", "useState", "React", "Next.js", "TypeScript",
        "Vercel", "Supabase", "Docker", "Postgres", "Redis", "Prisma", "Tailwind", "GitHub",
        "API", "SwiftUI", "Figma",
    ]
}
