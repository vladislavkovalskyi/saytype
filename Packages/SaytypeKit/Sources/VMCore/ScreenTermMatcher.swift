import Foundation

/// Rewrites what Whisper heard to the spelling of a term on the screen when the two sound alike:
/// "диктишн контроллер" → DictationController, "ScreenContextRider" → ScreenContextReader,
/// "ridme.md" → README.md.
///
/// A run of one to six words matches an identifier or a file name when their `SoundKey`s are
/// close, and when it passes the rules that keep ordinary speech as it is:
///
/// - the run has at least as many words or camelCase parts as the term has parts, so a term is
///   never matched from one plain word: "контроллер" and "проект" stay Russian;
/// - the keys differ by a tenth of the term's key at most, by a fifth when a mark said aloud or
///   written by Whisper backs the match up ("ridme.md"). A key under ten sounds allows one slip
///   of voicing or a vowel, no more;
/// - the first sound agrees, and a word at either end that the match does not need stays out;
/// - a function word ("и", "в", "the") is let in only where the term has a part that sounds the
///   same, and the rest of the run is long: "из лоадинг" is `isLoading`, "из кода" is not `isCode`;
/// - in English text, runs of plain English words are prose and stay: "the language model";
///   inside Russian speech, a run of Latin words needs every word capitalised, the way Whisper
///   writes the parts of a name ("Prompt Builder");
/// - two or more capitalised Cyrillic words are a person's name, not a term;
/// - "точка", "слэш", "андерскор" and their English words may stand between parts when the term
///   has that mark.
///
/// A handle matches only after "собака" or "at", or when Whisper wrote the @ itself. A Latin name
/// replaces one capitalised Latin word that sounds the same and is spelled nearly the same
/// ("Kovalsky" → Kovalskyi).
public struct ScreenTermMatcher: Sendable {
    public let terms: [String]
    private let candidates: [Candidate]
    private let names: [Candidate]
    private let handles: [Candidate]

    /// Sounds a key needs before it may be matched; fewer when a spoken mark or a dot in the
    /// heard word backs the match up.
    static let minimumKey = 6
    static let minimumKeyWithMark = 4
    static let minimumNameKey = 5
    /// Keys shorter than this allow half a point of difference at most: one vowel or voicing slip.
    static let shortKey = 10
    static let shortKeyAllowance = 0.5
    /// Share of the term's key that may differ.
    static let tolerance = 0.1
    static let toleranceWithMark = 0.2
    static let nameSpelling = 0.75
    static let maximumSpan = 6

    struct Candidate: Sendable {
        let term: String
        let key: [UInt8]
        let parts: Int
        /// Keys of the term's parts, for the function words a run may hold: `is` of isLoading.
        let partKeys: Set<[UInt8]>
        let marks: Set<Character>
    }

    public init(terms: [String]) {
        self.terms = terms
        var candidates: [Candidate] = []
        var names: [Candidate] = []
        var handles: [Candidate] = []
        for term in terms {
            let body = term.hasPrefix("@") ? String(term.dropFirst()) : term
            let parts = SoundKey.parts(of: body)
            let key = SoundKey.key(body)
            guard !key.isEmpty else { continue }
            let candidate = Candidate(
                term: term,
                key: key,
                parts: parts.count,
                partKeys: Set(parts.map { SoundKey.key($0.text) }),
                marks: Set(body.filter { ".-_/".contains($0) })
            )
            switch ScreenTerms.kind(of: term) {
            case .handle: handles.append(candidate)
            case .name: names.append(candidate)
            case .identifier, .file: if parts.count >= 2 { candidates.append(candidate) }
            }
        }
        self.candidates = candidates
        self.names = names
        self.handles = handles
    }

    public var isEmpty: Bool { candidates.isEmpty && names.isEmpty && handles.isEmpty }

    // MARK: Words

    struct Word {
        let raw: String
        let core: String
        let key: [UInt8]
        /// camelCase parts, hyphen halves and words: "фич-юзер" is two, "useAufSession" three.
        let segments: Int
        let latin: Bool
        let cyrillic: Bool
        let capitalized: Bool
        let stop: Bool
        /// "точка" → ".", "слэш" → "/".
        let mark: Character?
        /// "собака", "at": an @ said aloud.
        let at: Bool
        /// A dot, underscore or slash inside the word: Whisper wrote it as code.
        let joined: Bool
        let endsClean: Bool
        let startsClean: Bool

        init(_ raw: String) {
            self.raw = raw
            core = Self.core(of: raw)
            let lower = core.lowercased().replacingOccurrences(of: "ё", with: "е")
            mark = ScreenTermMatcher.markWords[lower]
            at = ScreenTermMatcher.atWords.contains(lower)
            stop = ScreenTermMatcher.stopWords.contains(lower)
            let parts = SoundKey.parts(of: core)
            segments = parts.count
            key = mark == nil ? SoundKey.key(core) : []
            latin = !parts.isEmpty && parts.allSatisfy(\.latin)
            cyrillic = parts.contains { !$0.latin }
            capitalized = core.first?.isUppercase == true
            joined = core.contains { "._/".contains($0) }
            endsClean = raw.last.map { !",.;:!?…)»\"”".contains($0) } ?? true
            startsClean = raw.first.map { !"(«\"“".contains($0) } ?? true
        }

        /// The word without the punctuation around it; an @ in front stays.
        static func core(of word: String) -> String {
            let start = word.firstIndex { $0.isLetter || $0.isNumber || $0 == "@" || $0 == "_" || $0 == "$" } ?? word.endIndex
            let end = word.lastIndex { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }.map { word.index(after: $0) } ?? start
            return start < end ? String(word[start..<end]) : ""
        }

        /// One Latin token Whisper wrote as code: humps, an underscore, a dot, a slash or a digit.
        /// "ScreenContextRider", "project-therms-service.swift". "built-in" is prose.
        var isCodeToken: Bool {
            latin && segments >= 2 && (joined || core.contains(where: \.isNumber) || core.range(of: "[a-z][A-Z]", options: .regularExpression) != nil)
        }
    }

    // MARK: Applying

    public func apply(to text: String) -> String {
        guard !isEmpty else { return text }
        let raw = Words.split(text)
        guard !raw.isEmpty else { return text }
        let words = raw.map(Word.init)
        // Russian speech carries English terms, often several in a sentence; English speech has
        // no Russian words at all.
        let english = words.filter(\.cyrillic).count * 3 < words.filter(\.latin).count
        var output: [String] = []
        output.reserveCapacity(words.count)
        var i = 0
        while i < words.count {
            if let (term, length) = handle(at: i, in: words) ?? name(at: i, in: words) ?? identifier(at: i, in: words, english: english) {
                output.append(Self.leading(words[i].raw) + term + Self.trailing(words[i + length - 1].raw))
                i += length
            } else {
                output.append(words[i].raw)
                i += 1
            }
        }
        return output.joined(separator: " ")
    }

    struct Match {
        let term: String
        let length: Int
        let distance: Double
        var spokenMark = false

        func isBetter(than other: Match) -> Bool {
            if spokenMark != other.spokenMark { return spokenMark }
            if abs(distance - other.distance) > 0.01 { return distance < other.distance }
            return length > other.length
        }
    }

    /// The best identifier or file term for a run starting at `start`.
    private func identifier(at start: Int, in words: [Word], english: Bool) -> (String, Int)? {
        guard !candidates.isEmpty, let best = bestRun(from: start, in: words, english: english) else { return nil }
        // A first word the match does not need belongs to the sentence: "дай DictationController".
        if best.length > 1, words[start].mark == nil,
           let shorter = bestRun(from: start + 1, in: words, english: english, maximumLength: best.length - 1),
           shorter.term == best.term, shorter.distance <= best.distance {
            return nil
        }
        return (best.term, best.length)
    }

    private func bestRun(from start: Int, in words: [Word], english: Bool, maximumLength: Int = maximumSpan) -> Match? {
        guard start < words.count, words[start].mark == nil, !words[start].key.isEmpty else { return nil }
        var key: [UInt8] = []
        var segments = 0
        var stops: [[UInt8]] = []
        /// Sounds of the words that are not function words: "из кода" has four, too few to be
        /// anything but Russian.
        var content = 0
        /// Marks said aloud, and marks inside the heard words: "ridme.md".
        var marks = Set<Character>()
        var innerMarks = Set<Character>()
        var best: Match?
        let limit = min(maximumLength, words.count - start)
        for length in 1...limit {
            let word = words[start + length - 1]
            if length > 1 {
                let previous = words[start + length - 2]
                guard previous.endsClean, word.startsClean else { break }
            }
            if let mark = word.mark {
                marks.insert(mark)
                continue
            }
            if word.key.isEmpty { break }
            SoundKey.append(word.key, to: &key)
            segments += word.segments
            if word.stop { stops.append(word.key) } else { content += word.key.count }
            innerMarks.formUnion(word.core.filter { "._/".contains($0) })
            guard key.count >= Self.minimumKeyWithMark else { continue }
            if !stops.isEmpty, content < Self.minimumKey { continue }
            let spoken = words[start..<start + length].filter { $0.mark == nil }
            // "Иван Петров" is a person, whatever is on the screen.
            if spoken.count > 1, spoken.allSatisfy({ $0.cyrillic && $0.capitalized }) { continue }
            // English prose: "the language model" is not LanguageModel, "built-in" is not builtIn.
            if english, spoken.allSatisfy(\.latin), !(spoken.count == 1 && spoken[spoken.startIndex].isCodeToken) { continue }
            // Inside Russian speech Whisper writes a name's parts capitalised, "Prompt Builder";
            // "language model" and «Copy last dictation» are English words.
            if spoken.count > 1, spoken.allSatisfy(\.latin), !spoken.allSatisfy(\.capitalized) { continue }
            for candidate in candidates {
                // A mark said aloud or written by Whisper, where the term has one too.
                let backed = !marks.isEmpty || !innerMarks.isDisjoint(with: candidate.marks)
                guard key.count >= (backed ? Self.minimumKeyWithMark : Self.minimumKey),
                      segments >= candidate.parts, marks.isSubset(of: candidate.marks),
                      stops.allSatisfy(candidate.partKeys.contains),
                      key[0] == candidate.key[0] || SoundKey.isNear(key[0], candidate.key[0])
                else { continue }
                var allowed = Double(candidate.key.count) * (backed ? Self.toleranceWithMark : Self.tolerance)
                if candidate.key.count < Self.shortKey { allowed = min(allowed, Self.shortKeyAllowance) }
                guard Double(abs(key.count - candidate.key.count)) * 0.1 <= allowed else { continue }
                let distance = SoundKey.distance(key, candidate.key, limit: allowed)
                guard distance <= allowed else { continue }
                // A run with a spoken mark wins: "… точка свифт" is the file, not its stem. Then the
                // closest; then the longer.
                let match = Match(term: candidate.term, length: length, distance: distance, spokenMark: !marks.isEmpty)
                if best.map({ match.isBetter(than: $0) }) ?? true { best = match }
            }
        }
        return best
    }

    /// "Kovalsky" → Kovalskyi: one capitalised Latin word that sounds the same as a name and is
    /// spelled nearly the same. "Russian" and "Reason" sound alike to the key, but are far apart
    /// in letters.
    private func name(at start: Int, in words: [Word]) -> (String, Int)? {
        let word = words[start]
        guard !names.isEmpty, word.latin, word.capitalized, word.segments == 1, word.key.count >= Self.minimumNameKey,
              !ScreenTerms.isCommonWord(word.core.lowercased())
        else { return nil }
        for candidate in names where candidate.term != word.core
            && SoundKey.distance(word.key, candidate.key, limit: 0.2) <= 0.2
            && EditLearning.similarity(word.core, candidate.term) >= Self.nameSpelling {
            return (candidate.term, 1)
        }
        return nil
    }

    /// "собака влад ковальский" or "@vlad_kovalsky" → @vlad_kovalskyi.
    private func handle(at start: Int, in words: [Word]) -> (String, Int)? {
        guard !handles.isEmpty else { return nil }
        let word = words[start]
        if word.core.hasPrefix("@") {
            let key = SoundKey.key(String(word.core.dropFirst()))
            for candidate in handles where Self.close(key, candidate.key) {
                return (candidate.term, 1)
            }
            return nil
        }
        guard word.at, word.endsClean, start + 1 < words.count else { return nil }
        var key: [UInt8] = []
        var best: (term: String, length: Int)?
        for length in 1...min(3, words.count - start - 1) {
            let next = words[start + length]
            guard next.mark == nil, !next.key.isEmpty, !next.stop else { break }
            SoundKey.append(next.key, to: &key)
            if let candidate = handles.first(where: { Self.close(key, $0.key) }) {
                best = (candidate.term, length + 1)
            }
            guard next.endsClean else { break }
        }
        return best
    }

    private static func close(_ key: [UInt8], _ term: [UInt8]) -> Bool {
        guard key.count >= 3 else { return false }
        var allowed = Double(term.count) * toleranceWithMark
        if term.count < shortKey { allowed = min(allowed, shortKeyAllowance) }
        return SoundKey.distance(key, term, limit: allowed) <= allowed
    }

    // MARK: Edges

    private static func leading(_ word: String) -> String {
        String(word.prefix { !$0.isLetter && !$0.isNumber && $0 != "@" && $0 != "_" && $0 != "$" })
    }

    private static func trailing(_ word: String) -> String {
        String(word.reversed().prefix { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "$" }.reversed())
    }

    // MARK: Word lists

    /// Marks said between the parts of a name.
    static let markWords: [String: Character] = [
        "точка": ".", "дот": ".", "dot": ".",
        "слэш": "/", "слеш": "/", "slash": "/",
        "андерскор": "_", "underscore": "_",
        "дефис": "-", "тире": "-", "dash": "-", "hyphen": "-",
    ]

    static let atWords: Set<String> = ["собака", "at", "эт"]

    /// Russian and English function words. A run with one is ordinary speech, unless the term has
    /// a part that sounds the same.
    static let stopWords: Set<String> = Set(DeveloperVocabulary.latinStopWords).union([
        "и", "а", "но", "или", "либо", "в", "во", "на", "с", "со", "к", "ко", "по", "за", "из", "у", "о", "об", "обо",
        "от", "до", "для", "при", "про", "над", "под", "без", "через", "не", "ни", "да", "нет", "что", "чтобы", "как",
        "это", "этот", "эта", "эти", "то", "тот", "та", "те", "же", "ли", "бы", "вот", "уже", "еще", "тоже", "так",
        "там", "тут", "где", "когда", "если", "он", "она", "оно", "они", "я", "ты", "мы", "вы", "его", "ее", "их",
        "мне", "меня", "тебе", "тебя", "нам", "вам", "им", "ему", "ей", "мой", "моя", "мое", "мои", "твой", "наш",
        "ваш", "свой", "все", "весь", "вся", "очень", "только", "потом", "сейчас", "ну", "типа", "короче", "вообще",
        "просто", "может", "надо", "нужно", "можно", "есть", "был", "была", "было", "были", "будет",
    ])
}
