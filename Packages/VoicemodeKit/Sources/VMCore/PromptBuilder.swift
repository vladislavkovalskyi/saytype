import Foundation

/// Builds the text Whisper sees as "what came before" the recording.
///
/// Listing terms in Latin makes Whisper spell them that way. Every prompt token
/// is decoded one by one before the audio, so the prompt stays short: on an M3 Pro
/// 16 terms add about half a second, a full punctuated sample adds a second.
public enum PromptBuilder {
    static let characterLimit = 240

    public static func prompt(glossary: [String]) -> String? {
        var list = ""
        for term in glossary {
            let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            let next = list.isEmpty ? term : list + ", " + term
            if next.count + 1 > characterLimit { break }
            list = next
        }
        return list.isEmpty ? nil : list + "."
    }

    /// Terms developers dictate most often. The user's dictionary goes first.
    public static let builtInTerms = [
        "useEffect", "useState", "React", "Next.js", "TypeScript", "Vercel", "Supabase",
        "Docker Compose", "Postgres", "Redis", "Prisma", "Zod", "GitHub Actions",
        "React Query", "SwiftUI", "Tailwind", "npm", "API", "README", "Claude Code",
    ]
}
