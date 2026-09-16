import Foundation

/// A user dictionary entry: how a term sounds in Russian speech and how to write it.
public struct DictionaryEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        case manual
        case history
    }

    public var id: UUID
    /// What Whisper tends to write, e.g. "юз эффект". Empty when only the spelling matters.
    public var heard: String
    /// The canonical spelling, e.g. "useEffect".
    public var written: String
    public var source: Source

    public init(id: UUID = UUID(), heard: String, written: String, source: Source = .manual) {
        self.id = id
        self.heard = heard
        self.written = written
        self.source = source
    }

    public static let starter: [DictionaryEntry] = [
        .init(heard: "юз эффект", written: "useEffect"),
        .init(heard: "юз стейт", written: "useState"),
        .init(heard: "версель", written: "Vercel"),
        .init(heard: "супабейс", written: "Supabase"),
        .init(heard: "некст джей эс", written: "Next.js"),
        .init(heard: "тайпскрипт", written: "TypeScript"),
        .init(heard: "реакт квери", written: "React Query"),
        .init(heard: "гитхаб экшенс", written: "GitHub Actions"),
        .init(heard: "призма", written: "Prisma"),
        .init(heard: "докер композ", written: "Docker Compose"),
    ]
}

/// Applies dictionary spellings to recognised text.
public struct DictionaryRewriter: Sendable {
    private let canonicalizer: TermCanonicalizer
    private let heardRules: [(pattern: NSRegularExpression, written: String)]

    public init(entries: [DictionaryEntry], builtInTerms: [String] = PromptBuilder.builtInTerms) {
        canonicalizer = TermCanonicalizer(terms: entries.map(\.written) + builtInTerms)
        heardRules = entries.compactMap { entry in
            let heard = entry.heard.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !heard.isEmpty else { return nil }
            let words = heard.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
            let pattern = #"(?<![\p{L}\p{N}])"# + words.joined(separator: #"[\s-]+"#) + #"(?![\p{L}\p{N}])"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            return (regex, entry.written)
        }
    }

    public func apply(to text: String) -> String {
        var result = text
        for rule in heardRules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.pattern.stringByReplacingMatches(in: result, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: rule.written))
        }
        return canonicalizer.apply(to: result)
    }

    /// Terms for the Whisper prompt: user entries first, then built-ins, without duplicates.
    public static func promptTerms(entries: [DictionaryEntry], builtInTerms: [String] = PromptBuilder.builtInTerms) -> [String] {
        var seen = Set<String>()
        return (entries.map(\.written) + builtInTerms).filter { term in
            let key = TermCanonicalizer.squash(term)
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}
