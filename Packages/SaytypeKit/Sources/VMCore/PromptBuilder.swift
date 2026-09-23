import Foundation

/// Builds the text Whisper sees as "what came before" the recording.
///
/// Listing terms in Latin makes Whisper spell them that way. The prompt comes out of each
/// 30-second window's budget of 224 decoder tokens, and it is fed to the decoder one token at a
/// time before every window. An 85-token prompt left 133 tokens for the text, less than fast
/// Russian needs in 30 s, and the rest of the window was lost; 40 tokens leave about 180.
public enum PromptBuilder {
    static let characterLimit = 240
    /// Real tokens when the engine has its tokenizer, the estimate below otherwise.
    public static let tokenLimit = 40
    /// Project identifiers offered to the prompt, best first; the token limit decides how many stay.
    public static let projectTermLimit = 24

    /// Terms in the order given, most important first, as many as fit. A term that does not fit
    /// is skipped and a shorter one after it may still get in. `countTokens` measures the whole
    /// prompt as the decoder will see it.
    public static func prompt(glossary: [String], tokenLimit: Int = tokenLimit, countTokens: (String) -> Int = estimatedTokens) -> String? {
        var list = ""
        for term in glossary {
            let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            let next = list.isEmpty ? term : list + ", " + term
            guard next.count + 1 <= characterLimit, countTokens(next + ".") <= tokenLimit else { continue }
            list = next
        }
        return list.isEmpty ? nil : list + "."
    }

    /// A pessimistic count of GPT-2 byte-pair tokens: a token per camelCase part or four Latin
    /// letters, per mark, and per Cyrillic letter.
    public static func estimatedTokens(_ term: String) -> Int {
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
