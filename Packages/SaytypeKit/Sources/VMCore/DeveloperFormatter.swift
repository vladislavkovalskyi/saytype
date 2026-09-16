import Foundation
import Synchronization

/// Spoken code for developer modes: casing ("кэмел кейс юзер дата" → userData), paths
/// ("src слэш app точка tsx" → src/app.tsx) and symbols ("стрелка" → =>).
///
/// Every rule needs code on both sides of the spoken word, so ordinary speech ("моя собака",
/// "с точки зрения", "они не равно распределены") passes through unchanged.
public enum DeveloperFormatter {
    public static func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let (tokens, tail) = DevToken.split(text)
        // Most dictations have no spoken code at all: one set lookup per word and out.
        guard tokens.contains(where: { heads.contains($0.key) || ($0.key.contains("-") && heads.contains($0.key.replacingOccurrences(of: "-", with: ""))) }) else {
            return text
        }
        var result = Casing.apply(tokens)
        result = Joiners.apply(result)
        result = Operators.apply(result)
        return DevToken.join(result) + tail
    }

    /// Builds the word tables ahead of the first dictation; they take about 15 ms once.
    public static func prepare() {
        _ = heads
        _ = DeveloperVocabulary.words
        _ = BuiltInDictionary.lookup
        _ = Backticks.builtInNames
        _ = Backticks.builtInIdentifiers
    }

    /// First words of every rule.
    static let heads: Set<String> = Set(Casing.triggers.keys)
        .union(Joiners.words)
        .union(Operators.phrases.keys)
}

// MARK: Tokens

/// A word with the whitespace before it and its punctuation split off.
struct DevToken {
    var space: String
    /// Punctuation before the first letter or digit.
    var lead: String
    /// From the first to the last letter or digit.
    var core: String
    /// Punctuation after the last letter or digit.
    var trail: String
    /// `core` lowercased, ё and э as е.
    let key: String

    init(space: String, lead: String = "", core: String, trail: String = "") {
        self.space = space
        self.lead = lead
        self.core = core
        self.trail = trail
        key = DeveloperText.normalize(core)
    }

    init(space: String, word: Substring) {
        guard let first = word.firstIndex(where: { $0.isLetter || $0.isNumber }),
              let last = word.lastIndex(where: { $0.isLetter || $0.isNumber }) else {
            self.init(space: space, lead: String(word), core: "")
            return
        }
        let end = word.index(after: last)
        self.init(space: space, lead: String(word[..<first]), core: String(word[first..<end]), trail: String(word[end...]))
    }

    var isBare: Bool { lead.isEmpty && trail.isEmpty }

    static func split(_ text: String) -> ([DevToken], tail: String) {
        var tokens: [DevToken] = []
        var space = ""
        var wordStart: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            if c.isWhitespace {
                if let start = wordStart {
                    tokens.append(DevToken(space: space, word: text[start..<index]))
                    space = ""
                    wordStart = nil
                }
                space.append(c)
            } else if wordStart == nil {
                wordStart = index
            }
            index = text.index(after: index)
        }
        if let start = wordStart {
            tokens.append(DevToken(space: space, word: text[start...]))
            space = ""
        }
        return (tokens, space)
    }

    static func join(_ tokens: [DevToken]) -> String {
        var out = ""
        for token in tokens {
            out += token.space
            out += token.lead
            out += token.core
            out += token.trail
        }
        return out
    }
}

extension DeveloperText {
    /// ASCII letters, digits and the marks paths and identifiers are made of.
    static func isPathish(_ text: String) -> Bool {
        var hasAlphanumeric = false
        for byte in text.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: hasAlphanumeric = true
            case UInt8(ascii: "_"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "/"), UInt8(ascii: "@"), UInt8(ascii: "~"), UInt8(ascii: ":"): continue
            default: return false
            }
        }
        return hasAlphanumeric
    }

    /// ASCII letters and digits, optionally joined by _ or -.
    static func isIdentifierWord(_ text: String) -> Bool {
        var previousWasJoin = true
        for byte in text.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: previousWasJoin = false
            case UInt8(ascii: "_"), UInt8(ascii: "-"):
                if previousWasJoin { return false }
                previousWasJoin = true
            default: return false
            }
        }
        return !previousWasJoin
    }

    static func isASCII(_ text: String) -> Bool {
        text.utf8.allSatisfy { $0 < 0x80 }
    }
}

// MARK: Casing

/// "кэмел кейс юзер дата" → userData, "константа макс ретраи" → MAX_RETRIES.
enum Casing {
    enum Style {
        case camel, pascal, snake, kebab, constant
    }

    struct Trigger {
        let words: [String]
        let style: Style
    }

    /// Most words an identifier takes after a trigger.
    static let maxWords = 6

    /// First word → triggers starting with it, longest first.
    static let triggers: [String: [Trigger]] = {
        // Whisper mixes scripts ("camel кейс") and glues words ("кэмелкейс", "camel-case").
        let names: [(Style, [String])] = [
            (.camel, ["кэмел", "камел", "кэмл", "кэмал", "camel"]),
            (.pascal, ["паскаль", "паскал", "паскэль", "pascal"]),
            (.snake, ["снейк", "снек", "snake"]),
            (.kebab, ["кебаб", "kebab"]),
            (.constant, ["констант", "constant", "капс снейк", "скриминг снейк", "screaming snake", "upper snake"]),
        ]
        var spoken: [(String, Style)] = [("константа", .constant), ("капс снейк", .constant)]
        for (style, variants) in names {
            for name in variants {
                for caseWord in ["кейс", "кейз", "case"] {
                    spoken.append((name + " " + caseWord, style))
                    if !name.contains(" ") { spoken.append((name + caseWord, style)) }
                }
            }
        }
        var map: [String: [Trigger]] = [:]
        for (phrase, style) in spoken {
            let words = phrase.split(separator: " ").map { DeveloperText.normalize(String($0)) }
            map[words[0], default: []].append(Trigger(words: words, style: style))
        }
        return map.mapValues { $0.sorted { $0.words.count > $1.words.count } }
    }()

    static func apply(_ tokens: [DevToken]) -> [DevToken] {
        var out: [DevToken] = []
        out.reserveCapacity(tokens.count)
        var i = 0
        while i < tokens.count {
            if let (trigger, length) = trigger(at: i, in: tokens),
               let (token, end) = identifier(from: i + length, in: tokens, trigger: trigger, start: tokens[i]) {
                out.append(token)
                i = end
                continue
            }
            out.append(tokens[i])
            i += 1
        }
        return out
    }

    private static func trigger(at i: Int, in tokens: [DevToken]) -> (Trigger, Int)? {
        let head = tokens[i].key.replacingOccurrences(of: "-", with: "")
        guard let candidates = triggers[head] else { return nil }
        for trigger in candidates {
            let count = trigger.words.count
            guard i + count <= tokens.count else { continue }
            var matches = true
            for k in 0..<count {
                let token = tokens[i + k]
                let key = count == 1 ? token.key.replacingOccurrences(of: "-", with: "") : token.key
                guard key == trigger.words[k], k == 0 || token.lead.isEmpty else {
                    matches = false
                    break
                }
                // "кэмел кейс, юзер дата" still counts; "кэмел кейс. Юзер" does not.
                if k < count - 1 ? !token.trail.isEmpty : !["", ",", ":"].contains(token.trail) {
                    matches = false
                    break
                }
            }
            if matches { return (trigger, count) }
        }
        return nil
    }

    /// The identifier spoken after a trigger and the index after its last word.
    private static func identifier(from first: Int, in tokens: [DevToken], trigger: Trigger, start: DevToken) -> (DevToken, Int)? {
        let latinTrigger = DeveloperText.isASCII(start.core)
        var parts: [String] = []
        var pending: [String] = []
        var words = 0
        var end = first
        var trail = ""
        var j = first
        while j < tokens.count, words < maxWords {
            let token = tokens[j]
            guard token.lead.isEmpty, let piece = Piece(token) else { break }
            if piece.isConnector {
                guard !parts.isEmpty || !pending.isEmpty || piece.canLead else { break }
                let next = j + 1 < tokens.count ? tokens[j + 1] : nil
                let lastWord = !token.trail.isEmpty || next == nil || next?.lead.isEmpty == false
                if lastWord || next.flatMap(Piece.init) == nil {
                    // An English word can end the name: createdAt, sortBy. In English speech a
                    // connector before prose ("user data in the store") is prose; a Russian one ("из дома") always is.
                    guard !parts.isEmpty, lastWord || !latinTrigger,
                          DeveloperText.isASCII(token.core) || (lastWord && !DeveloperVocabulary.russianConnectors.contains(token.key)) else { break }
                    parts += pending + piece.parts
                    pending = []
                    j += 1
                    end = j
                    trail = token.trail
                    break
                }
                pending += piece.parts
                words += 1
                j += 1
                continue
            }
            parts += pending + piece.parts
            pending = []
            words += 1
            j += 1
            end = j
            if !token.trail.isEmpty {
                trail = token.trail
                break
            }
        }
        // After "camel case" in English speech a single word is more likely prose.
        guard !parts.isEmpty, !latinTrigger || parts.count >= 2 else { return nil }
        return (DevToken(space: start.space, lead: start.lead, core: format(parts, trigger.style), trail: trail), end)
    }

    static func format(_ parts: [String], _ style: Style) -> String {
        switch style {
        case .camel: parts.enumerated().map { $0.offset == 0 ? $0.element.lowercased() : DeveloperText.capitalized($0.element) }.joined()
        case .pascal: parts.map(DeveloperText.capitalized).joined()
        case .snake: parts.map { $0.lowercased() }.joined(separator: "_")
        case .kebab: parts.map { $0.lowercased() }.joined(separator: "-")
        case .constant: parts.map { $0.uppercased() }.joined(separator: "_")
        }
    }

    /// One spoken word of an identifier as lowercase parts.
    private struct Piece {
        let parts: [String]
        let isConnector: Bool
        let canLead: Bool

        init?(_ token: DevToken) {
            let key = token.key
            guard !key.isEmpty else { return nil }
            if DeveloperText.isASCII(token.core) {
                guard DeveloperText.isIdentifierWord(token.core) else { return nil }
                if DeveloperVocabulary.latinConnectors.contains(key) {
                    self.init(parts: [key], isConnector: true, canLead: DeveloperVocabulary.leadingConnectors.contains(key))
                    return
                }
                guard !DeveloperVocabulary.latinStopWords.contains(key) else { return nil }
                self.init(parts: DeveloperText.parts(of: token.core), isConnector: false, canLead: false)
                return
            }
            if let connector = DeveloperVocabulary.connectors[key] {
                self.init(parts: [connector], isConnector: true, canLead: DeveloperVocabulary.leadingConnectors.contains(key))
                return
            }
            guard let parts = Self.translit(key) ?? Self.builtIn(token.core) else { return nil }
            self.init(parts: parts, isConnector: false, canLead: false)
        }

        private init(parts: [String], isConnector: Bool, canLead: Bool) {
            self.parts = parts
            self.isConnector = isConnector
            self.canLead = canLead
        }

        /// "юзер" → [user]; "юзер-дата" → [user, data] only when every half is known.
        private static func translit(_ key: String) -> [String]? {
            if let word = DeveloperVocabulary.words[key] { return [word.english] }
            guard key.contains("-") else { return nil }
            var parts: [String] = []
            for half in key.split(separator: "-") {
                guard let word = DeveloperVocabulary.words[String(half)] else { return nil }
                parts.append(word.english)
            }
            return parts
        }

        /// Names from the built-in dictionary: "супабейс" → Supabase → [supabase].
        private static func builtIn(_ core: String) -> [String]? {
            let key = core.lowercased().replacingOccurrences(of: "ё", with: "е").replacingOccurrences(of: "-", with: " ")
            guard let written = BuiltInDictionary.lookup[key], DeveloperText.isASCII(written) else { return nil }
            let parts = DeveloperText.parts(of: written)
            return parts.isEmpty ? nil : parts
        }
    }
}

// MARK: Paths

/// "src слэш components слэш header точка tsx" → src/components/header.tsx,
/// "vlad собака gmail точка com" → vlad@gmail.com, "андерскор апп" → _app.
enum Joiners {
    enum Kind: Equatable {
        case slash
        /// `spokenRussian` is "точка": two Latin words around it are code. English "dot" is not that sure.
        case dot(spokenRussian: Bool)
        case underscore
        case at
    }

    static let words: Set<String> = ["слеш", "slash", "точка", "dot", "андерскор", "underscore", "нижнее", "собака"]

    static let extensions: Set<String> = [
        "ts", "tsx", "js", "jsx", "mjs", "cjs", "json", "md", "mdx", "swift", "py", "go", "rs", "kt", "java", "rb", "php",
        "vue", "svelte", "html", "css", "scss", "sass", "less", "yml", "yaml", "toml", "xml", "csv", "txt", "sh", "zsh",
        "sql", "prisma", "graphql", "gql", "lock", "log", "png", "jpg", "jpeg", "svg", "gif", "webp", "ico", "pdf", "plist",
        "xcstrings", "strings", "c", "h", "cpp", "hpp", "cs", "m", "mm", "dart", "lua", "ipynb", "env",
        "com", "ru", "io", "dev", "org", "net", "app", "ai",
    ]

    /// Extensions as Whisper writes them in Cyrillic, normalized.
    static let spokenExtensions: [String: String] = Dictionary(uniqueKeysWithValues: [
        "джейсон": "json", "джсон": "json", "тс": "ts", "тсх": "tsx", "джс": "js", "жс": "js", "ямл": "yaml", "ямль": "yaml",
        "мд": "md", "свифт": "swift", "пай": "py", "ру": "ru", "ком": "com", "хтмл": "html", "цсс": "css", "энв": "env",
    ].map { (DeveloperText.normalize($0.key), $0.value) })

    /// Files and folders that start with a dot: "точка env" → .env.
    static let dotfiles: [String: String] = Dictionary(uniqueKeysWithValues: [
        "env": "env", "gitignore": "gitignore", "eslintrc": "eslintrc", "prettierrc": "prettierrc", "npmrc": "npmrc",
        "nvmrc": "nvmrc", "dockerignore": "dockerignore", "github": "github", "vscode": "vscode", "zshrc": "zshrc",
        "bashrc": "bashrc", "editorconfig": "editorconfig", "cursor": "cursor", "claude": "claude",
        "энв": "env", "гитигнор": "gitignore",
    ].map { (DeveloperText.normalize($0.key), $0.value) })

    struct Component {
        let text: String
        let latin: Bool
        let ambiguous: Bool
        var dotted: Bool { text.contains(".") || text.contains("/") || text.contains("@") }
    }

    static func component(_ token: DevToken) -> Component? {
        guard !token.core.isEmpty else { return nil }
        if DeveloperText.isPathish(token.core) {
            guard !DeveloperVocabulary.latinStopWords.contains(token.key) else { return nil }
            return Component(text: token.core, latin: true, ambiguous: false)
        }
        if let word = DeveloperVocabulary.words[token.key] {
            return Component(text: word.english, latin: false, ambiguous: word.ambiguous)
        }
        return nil
    }

    static func apply(_ tokens: [DevToken]) -> [DevToken] {
        var out: [DevToken] = []
        out.reserveCapacity(tokens.count)
        var i = 0
        while i < tokens.count {
            guard let (kind, length) = joiner(at: i, in: tokens) else {
                out.append(tokens[i])
                i += 1
                continue
            }
            var count = 1
            var next = i + length
            // "андерскор андерскор инит" → __init
            while kind == .underscore, next < tokens.count, let (more, moreLength) = joiner(at: next, in: tokens), more == .underscore {
                count += 1
                next += moreLength
            }
            let left = out.last.flatMap { $0.trail.isEmpty && !$0.core.isEmpty ? $0 : nil }
            let right = next < tokens.count && tokens[next].lead.isEmpty ? tokens[next] : nil
            if case .dot = kind, let left, let right, out.count >= 2, let file = builtInFileName(out[out.count - 2], left, right) {
                out.removeLast(2)
                out.append(file)
                i = next + 1
                continue
            }
            if let merge = merge(kind, count: count, left: left, space: tokens[i].space, right: right) {
                if merge.usesLeft { out.removeLast() }
                out.append(merge.token)
                i = next + (merge.usesRight ? 1 : 0)
            } else {
                out.append(contentsOf: tokens[i..<next])
                i = next
            }
        }
        return out
    }

    private static func joiner(at i: Int, in tokens: [DevToken]) -> (Kind, Int)? {
        let token = tokens[i]
        guard token.isBare else { return nil }
        switch token.key {
        case "слеш", "slash": return (.slash, 1)
        case "точка": return (.dot(spokenRussian: true), 1)
        case "dot": return (.dot(spokenRussian: false), 1)
        case "андерскор", "underscore": return (.underscore, 1)
        case "собака": return (.at, 1)
        case "нижнее":
            guard i + 1 < tokens.count, tokens[i + 1].isBare, tokens[i + 1].key == "подчеркивание" else { return nil }
            return (.underscore, 2)
        default: return nil
        }
    }

    private struct Merge {
        let token: DevToken
        let usesLeft: Bool
        let usesRight: Bool
    }

    private static func merge(_ kind: Kind, count: Int, left: DevToken?, space: String, right: DevToken?) -> Merge? {
        let l = left.flatMap(component)
        let r = right.flatMap(component)

        func joined(_ symbol: String, _ rightText: String, leftText: String? = nil) -> Merge? {
            guard let left, let leftText = leftText ?? l?.text, let right else { return nil }
            return Merge(token: DevToken(space: left.space, lead: left.lead, core: leftText + symbol + rightText, trail: right.trail), usesLeft: true, usesRight: true)
        }

        func prefixed(_ text: String) -> Merge? {
            guard let right else { return nil }
            return Merge(token: DevToken(space: space, core: text, trail: right.trail), usesLeft: false, usesRight: true)
        }

        switch kind {
        case .slash:
            guard let r else { return nil }
            // The import alias: "из собака слэш components" → from @/components.
            if left?.key == "собака", !r.ambiguous {
                return joined("/", r.text, leftText: "@")
            }
            // A Russian noun before a Latin path names it: "роут слэш api" → роут /api.
            if let l, l.latin || !r.latin {
                // "текст слэш код" is prose: one side has to be clearly code.
                guard !(l.ambiguous && r.ambiguous) else { return nil }
                return joined("/", r.text)
            }
            return r.ambiguous ? nil : prefixed("/" + r.text)

        case .dot(let spokenRussian):
            if let l, !l.ambiguous, let right, let ext = extensionName(right) {
                return joined(".", ext)
            }
            if let l, let r, l.latin, l.dotted || (spokenRussian && r.latin) {
                return joined(".", r.text)
            }
            if l == nil || l?.ambiguous == true, let right, let name = dotfileName(right) {
                return prefixed("." + name)
            }
            return nil

        case .underscore:
            let symbol = String(repeating: "_", count: count)
            switch (l, r) {
            case let (_?, r?): return joined(symbol, r.text)
            case let (nil, r?): return prefixed(symbol + r.text)
            case let (l?, nil):
                // Only the end of a dunder name: "__init" + "андерскор андерскор".
                guard let left, l.text.hasPrefix("_") else { return nil }
                return Merge(token: DevToken(space: left.space, lead: left.lead, core: l.text + symbol), usesLeft: true, usesRight: false)
            default: return nil
            }

        case .at:
            guard let l, l.latin, let r, r.latin else { return nil }
            return joined("@", r.text)
        }
    }

    /// A two-word file name from the built-in dictionary: "тс конфиг точка джейсон" → tsconfig.json.
    private static func builtInFileName(_ first: DevToken, _ second: DevToken, _ right: DevToken) -> DevToken? {
        guard first.trail.isEmpty, second.lead.isEmpty, !first.core.isEmpty, !DeveloperText.isASCII(second.core),
              let ext = extensionName(right) else { return nil }
        let key = (first.core + " " + second.core).lowercased().replacingOccurrences(of: "ё", with: "е")
        guard let written = BuiltInDictionary.lookup[key], written.hasSuffix("." + ext) else { return nil }
        return DevToken(space: first.space, lead: first.lead, core: written, trail: right.trail)
    }

    private static func extensionName(_ token: DevToken) -> String? {
        if DeveloperText.isASCII(token.core) { return extensions.contains(token.key) ? token.key : nil }
        return spokenExtensions[token.key]
    }

    private static func dotfileName(_ token: DevToken) -> String? {
        dotfiles[token.key]
    }
}

// MARK: Symbols

/// "x не равно null" → x != null, "три точки пропс" → ...props. Symbols appear only between
/// code-like operands: Latin identifiers, numbers or brackets.
enum Operators {
    enum Form {
        /// Between two operands.
        case infix
        /// Glued to the operand after it.
        case prefix
    }

    struct Phrase {
        let words: [String]
        let symbol: String
        let form: Form
    }

    static let phrases: [String: [Phrase]] = {
        let list: [(String, String, Form)] = [
            ("строго не равно", "!==", .infix), ("не равно", "!=", .infix),
            ("строго равно", "===", .infix), ("тройное равно", "===", .infix), ("двойное равно", "==", .infix),
            ("больше или равно", ">=", .infix), ("меньше или равно", "<=", .infix),
            ("тонкая стрелка", "->", .infix), ("жирная стрелка", "=>", .infix), ("стрелка", "=>", .infix),
            ("три точки", "...", .prefix), ("спред", "...", .prefix),
            ("not equal to", "!=", .infix), ("not equals", "!=", .infix), ("not equal", "!=", .infix),
            ("strictly equals", "===", .infix), ("triple equals", "===", .infix), ("double equals", "==", .infix),
            ("greater than or equal to", ">=", .infix), ("less than or equal to", "<=", .infix),
            ("fat arrow", "=>", .infix), ("thin arrow", "->", .infix), ("arrow", "=>", .infix),
        ]
        var map: [String: [Phrase]] = [:]
        for (text, symbol, form) in list {
            let words = text.split(separator: " ").map { DeveloperText.normalize(String($0)) }
            map[words[0], default: []].append(Phrase(words: words, symbol: symbol, form: form))
        }
        return map.mapValues { $0.sorted { $0.words.count > $1.words.count } }
    }()

    /// "arrow keys", "arrow function": the English word names the thing, not the symbol.
    static let arrowNouns: Set<String> = ["function", "functions", "key", "keys", "icon", "icons", "button", "buttons", "up", "down", "left", "right"]

    static func apply(_ tokens: [DevToken]) -> [DevToken] {
        var out: [DevToken] = []
        out.reserveCapacity(tokens.count)
        var i = 0
        while i < tokens.count {
            if let candidates = phrases[tokens[i].key], let (phrase, next) = match(candidates, at: i, in: tokens) {
                switch phrase.form {
                case .infix:
                    let english = DeveloperText.isASCII(phrase.words[0])
                    if let left = out.last, isOperand(left, before: true, english: english), next < tokens.count,
                       isOperand(tokens[next], before: false, english: english),
                       !(phrase.words == ["arrow"] && arrowNouns.contains(tokens[next].key)) {
                        out.append(DevToken(space: tokens[i].space, core: phrase.symbol))
                        i = next
                        continue
                    }
                case .prefix:
                    if next < tokens.count, tokens[next].lead.isEmpty, let operand = spreadOperand(tokens[next]) {
                        out.append(DevToken(space: tokens[i].space, core: "..." + operand, trail: tokens[next].trail))
                        i = next + 1
                        continue
                    }
                }
            }
            out.append(tokens[i])
            i += 1
        }
        return out
    }

    private static func match(_ candidates: [Phrase], at i: Int, in tokens: [DevToken]) -> (Phrase, Int)? {
        for phrase in candidates where i + phrase.words.count <= tokens.count {
            let matches = phrase.words.indices.allSatisfy { k in
                tokens[i + k].isBare && tokens[i + k].key == phrase.words[k]
            }
            if matches { return (phrase, i + phrase.words.count) }
        }
        return nil
    }

    private static let closing: Set<Character> = ["(", ")", "]", "}", "\"", "'", "`"]
    private static let opening: Set<Character> = ["(", "[", "{", "\"", "'", "`", "!", "-"]
    private static let brackets: Set<Character> = ["(", ")", "[", "]", "{", "}"]

    /// A Latin identifier, a number or brackets, with nothing but brackets or quotes towards the symbol.
    /// Next to an English phrase English function words ("an arrow") are not operands; in Russian
    /// speech a Latin "a" is a variable.
    static func isOperand(_ token: DevToken, before: Bool, english: Bool) -> Bool {
        if token.core.isEmpty {
            return !token.lead.isEmpty && token.lead.allSatisfy { brackets.contains($0) }
        }
        let edge = before ? token.trail : token.lead
        guard edge.allSatisfy({ (before ? closing : opening).contains($0) }) else { return false }
        return DeveloperText.isPathish(token.core) && !(english && DeveloperVocabulary.latinStopWords.contains(token.key))
    }

    private static func spreadOperand(_ token: DevToken) -> String? {
        guard let component = Joiners.component(token), !component.ambiguous else { return nil }
        return component.text
    }
}

// MARK: Backticks

/// Markdown code spans for developer modes: "поправь useEffect" → "поправь `useEffect`".
///
/// Wraps identifiers, paths and file names; leaves names (React, GitHub, Next.js), URLs,
/// e-mail addresses and text already in backticks or fenced blocks alone.
public enum Backticks {
    /// - Parameter terms: the user's and project spellings; identifier-like ones are wrapped too.
    public static func wrap(_ text: String, terms: [String] = []) -> String {
        guard !text.isEmpty, text.utf8.contains(where: { ($0 | 0x20) >= 0x61 && ($0 | 0x20) <= 0x7A }) else { return text }
        let identifiers = extraIdentifiers(terms)
        var output = ""
        output.reserveCapacity(text.utf8.count + 32)
        var inFence = false
        var firstLine = true
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if !firstLine { output += "\n" }
            firstLine = false
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                output += line
                continue
            }
            if inFence {
                output += line
                continue
            }
            var inSpan = false
            var wordStart: Substring.Index?
            var index = line.startIndex
            while index <= line.endIndex {
                let isEnd = index == line.endIndex
                if isEnd || line[index] == " " || line[index] == "\t" {
                    if let start = wordStart {
                        let word = line[start..<index]
                        let ticks = word.utf8.reduce(0) { $0 + ($1 == UInt8(ascii: "`") ? 1 : 0) }
                        if ticks > 0 {
                            output += word
                            if ticks % 2 == 1 { inSpan.toggle() }
                        } else if inSpan {
                            output += word
                        } else {
                            output += wrapped(word, identifiers: identifiers)
                        }
                        wordStart = nil
                    }
                    if isEnd { break }
                    output.append(line[index])
                } else if wordStart == nil {
                    wordStart = index
                }
                index = line.index(after: index)
            }
        }
        return output
    }

    private static let leading: Set<Character> = ["«", "\"", "'", "(", "[", "{", "“", "„"]
    private static let trailing: Set<Character> = [".", ",", ";", ":", "!", "?", "…", "»", "\"", "'", ")", "]", "}", "”"]

    static func wrapped(_ word: Substring, identifiers: Set<String>) -> String {
        guard word.utf8.contains(where: { ($0 | 0x20) >= 0x61 && ($0 | 0x20) <= 0x7A }) else { return String(word) }
        var core = word[...]
        while let first = core.first, leading.contains(first) { core = core.dropFirst() }
        var trailEnd = core.endIndex
        while trailEnd > core.startIndex, trailing.contains(core[core.index(before: trailEnd)]) {
            trailEnd = core.index(before: trailEnd)
        }
        // A call keeps its parentheses: "useEffect()." → `useEffect()`.
        var coreText = core[..<trailEnd]
        while coreText.filter({ $0 == "(" }).count > coreText.filter({ $0 == ")" }).count, trailEnd < core.endIndex, core[trailEnd] == ")" {
            trailEnd = core.index(after: trailEnd)
            coreText = core[..<trailEnd]
        }
        let body = String(coreText)
        guard !body.isEmpty, DeveloperText.isASCII(body), shouldWrap(body, identifiers: identifiers) else { return String(word) }
        return String(word[..<core.startIndex]) + "`" + body + "`" + String(core[trailEnd...])
    }

    static func shouldWrap(_ core: String, identifiers: Set<String>) -> Bool {
        if identifiers.contains(core) || builtInIdentifiers.contains(core) { return true }
        if builtInNames.contains(core) || isLink(core) || isDottedAcronym(core) { return false }
        return isCodeLike(core)
    }

    /// `Words.isCodeLike` without regular expressions, for an already trimmed ASCII word.
    static func isCodeLike(_ word: String) -> Bool {
        var bytes = Array(word.utf8)
        while bytes.count >= 2, bytes[bytes.count - 2] == UInt8(ascii: "("), bytes.last == UInt8(ascii: ")") { bytes.removeLast(2) }
        if bytes.last == UInt8(ascii: ".") { bytes.removeLast() }
        guard bytes.count > 1 else { return false }
        func isLower(_ b: UInt8) -> Bool { b >= 0x61 && b <= 0x7A }
        func isUpper(_ b: UInt8) -> Bool { b >= 0x41 && b <= 0x5A }
        func isAlnum(_ b: UInt8) -> Bool { isLower(b) || isUpper(b) || (b >= 0x30 && b <= 0x39) }
        let letters = bytes.filter { isLower($0) || isUpper($0) }.count
        guard letters > 0 else { return false }
        for i in 1..<bytes.count where isLower(bytes[i - 1]) && isUpper(bytes[i]) { return true }
        if letters >= 3, bytes.count >= 3 {
            for i in 1..<(bytes.count - 1) where [UInt8(ascii: "."), UInt8(ascii: "/"), UInt8(ascii: "_"), UInt8(ascii: ":")].contains(bytes[i]) {
                if isAlnum(bytes[i - 1]) && isAlnum(bytes[i + 1]) { return true }
            }
        }
        if (bytes[0] == UInt8(ascii: "/") || bytes[0] == UInt8(ascii: ".")) && bytes.count > 2 { return true }
        return false
    }

    /// "https://…", "www.…", "vlad@gmail.com", "example.com".
    static func isLink(_ core: String) -> Bool {
        if core.contains("://") || core.hasPrefix("www.") { return true }
        if core.contains("@"), core.contains(".") { return true }
        guard let dot = core.lastIndex(of: "."), !core.contains("/") else { return false }
        return ["com", "org", "net", "ru", "io", "co", "me", "ai"].contains(core[core.index(after: dot)...].lowercased())
    }

    /// "U.S.A", "e.g": letters with dots, not code.
    static func isDottedAcronym(_ core: String) -> Bool {
        let chars = Array(core)
        guard chars.count >= 3 else { return false }
        for (i, c) in chars.enumerated() {
            if i % 2 == 0 ? !c.isLetter : c != "." { return false }
        }
        return true
    }

    /// Built-in terms written like code: useEffect, localStorage, package.json, .env.
    static let builtInIdentifiers: Set<String> = Set(BuiltInDictionary.terms.map(\.written).filter { !$0.contains(" ") && isIdentifierTerm($0) })

    /// Every word of the built-in names: React, GitHub, Next.js, CI/CD, shadcn/ui.
    static let builtInNames: Set<String> = Set(BuiltInDictionary.terms.flatMap { $0.written.split(separator: " ").map(String.init) }.filter { !isIdentifierTerm($0) })

    static func isIdentifierTerm(_ term: String) -> Bool {
        guard term.count > 1, DeveloperText.isASCII(term), !term.contains(" ") else { return false }
        if term.hasPrefix("."), term.count > 2 { return true }
        if term.contains("_") { return true }
        let chars = Array(term)
        if let dot = term.lastIndex(of: "."), let first = chars.first, first.isLowercase,
           Joiners.extensions.contains(String(term[term.index(after: dot)...])) {
            return true
        }
        // useEffect, localStorage; not macOS, iPhone or jQuery.
        let prefix = chars.prefix { $0.isLowercase }.count
        guard prefix >= 2, prefix + 1 < chars.count else { return false }
        return chars[prefix].isUppercase && chars[prefix + 1].isLowercase
    }

    private static let cache = Mutex<(terms: [String], identifiers: Set<String>)>(([], []))

    /// Identifier-like user and project terms, remembered for the last list.
    static func extraIdentifiers(_ terms: [String]) -> Set<String> {
        guard !terms.isEmpty else { return [] }
        return cache.withLock { cached in
            if cached.terms == terms { return cached.identifiers }
            let identifiers = Set(terms.filter { term in
                guard !builtInNames.contains(term), DeveloperText.isASCII(term), !term.contains(" ") else { return false }
                return isIdentifierTerm(term) || isCodeLike(term) || isKebab(term)
            })
            cached = (terms, identifiers)
            return identifiers
        }
    }

    /// "use-auth", "user-profile-card".
    private static func isKebab(_ term: String) -> Bool {
        let parts = term.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            part.count >= 2 && part.allSatisfy { ($0.isLowercase && $0.isASCII) || $0.isASCII && $0.isNumber }
        }
    }
}
