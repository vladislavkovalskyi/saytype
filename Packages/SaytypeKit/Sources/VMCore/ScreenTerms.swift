import Foundation

/// Text read from the window in front when a dictation starts. It lives for that dictation only
/// and is never stored.
public struct ScreenText: Sendable, Equatable {
    /// The window title; in editors it names the file and the project.
    public var title: String
    /// The focused field: its visible part, or the text around the caret.
    public var focused: String
    /// The rest of the window's text.
    public var visible: [String]

    public init(title: String = "", focused: String = "", visible: [String] = []) {
        self.title = title
        self.focused = focused
        self.visible = visible
    }

    public var isEmpty: Bool {
        title.isEmpty && focused.isEmpty && visible.allSatisfy(\.isEmpty)
    }

    public var characterCount: Int {
        title.count + focused.count + visible.reduce(0) { $0 + $1.count }
    }
}

/// The rare words of a window's text a developer might dictate: identifiers, file names,
/// @handles and Latin names. Everyday words, URLs, e-mail addresses, hashes and terms the
/// built-in dictionary already spells are left out.
public enum ScreenTerms {
    public static let limit = 80
    static let minimumLength = 4
    static let maximumLength = 60
    static let minimumNameLength = 5

    public enum Kind: Int, Comparable, Sendable {
        case identifier, file, handle, name

        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }

        /// Names rank after everything else: they are the least sure.
        var tier: Int { self == .name ? 1 : 0 }
    }

    /// The terms of a window's text, best first. The focused field and the title count three
    /// times as much as the rest of the window; then how often a term occurs; then its length.
    public static func extract(from text: ScreenText, limit: Int = limit) -> [String] {
        var counter = Counter()
        counter.add(text.focused, weight: 3)
        counter.add(text.title, weight: 3)
        for piece in text.visible { counter.add(piece, weight: 1) }
        return counter.ranked(limit: limit)
    }

    /// The kind of an extracted term, from its shape.
    public static func kind(of term: String) -> Kind {
        if term.hasPrefix("@") { return .handle }
        if fileExtension(of: term) != nil { return .file }
        return DeveloperText.parts(of: term).count >= 2 ? .identifier : .name
    }

    // MARK: Counting

    struct Counter {
        struct Entry {
            var term: String
            var kind: Kind
            var score: Int
            var bestWeight: Int
            var order: Int
        }

        var entries: [String: Entry] = [:]
        var order = 0

        mutating func add(_ source: String, weight: Int) {
            guard !source.isEmpty else { return }
            for (term, kind) in ScreenTerms.candidates(in: source) {
                let key = TermCanonicalizer.squash(term)
                guard !key.isEmpty, !ScreenTerms.builtInKeys.contains(key) else { continue }
                if var entry = entries[key] {
                    entry.score += weight
                    // The spelling from the likeliest place wins: the focused field over a list.
                    if weight > entry.bestWeight {
                        entry.term = term
                        entry.kind = kind
                        entry.bestWeight = weight
                    }
                    entries[key] = entry
                } else {
                    entries[key] = Entry(term: term, kind: kind, score: weight, bestWeight: weight, order: order)
                    order += 1
                }
            }
        }

        func ranked(limit: Int) -> [String] {
            entries.values.sorted { a, b in
                if a.kind.tier != b.kind.tier { return a.kind.tier < b.kind.tier }
                if a.score != b.score { return a.score > b.score }
                if a.term.count != b.term.count { return a.term.count > b.term.count }
                return a.order < b.order
            }
            .prefix(limit)
            .map(\.term)
        }
    }

    // MARK: Candidates

    /// Every term in one piece of text, in order, with repeats.
    static func candidates(in source: String) -> [(String, Kind)] {
        let cleaned = strippingLinks(source)
        let ns = cleaned as NSString
        var result: [(String, Kind)] = []
        for match in token.matches(in: cleaned, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range)
            if raw.hasPrefix("@") {
                let name = raw.dropFirst()
                if isHandle(name) {
                    result.append((raw, .handle))
                    continue
                }
                // "@tanstack/react-query" is a package scope, not a person.
                result.append(contentsOf: pathTerms(String(name)))
                continue
            }
            // A capitalised word opening a line, a label or a sentence is a heading or a button,
            // not a name: "Refactor …", "Translation Available".
            let terms = pathTerms(raw)
            let midSentence = isMidSentence(ns, before: match.range.location)
            result.append(contentsOf: terms.filter { $0.1 != .name || midSentence })
        }
        return result
    }

    /// True when a word, not the start of the text or a line or a sentence end, comes before.
    static func isMidSentence(_ text: NSString, before location: Int) -> Bool {
        var i = location - 1
        while i >= 0, let scalar = UnicodeScalar(text.character(at: i)), scalar == " " || scalar == "\t" { i -= 1 }
        guard i >= 0, let scalar = UnicodeScalar(text.character(at: i)) else { return false }
        return CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) || scalar == ","
    }

    /// src/components/UserProfileCard.tsx → UserProfileCard.tsx, UserProfileCard (and `components`
    /// if it were an identifier).
    private static func pathTerms(_ token: String) -> [(String, Kind)] {
        var result: [(String, Kind)] = []
        for component in token.split(separator: "/").map(String.init) {
            if let ext = fileExtension(of: component) {
                let stem = String(component.dropLast(ext.count + 1))
                if stem.contains(where: \.isLetter), component.count <= maximumLength {
                    result.append((component, .file))
                }
                if isIdentifier(stem) { result.append((stem, .identifier)) }
                continue
            }
            // DictionaryRewriter.cached → the identifiers on either side of the dot.
            for piece in component.split(separator: ".").map(String.init) {
                if isIdentifier(piece) {
                    result.append((piece, .identifier))
                } else if isName(piece) {
                    result.append((piece, .name))
                }
            }
        }
        return result
    }

    /// The extension of a file name, when it is one people work with: `swift`, `tsx`, `md`.
    static func fileExtension(of name: String) -> String? {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        let ext = name[name.index(after: dot)...].lowercased()
        guard !ext.isEmpty, fileExtensions.contains(ext) else { return nil }
        return String(name[name.index(after: dot)...])
    }

    static func isIdentifier(_ word: String) -> Bool {
        guard word.count >= minimumLength, word.count <= maximumLength,
              let first = word.first, first.isLetter || first == "_" || first == "$",
              word.allSatisfy({ DeveloperText.isASCIILetter($0) || DeveloperText.isASCIIDigit($0) || $0 == "_" || $0 == "-" || $0 == "$" })
        else { return false }
        let parts = DeveloperText.parts(of: word)
        guard parts.count >= 2, parts.count <= 6 else { return false }
        // Ids and hashes: agent-a7a06b5a4025, 3f9c2e1b.
        guard !parts.contains(where: looksGenerated) else { return false }
        if word.contains("-"), !word.contains("_"), !word.contains(where: \.isUppercase) {
            // Prose with hyphens: built-in, follow-up, drag-and-drop, e-mail. An underscore is
            // always code: mark_as_paid.
            guard parts.allSatisfy({ $0.filter(\.isLetter).count >= 2 && !DeveloperVocabulary.latinStopWords.contains($0) }) else { return false }
        }
        return true
    }

    /// Capitalised, letters only, not an everyday English word: Kovalskyi, Grafana. Taken only
    /// in the middle of a sentence.
    static func isName(_ word: String) -> Bool {
        guard word.count >= minimumNameLength, word.count <= 30,
              let first = word.first, first.isUppercase, DeveloperText.isASCIILetter(first),
              word.dropFirst().allSatisfy({ DeveloperText.isASCIILetter($0) && $0.isLowercase })
        else { return false }
        return !isCommonWord(word.lowercased())
    }

    static func isHandle(_ name: Substring) -> Bool {
        name.count >= 3 && name.count <= 32
            && name.allSatisfy { DeveloperText.isASCIILetter($0) || DeveloperText.isASCIIDigit($0) || $0 == "_" }
            && name.contains(where: \.isLetter)
    }

    private static func looksGenerated(_ part: String) -> Bool {
        let digits = part.filter(\.isNumber).count
        return digits >= 3 || (part.count >= 8 && digits >= 2)
    }

    static func isCommonWord(_ word: String) -> Bool {
        if commonWords.contains(word) { return true }
        // Plurals and verb forms of the words above: Issues, Actions, Settings, Opened.
        for suffix in ["es", "s", "ed", "ing", "er"] where word.hasSuffix(suffix) {
            let stem = String(word.dropLast(suffix.count))
            if commonWords.contains(stem) || commonWords.contains(stem + "e") { return true }
        }
        return false
    }

    // MARK: Tables

    /// Built-in and prompt terms are spelled already; the screen adds nothing to them.
    static let builtInKeys: Set<String> = Set(
        (BuiltInDictionary.terms.map(\.written) + PromptBuilder.builtInTerms).map(TermCanonicalizer.squash)
    )

    /// Extensions of source, config, document and image files. Web domains (`com`, `io`) are
    /// left out: `github.com` is not a file.
    static let fileExtensions: Set<String> = Joiners.extensions.subtracting(["com", "ru", "io", "dev", "org", "net", "app", "ai"])

    /// Words, identifiers with their marks, file names with dots and paths, @handles.
    private static let token = try! NSRegularExpression(pattern: #"@?[A-Za-z_$][A-Za-z0-9_$]*(?:[-./][A-Za-z0-9_$]+)*"#)

    private static let links = try! NSRegularExpression(
        pattern: #"(?i)\b(?:[a-z][a-z0-9+.-]*://|www\.)\S+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
    )

    /// URLs and e-mail addresses are blanked before the words are read.
    private static func strippingLinks(_ text: String) -> String {
        guard text.contains("://") || text.contains("www.") || text.contains("@") else { return text }
        return links.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: " ")
    }

    /// Everyday English, and the words app interfaces are made of. Only capitalised single
    /// words are checked against it; identifiers never are.
    static let commonWords: Set<String> = {
        var words = Set(DeveloperVocabulary.latinStopWords)
        for word in DeveloperVocabulary.words.values { words.insert(word.english) }
        for word in commonWordList.split(whereSeparator: { $0 == " " || $0 == "\n" }) { words.insert(String(word)) }
        return words
    }()

    private static let commonWordList = """
    about above account action activity actual add address after again against agent album alert all allow already
    always amount another answer anyone anything apply april archive area around article ask assign attach audio
    august author auto available away back background badge balance bar base basic before begin below best between
    beyond bill black block blue board body bold book border both bottom box branch break bring browse browser build
    business button buy cache calendar call camera cancel card care case catalog category center change channel chart
    chat check child choose clear click client clip clock close cloud code collapse collection color column comment
    commit common community company compare complete compose computer confirm connect contact content continue control
    copy correct count country course cover create credit current custom customer daily dark dashboard data date day
    debug december default delete deliver describe description design desktop detail details develop device dialog
    different direct directory disable discard discover display document done down download draft drive drop during
    each early edit editor email empty enable end enter entire error even event every example exit expand explore
    explorer export extension extensions external family favorite feature february feed field file files filter
    final find finish first follow following font food footer force form format forward free friday friend from front
    full function gallery game general get give global good great green group guest guide hand have header health
    hello help here hidden hide high history hold home hour house however image import inbox include index info input
    insert inside install into invite issue item items january join journal july june just keep key keyboard kind
    know label language large last later layer layout learn leave left less level library light like limit line link
    list little live load local location lock login logout long look lower main make manage manager many map march
    mark market match maximum may media medium member members memory menu merge message method middle minimum minute
    mode monday money month more most move music name navigate need network never new news next night none normal
    note notes notice november number object october office offline often okay online only open option options order
    other outline output over overview owner page panel paper parent part password paste path pause people person
    phone photo picture pin place plan play please plugin point policy popular post power present preview previous
    price print privacy private problem problems process product profile program project public publish pull push
    quick quit radio random range read ready real recent record redo refresh region release reload remove rename
    reply report request required reset resource restore result resume return review right rule run safe same saturday
    save saved scale schedule screen script scroll search second section security select send september server session
    set setting settings setup share sheet shift short show side sidebar sign simple single site size skip small
    social some sort source space speed split stack standard star start state status step still stop storage store
    story style subject submit summary sunday support switch sync system tab table tag task team template terminal
    test text than thank thanks that theme there these thing things think this thread thursday time title today
    together toggle token tomorrow tool toolbar tools top total track trash trend tuesday type under undo unread
    until untitled update upload upper usage user users using value version video view visible voice wait want watch
    week wednesday welcome what when where which while white who whole why wide will window with within word work
    workspace world would write year yellow yesterday your zoom
    """
}
