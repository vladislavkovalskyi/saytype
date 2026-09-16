import Foundation
import Synchronization

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

    private let builtIn: Bool

    /// - Parameters:
    ///   - builtIn: also apply `BuiltInDictionary` after the user's own entries.
    ///   - projectTerms: identifiers from the user's code folders: "use user data" → useUserData.
    public init(entries: [DictionaryEntry], builtIn: Bool = false, builtInTerms: [String] = PromptBuilder.builtInTerms, projectTerms: [String] = []) {
        self.builtIn = builtIn
        canonicalizer = TermCanonicalizer(
            terms: entries.map(\.written) + builtInTerms + (builtIn ? BuiltInDictionary.canonicalTerms : []),
            projectTerms: projectTerms
        )
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
        // The user's entries run first, so they win over a built-in spelling of the same words.
        if builtIn { result = BuiltInDictionary.apply(to: result) }
        return canonicalizer.apply(to: result)
    }

    /// Terms for the Whisper prompt: user entries first, then project identifiers, then
    /// built-ins, without duplicates. `PromptBuilder` keeps as many as fit.
    public static func promptTerms(entries: [DictionaryEntry], builtInTerms: [String] = PromptBuilder.builtInTerms, projectTerms: [String] = []) -> [String] {
        var seen = Set<String>()
        return (entries.map(\.written) + projectTerms.prefix(PromptBuilder.projectTermLimit) + builtInTerms).filter { term in
            let key = TermCanonicalizer.squash(term)
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private struct CacheKey: Equatable {
        let entries: [DictionaryEntry]
        let builtIn: Bool
        let projectTerms: [String]
    }

    private static let cache = Mutex<(key: CacheKey, rewriter: DictionaryRewriter)?>(nil)

    /// The rewriter for these settings, built once and reused while they stay the same.
    /// Building one compiles a regular expression per entry and indexes about a thousand terms.
    public static func cached(entries: [DictionaryEntry], builtIn: Bool, projectTerms: [String] = []) -> DictionaryRewriter {
        let key = CacheKey(entries: entries, builtIn: builtIn, projectTerms: projectTerms)
        if let hit = cache.withLock({ $0?.key == key ? $0?.rewriter : nil }) { return hit }
        let rewriter = DictionaryRewriter(entries: entries, builtIn: builtIn, projectTerms: projectTerms)
        cache.withLock { $0 = (key, rewriter) }
        return rewriter
    }
}
