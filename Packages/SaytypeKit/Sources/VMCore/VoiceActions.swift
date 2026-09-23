import Foundation

/// A spoken instruction over text the user already has: the text selected in the app in front,
/// or the text on the clipboard. The language model carries it out instead of the words being
/// typed: "переведи выделенное на испанский", "translate the clipboard text to English".
public struct VoiceAction: Equatable, Sendable {
    public enum Source: String, Codable, Equatable, Sendable {
        case selection
        case clipboard
    }

    /// How the words point at the source.
    public enum Reference: Equatable, Sendable {
        /// "выделенное", "буфер обмена", "the selected text", "clipboard".
        case named
        /// "это", "this", "этот текст": the selection, if there is one.
        case pointer
        /// No words for it: text was selected when recording started, and the words are a short
        /// instruction over text.
        case implied
    }

    /// What the model does.
    public enum Job: Equatable, Sendable {
        /// Translates into this language and does nothing else.
        case translate(AppSettings.SpeechLanguage)
        /// Translates, but no language was named; `VoiceActions.defaultTarget` picks one.
        case translateUnnamed
        /// Anything else: `instruction` goes to the model as it was said.
        case instruct
    }

    public var source: Source
    public var reference: Reference
    public var job: Job
    /// The words as they were said, without a trailing "отправь".
    public var instruction: String
    /// The dictation ended with "отправь" / "send it": Return after the paste.
    public var send: Bool

    public init(source: Source, reference: Reference, job: Job, instruction: String, send: Bool = false) {
        self.source = source
        self.reference = reference
        self.job = job
        self.instruction = instruction
        self.send = send
    }
}

/// Finds a voice action in what Whisper heard, before anything else touches the words.
///
/// Rules rather than a model: a missed action costs a repeat, a false one replaces somebody's
/// selection or eats a message, so the rules are narrow and every negative can be tested.
///
/// The utterance is lead-ins ("пожалуйста", "can you"), an optional source, an action verb, and
/// then slots: sources, a target language ("на испанский", "to Spanish"), fillers ("мне",
/// "please") and modifiers ("короче", "до двух предложений", "typos"). Words that fit no slot are
/// the residue.
///
/// - A named source ("выделенное", "буфер обмена", "clipboard") must come before any residue.
///   With a translate or text verb a short residue may follow ("и сделай вежливее"); with
///   "исправь" or "сделай" only modifiers may.
/// - A pointer ("это", "this", "этот текст") or no source at all allows translate verbs, text
///   verbs, "исправь" with a mistake word and "сделай" with a word about the text ("короче"),
///   and nothing but modifiers besides.
/// - A keyword used as an adjective for something else is not a source: "the selected tab",
///   "поправь буфер обмена в Paster" has "Paster" after it.
public enum VoiceActions {
    /// Longer utterances are dictations, not instructions.
    static let wordLimit = 24
    /// Most residue words a named source's instruction may have.
    static let residueLimit = 6

    /// - Parameters:
    ///   - transcript: the raw transcript, as Whisper wrote it.
    ///   - selectionAtStart: text was selected, by Accessibility, when recording started. Without
    ///     it an utterance that names no source is never an action.
    ///   - sendCommand: voice commands are on, so a trailing "отправь" is taken off and any other
    ///     command makes the utterance an ordinary dictation.
    public static func detect(_ transcript: String, selectionAtStart: Bool, sendCommand: Bool = true) -> VoiceAction? {
        var tokens = Token.split(transcript).filter { !hesitations.contains($0.key) }
        guard !tokens.isEmpty, tokens.count <= wordLimit else { return nil }

        var send = false
        var end = transcript.endIndex
        if sendCommand, let cut = trailingSend(tokens) {
            send = true
            end = tokens[cut].range.lowerBound
            tokens.removeSubrange(cut...)
        }
        let instruction = String(transcript[..<end]).trimmingCharacters(in: trailingMarks)
        if sendCommand, VoiceCommands.parse(instruction).contains(where: { if case .command = $0 { true } else { false } }) {
            return nil
        }
        guard let parse = Parse(tokens.map(\.key)), let (reference, job) = parse.decide(selectionAtStart: selectionAtStart) else { return nil }
        return VoiceAction(source: parse.source?.source ?? .selection, reference: reference, job: job, instruction: instruction, send: send)
    }

    /// The language a translation goes into when none was named: the translate everything
    /// language when the text is in another script ("переведи выделенное" over Russian text →
    /// English); otherwise the language of the spoken instruction when its script differs from
    /// the text's (over English text → Russian). `nil` leaves it to the model.
    public static func defaultTarget(for text: String, instruction: String, translateTarget: AppSettings.SpeechLanguage) -> AppSettings.SpeechLanguage? {
        guard let script = Script.of(text) else { return nil }
        if let target = Script.of(translateTarget), target != script { return translateTarget }
        let spoken: AppSettings.SpeechLanguage? = switch Script.of(instruction) {
        case .cyrillic: .russian
        case .latin: .english
        default: nil
        }
        if let spoken, Script.of(spoken) != script { return spoken }
        return nil
    }

    /// Index of the first token of a trailing "(и) отправь" or "(and) send (it)", when words come
    /// before it.
    static func trailingSend(_ tokens: [Token]) -> Int? {
        let keys = tokens.map(\.key)
        var cut: Int
        if let last = keys.last, last == "отправь" || last == "отправить" {
            cut = keys.count - 1
        } else if keys.suffix(2) == ["send", "it"] {
            cut = keys.count - 2
        } else if keys.suffix(2) == ["and", "send"] {
            cut = keys.count - 1
        } else {
            return nil
        }
        if cut > 0, keys[cut - 1] == "и" || keys[cut - 1] == "and" { cut -= 1 }
        return cut > 0 ? cut : nil
    }

    static let trailingMarks = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:—–-"))
}

// MARK: Words

extension VoiceActions {
    struct Token {
        /// Lowercase, ё as е.
        let key: String
        let range: Range<String.Index>

        /// Runs of letters and digits; an apostrophe between letters stays inside ("what's").
        static func split(_ text: String) -> [Token] {
            var tokens: [Token] = []
            var start: String.Index?
            var index = text.startIndex
            func close(at end: String.Index) {
                guard let first = start else { return }
                let key = text[first..<end].lowercased().replacingOccurrences(of: "ё", with: "е").replacingOccurrences(of: "’", with: "'")
                tokens.append(Token(key: key, range: first..<end))
                start = nil
            }
            while index < text.endIndex {
                let character = text[index]
                let next = text.index(after: index)
                if character.isLetter || character.isNumber {
                    if start == nil { start = index }
                } else if character == "'" || character == "’", start != nil, next < text.endIndex, text[next].isLetter {
                    // An apostrophe inside a word.
                } else {
                    close(at: index)
                }
                index = next
            }
            close(at: text.endIndex)
            return tokens
        }
    }

    static let hesitations: Set<String> = Cleanup.hesitations.union(["um", "uh", "uhm", "umm", "erm", "hmm", "ah", "eh"])

    /// Phrases that may open a request before the verb, longest first.
    static let leadIns: [[String]] = [
        ["пожалуйста"], ["плиз"], ["ну"], ["так"], ["слушай"], ["слушайте"], ["давай"], ["давайте"], ["а"], ["и"],
        ["или"], ["теперь"], ["окей"], ["ок"], ["хорошо"], ["эй"], ["можешь"], ["можете"], ["сможешь"],
        ["сможете"], ["ты", "можешь"], ["вы", "можете"], ["можешь", "ли", "ты"], ["можете", "ли", "вы"],
        ["не", "мог", "бы", "ты"], ["не", "могла", "бы", "ты"], ["не", "могли", "бы", "вы"], ["не", "мог", "бы"],
        ["не", "могла", "бы"], ["не", "могли", "бы"], ["мог", "бы", "ты"], ["могла", "бы", "ты"], ["будь", "добр"],
        ["будь", "добра"], ["будьте", "добры"], ["мне", "нужно"], ["мне", "надо"], ["нужно"], ["надо"],
        ["попробуй"], ["помоги"], ["помогите"], ["я", "хочу", "чтобы", "ты"], ["хочу", "чтобы", "ты"],
        ["please"], ["so"], ["now"], ["hey"], ["ok"], ["okay"], ["and"], ["or"], ["then"], ["well"], ["can", "you"],
        ["could", "you"], ["would", "you"], ["will", "you"], ["can", "u"], ["could", "u"], ["i", "need", "you", "to"],
        ["i", "want", "you", "to"], ["i'd", "like", "you", "to"], ["i", "would", "like", "you", "to"],
        ["let's"], ["lets"], ["let", "us"], ["go", "ahead", "and"], ["just"], ["kindly"], ["help", "me"],
    ].sorted { $0.count > $1.count }

    enum Verb {
        /// переведи, translate.
        case translate
        /// Verbs that only make sense for text: сократи, перефразируй, rephrase.
        case text
        /// исправь, fix: over a pointer or an implied selection only with a mistake word.
        case fix
        /// сделай, make: over a pointer or an implied selection only with a word about the text.
        case general
    }

    static let verbs: [String: Verb] = {
        var verbs: [String: Verb] = [:]
        func add(_ words: [String], _ verb: Verb) { for word in words { verbs[word] = verb } }
        add(["переведи", "переведите", "перевести", "переведешь", "переведете", "translate"], .translate)
        add([
            "сократи", "сократите", "сократить", "перепиши", "перепишите", "переписать", "перефразируй",
            "перефразируйте", "перефразировать", "переформулируй", "переформулируйте", "переформулировать",
            "отредактируй", "отредактируйте", "отредактировать", "упрости", "упростите", "упростить", "резюмируй",
            "резюмируйте", "резюмировать", "перескажи", "перескажите", "пересказать", "укороти", "укоротите",
            "укоротить", "shorten", "rewrite", "rephrase", "reword", "paraphrase", "summarize", "summarise",
            "simplify", "proofread", "condense",
        ], .text)
        add(["исправь", "исправьте", "исправить", "поправь", "поправьте", "поправить", "fix", "correct"], .fix)
        add([
            "сделай", "сделайте", "сделать", "преврати", "превратите", "превратить", "оформи", "оформите", "оформить",
            "разбей", "разбейте", "разбить", "улучши", "улучшите", "улучшить", "отформатируй", "отформатируйте",
            "отформатировать", "расширь", "расширьте", "расширить", "make", "turn", "convert", "improve", "format",
            "polish", "edit", "expand",
        ], .general)
        return verbs
    }()

    /// Words that follow a verb without changing the job: "переведи мне", "for me, please".
    static let fillers: Set<String> = [
        "мне", "нам", "для", "меня", "нас", "пожалуйста", "плиз", "ка", "весь", "всю", "все", "целиком",
        "полностью", "вот", "тут", "здесь", "быстро", "тоже", "еще", "раз", "язык", "языке", "языка", "please",
        "for", "me", "us", "the", "a", "an", "my", "our", "just", "whole", "entire", "all", "here", "quickly",
        "also", "again", "language", "спасибо", "thanks", "thank",
    ]

    /// Words of an edit instruction: how short, how formal, what to fix.
    static let modifiers: Set<String> = mistakes.union([
        "короче", "покороче", "проще", "попроще", "понятнее", "яснее", "формальнее", "официальнее", "вежливее",
        "мягче", "строже", "дружелюбнее", "грамотнее", "лучше", "живее", "красивее", "естественнее", "более",
        "менее", "формально", "официально", "вежливо", "кратко", "коротко", "просто", "понятно",
        "профессионально", "естественно", "формальный", "формальным", "официальный", "официальным", "вежливый",
        "вежливым", "короткий", "коротким", "краткий", "кратким", "простой", "простым", "понятный", "понятным",
        "дружелюбный", "дружелюбным", "нейтральный", "нейтральным", "деловой", "деловым", "деловом",
        "профессиональный", "профессиональным", "грамотным", "официальном", "формальном", "дружелюбном",
        "нейтральном", "стиле", "стиль", "тоне", "тон", "вдвое", "до", "в", "во", "на", "один", "одно", "одного",
        "одну", "одном", "два", "две", "двух", "три", "трех", "четыре", "четырех", "пять", "пяти", "треть",
        "половину", "раза", "предложение", "предложения", "предложений", "абзац", "абзаца", "абзацев", "абзацы",
        "строку", "строки", "строк", "слов", "слова", "пунктов", "пункта", "пункты", "список", "списком",
        "списка", "маркированный", "нумерованный", "тезисы", "тезисов", "и", "shorter", "simpler", "clearer",
        "more", "less", "formal", "formally", "informal", "polite", "politely", "concise", "concisely",
        "professional", "professionally", "friendly", "friendlier", "casual", "casually", "natural", "naturally",
        "better", "brief", "briefly", "short", "simple", "clear", "tone", "style", "neutral", "warmer", "warm",
        "tighter", "readable", "to", "into", "in", "one", "two", "three", "four", "five", "sentence", "sentences",
        "paragraph", "paragraphs", "line", "lines", "words", "word", "bullet", "bullets", "points", "list", "half",
        "third", "and",
    ])

    /// Modifiers that say nothing about the text on their own: "сделай это до пятницы" is not an
    /// edit, "сделай это короче" is.
    static let structuralModifiers: Set<String> = [
        "до", "в", "во", "на", "и", "более", "менее", "один", "одно", "одного", "одну", "одном", "два", "две", "двух",
        "три", "трех", "четыре", "четырех", "пять", "пяти", "раза", "вдвое", "треть", "половину", "to", "into", "in",
        "and", "more", "less", "one", "two", "three", "four", "five", "half", "third",
    ]

    /// What "исправь" and "fix" need to be about text over a pointer: "исправь ошибки", "fix the typos".
    static let mistakes: Set<String> = [
        "ошибки", "ошибку", "ошибок", "опечатки", "опечатку", "опечаток", "грамматику", "пунктуацию", "орфографию",
        "запятые", "typos", "typo", "mistakes", "mistake", "errors", "error", "grammar", "spelling", "punctuation",
    ]

    /// A residue with one of these is a sentence about something, not an instruction over text:
    /// "…так, чтобы выделенный текст подсвечивался", "…, он не подсвечивается".
    static let clauseWords: Set<String> = [
        "чтобы", "если", "когда", "который", "которая", "которое", "которые", "которого", "которой", "которую",
        "потому", "поскольку", "пока", "где", "куда", "он", "она", "оно", "они", "мы", "ты", "вы", "because",
        "if", "when", "which", "who", "whose", "while", "where", "unless", "although", "since", "he", "she",
        "they", "we", "you", "it", "its", "it's", "i",
    ]

    /// Nouns for a piece of text: "этот текст", "this paragraph".
    static let textNouns: Set<String> = [
        "текст", "текста", "тексте", "текстом", "фрагмент", "фрагмента", "фрагменте", "абзац", "абзаца", "абзаце",
        "предложение", "предложения", "кусок", "кусочек", "часть", "части", "строку", "строки", "сообщение",
        "письмо", "фразу", "фраза", "фразы", "слово", "слова", "text", "paragraph", "sentence", "sentences",
        "passage", "fragment", "part", "piece", "bit", "line", "lines", "message", "email", "letter", "phrase",
        "word", "words",
    ]

    static let pointerPronouns: Set<String> = ["это", "его", "ее", "их", "this", "it", "that"]
    static let pointerDeterminers: Set<String> = [
        "этот", "эту", "эти", "этого", "этом", "этой", "это", "данный", "данную", "данное", "данного", "данном",
        "this", "that", "these", "those", "the",
    ]

    /// Words that join a source keyword into one phrase: "текст из буфера обмена", "то, что я
    /// выделил", "текст, который я скопировал", "the text in my clipboard".
    static let leftGlue: Set<String> = [
        "в", "во", "из", "с", "со", "то", "что", "я", "весь", "всю", "все", "этот", "эту", "это", "эти", "данный",
        "текст", "текста", "тексте", "содержимое", "содержимого", "который", "которое", "которую", "которые", "the",
        "my", "this", "that",
        "what", "what's", "whats", "which", "i", "i've", "ive", "is", "in", "from", "on", "all", "of", "text",
        "have", "everything", "content", "contents",
    ]
    static let rightGlue: Set<String> = textNouns.union(["обмена", "content", "contents"])

    /// Prepositions that may open a target language.
    static let targetPrepositions: Set<String> = ["на", "по", "в", "to", "into", "in"]
    static let fromPrepositions: Set<String> = ["с", "со", "from"]

    static func sourceKeyword(_ key: String) -> VoiceAction.Source? {
        if key.hasPrefix("выделенн") || key.hasPrefix("выделени") || key.hasPrefix("выделил")
            || ["выделено", "выделен", "выделена", "selected", "selection", "highlighted"].contains(key) {
            return .selection
        }
        if key.hasPrefix("буфер") || key.hasPrefix("клипборд") || key.hasPrefix("скопированн") || key.hasPrefix("скопировал")
            || key.hasPrefix("clipboard") || ["скопировано", "copied", "pasteboard"].contains(key) {
            return .clipboard
        }
        return nil
    }
}

// MARK: Parse

extension VoiceActions {
    struct SourceSpan {
        let source: VoiceAction.Source
        let reference: VoiceAction.Reference
        let range: ClosedRange<Int>
    }

    /// One utterance cut into lead-ins, source, verb and slots.
    struct Parse {
        var verb: Verb
        var source: SourceSpan?
        var target: AppSettings.SpeechLanguage?
        /// Modifier words, in order.
        var modifiers: [String] = []
        /// Words that fit no slot.
        var residue: [String] = []
        /// The source came before any residue word, or before the verb.
        var sourceFirst = false
        /// "на карту", "to plain English": a translate verb pointing somewhere that is not a language.
        var strayTarget = false
        /// "с английского", "from Spanish": the language the text is in.
        var fromLanguage: AppSettings.SpeechLanguage?

        init?(_ keys: [String]) {
            let named = Self.namedSources(keys)
            guard Set(named.map(\.source)).count <= 1 else { return nil }

            var i = 0
            var leadIns = 0
            while leadIns < 4, let phrase = VoiceActions.leadIns.first(where: { i + $0.count <= keys.count && Array(keys[i..<i + $0.count]) == $0 }) {
                i += phrase.count
                leadIns += 1
            }
            guard i < keys.count else { return nil }

            // "выделенное переведи на английский", "это переведи".
            let before = named.first { $0.range.lowerBound == i } ?? Self.pointer(keys, at: i, named: named)
            if let span = before {
                var j = span.range.upperBound + 1
                while j < keys.count, VoiceActions.fillers.contains(keys[j]) { j += 1 }
                guard j < keys.count, VoiceActions.verbs[keys[j]] != nil else { return nil }
                i = j
            }

            guard let verb = VoiceActions.verbs[keys[i]] else { return nil }
            self.verb = verb
            source = before
            sourceFirst = before != nil

            var j = i + 1
            var sawResidue = false
            while j < keys.count {
                if let span = named.first(where: { $0.range.contains(j) }) {
                    if source == nil {
                        source = span
                        sourceFirst = !sawResidue
                    }
                    j = span.range.upperBound + 1
                    continue
                }
                if let (language, length) = Self.language(keys, at: j) {
                    // "с русского на английский": the first language is where the text comes from.
                    if VoiceActions.fromPrepositions.contains(keys[j]) {
                        fromLanguage = fromLanguage ?? language
                    } else {
                        target = target ?? language
                    }
                    j += length
                    continue
                }
                // "английский текст", "the Spanish text": the language the text is in.
                if let (language, length) = LanguageNames.match(keys, at: j), j + length < keys.count,
                   VoiceActions.textNouns.contains(keys[j + length]) {
                    fromLanguage = fromLanguage ?? language
                    j += length
                    continue
                }
                if source == nil, !sawResidue, let span = Self.pointer(keys, at: j, named: named) {
                    source = span
                    sourceFirst = true
                    j = span.range.upperBound + 1
                    continue
                }
                let key = keys[j]
                if verb == .translate, ["на", "to", "into"].contains(key) { strayTarget = true }
                if VoiceActions.fillers.contains(key) || key == "you" && j > 0 && keys[j - 1] == "thank" {
                    // Nothing to keep.
                } else if VoiceActions.modifiers.contains(key) || key.allSatisfy(\.isNumber) {
                    modifiers.append(key)
                } else {
                    residue.append(key)
                    sawResidue = true
                }
                j += 1
            }
        }

        /// The reference and the job, or `nil` when the words are a dictation after all.
        func decide(selectionAtStart: Bool) -> (VoiceAction.Reference, VoiceAction.Job)? {
            let reference: VoiceAction.Reference
            if let source {
                reference = source.reference
            } else {
                guard selectionAtStart else { return nil }
                reference = .implied
            }
            if reference == .named {
                guard sourceFirst else { return nil }
                switch verb {
                case .translate, .text:
                    guard residue.count <= VoiceActions.residueLimit, !residue.contains(where: VoiceActions.clauseWords.contains) else { return nil }
                case .fix, .general:
                    guard residue.isEmpty else { return nil }
                }
                return (reference, job(translatesPlainly: residue.isEmpty && modifiers.isEmpty))
            }
            // A pointer or nothing: the words must be an instruction over text and nothing else.
            guard residue.isEmpty, !(verb == .translate && strayTarget) else { return nil }
            switch verb {
            case .translate:
                // "переведи" alone over a selection is too little to go on; "переведи с английского" is not.
                if reference == .implied, target == nil, fromLanguage == nil { return nil }
                return (reference, job(translatesPlainly: modifiers.isEmpty))
            case .text:
                return (reference, .instruct)
            case .fix:
                guard modifiers.contains(where: VoiceActions.mistakes.contains) else { return nil }
                return (reference, .instruct)
            case .general:
                // "сделай это короче", "make it more formal"; not "сделай это до пятницы".
                guard modifiers.contains(where: { !VoiceActions.structuralModifiers.contains($0) && !$0.allSatisfy(\.isNumber) }) else { return nil }
                return (reference, .instruct)
            }
        }

        private func job(translatesPlainly: Bool) -> VoiceAction.Job {
            guard verb == .translate, translatesPlainly else { return .instruct }
            return target.map { .translate($0) } ?? .translateUnnamed
        }

        /// A word that belongs to the instruction's grammar rather than to a sentence about
        /// something: the word after a source keyword or a pointer must be one, or nothing.
        static func isSlot(_ keys: [String], at index: Int) -> Bool {
            guard index < keys.count else { return true }
            let key = keys[index]
            return VoiceActions.fillers.contains(key) || VoiceActions.modifiers.contains(key)
                || VoiceActions.verbs[key] != nil || VoiceActions.targetPrepositions.contains(key)
                || VoiceActions.fromPrepositions.contains(key) || VoiceActions.sourceKeyword(key) != nil
                || key.allSatisfy(\.isNumber) || ["отправь", "отправить", "send"].contains(key)
        }

        /// Every named source: a keyword and the words glued to it, used as a reference to text.
        /// "the selected tab" and "the clipboard restore" name something else.
        static func namedSources(_ keys: [String]) -> [SourceSpan] {
            var spans: [SourceSpan] = []
            var index = 0
            while index < keys.count {
                guard let source = VoiceActions.sourceKeyword(keys[index]) else {
                    index += 1
                    continue
                }
                var upper = index
                while upper + 1 < keys.count, upper - index < 3,
                      VoiceActions.rightGlue.contains(keys[upper + 1]) || VoiceActions.sourceKeyword(keys[upper + 1]) == source {
                    upper += 1
                }
                guard isSlot(keys, at: upper + 1) else {
                    index = upper + 1
                    continue
                }
                var lower = index
                let floor = (spans.last?.range.upperBound ?? -1) + 1
                while lower > floor, index - lower < 5, VoiceActions.leftGlue.contains(keys[lower - 1]) {
                    lower -= 1
                }
                spans.append(SourceSpan(source: source, reference: .named, range: lower...upper))
                index = upper + 1
            }
            return spans
        }

        /// "это", "this", "этот текст", "the text" at `index`. A pronoun followed by a word that is
        /// not a slot is a determiner: "fix this bug".
        static func pointer(_ keys: [String], at index: Int, named: [SourceSpan]) -> SourceSpan? {
            let key = keys[index]
            if VoiceActions.pointerDeterminers.contains(key), index + 1 < keys.count, VoiceActions.textNouns.contains(keys[index + 1]) {
                return SourceSpan(source: .selection, reference: .pointer, range: index...(index + 1))
            }
            guard key == "текст" || key == "text" || VoiceActions.pointerPronouns.contains(key), isSlot(keys, at: index + 1) else { return nil }
            return SourceSpan(source: .selection, reference: .pointer, range: index...index)
        }

        /// "на испанский", "на английском языке", "по-английски", "to Spanish", "into Norwegian
        /// Nynorsk", or "с русского" / "from Russian": the language and the number of words.
        static func language(_ keys: [String], at index: Int) -> (AppSettings.SpeechLanguage, Int)? {
            let preposition = keys[index]
            guard VoiceActions.targetPrepositions.contains(preposition) || VoiceActions.fromPrepositions.contains(preposition),
                  index + 1 < keys.count, let (language, length) = LanguageNames.match(keys, at: index + 1)
            else { return nil }
            var count = 1 + length
            if index + count < keys.count, ["язык", "языке", "языка", "language"].contains(keys[index + count]) { count += 1 }
            return (language, count)
        }
    }
}

// MARK: Languages

/// Names of Whisper's languages as people say them, in Russian and English.
enum LanguageNames {
    /// English names, some of two words ("norwegian nynorsk"), longest first.
    static let english: [(words: [String], language: AppSettings.SpeechLanguage)] = {
        var names: [(words: [String], language: AppSettings.SpeechLanguage)] = []
        let locale = Locale(identifier: "en")
        for code in AppSettings.SpeechLanguage.whisperCodes {
            guard let name = locale.localizedString(forLanguageCode: code) else { continue }
            names.append((name.lowercased().split(separator: " ").map(String.init), AppSettings.SpeechLanguage(rawValue: code)))
        }
        let aliases = ["mandarin": "zh", "farsi": "fa", "bengali": "bn", "maori": "mi", "filipino": "tl", "flemish": "nl"]
        for (alias, code) in aliases { names.append(([alias], AppSettings.SpeechLanguage(rawValue: code))) }
        return names.sorted { $0.words.count > $1.words.count }
    }()

    /// Russian names: an adjective's stem ("испанск") takes its case endings; other names
    /// ("иврит", "хинди") are matched whole or with a noun ending.
    static let russian: [(stem: String, adjective: Bool, language: AppSettings.SpeechLanguage)] = {
        var names: [(stem: String, adjective: Bool, language: AppSettings.SpeechLanguage)] = []
        let locale = Locale(identifier: "ru")
        var pairs: [(String, String)] = AppSettings.SpeechLanguage.whisperCodes.compactMap { code in
            locale.localizedString(forLanguageCode: code).map { ($0.lowercased().replacingOccurrences(of: "ё", with: "е"), code) }
        }
        pairs += [("голландский", "nl"), ("фарси", "fa"), ("бенгали", "bn"), ("филиппинский", "tl")]
        for (name, code) in pairs {
            let word = String(name.split(separator: " ").first ?? "")
            guard !word.isEmpty else { continue }
            if word.hasSuffix("ий") || word.hasSuffix("ый") || word.hasSuffix("ой") {
                names.append((String(word.dropLast(2)), true, AppSettings.SpeechLanguage(rawValue: code)))
            } else {
                names.append((word, false, AppSettings.SpeechLanguage(rawValue: code)))
            }
        }
        return names
    }()

    static let adjectiveEndings: Set<String> = ["ий", "ый", "ой", "ого", "ому", "им", "ым", "ом", "ая", "ую", "ие", "ые", "их", "ых", "ими", "и"]
    static let nounEndings: Set<String> = ["", "е", "а", "у", "ом", "ем"]

    /// The language named at `index`, and how many words its name took.
    static func match(_ keys: [String], at index: Int) -> (AppSettings.SpeechLanguage, Int)? {
        for (words, language) in english where index + words.count <= keys.count && Array(keys[index..<index + words.count]) == words {
            return (language, words.count)
        }
        let key = keys[index]
        for name in russian where key.hasPrefix(name.stem) {
            let ending = String(key.dropFirst(name.stem.count))
            if name.adjective ? adjectiveEndings.contains(ending) : nounEndings.contains(ending) {
                return (name.language, 1)
            }
        }
        return nil
    }
}

// MARK: Scripts

/// The alphabet a text or a language is written in, as far as picking a translation target goes.
enum Script: Equatable {
    case latin
    case cyrillic
    case other

    static let cyrillicLanguages: Set<String> = ["ru", "uk", "be", "bg", "sr", "mk", "kk", "tg", "tt", "ba", "mn"]
    static let otherLanguages: Set<String> = [
        "zh", "ko", "ja", "ar", "hi", "he", "el", "ta", "th", "ur", "ml", "te", "fa", "bn", "kn", "hy", "ne", "mr",
        "pa", "si", "km", "ka", "gu", "am", "yi", "lo", "sd", "ps", "my", "bo", "as", "sa", "yue",
    ]

    static func of(_ language: AppSettings.SpeechLanguage) -> Script? {
        guard let code = language.whisperCode else { return nil }
        if cyrillicLanguages.contains(code) { return .cyrillic }
        return otherLanguages.contains(code) ? .other : .latin
    }

    /// The script most of the letters are in; `nil` without letters.
    static func of(_ text: String) -> Script? {
        var latin = 0, cyrillic = 0, other = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F: latin += 1
            case 0x400...0x4FF: cyrillic += 1
            default: other += 1
            }
        }
        let most = max(latin, cyrillic, other)
        guard most > 0 else { return nil }
        return most == cyrillic ? .cyrillic : most == latin ? .latin : .other
    }
}

// MARK: Requests and records

extension RewriteRequest {
    /// A plain translation of text the user already has: the request translate everything uses.
    public static func translation(into target: AppSettings.SpeechLanguage) -> RewriteRequest {
        RewriteRequest(style: .none, translate: true, targetLanguage: englishName(of: target))
    }
}

extension DictationRecord {
    /// What a voice action worked on. The record's `text` is the model's result and its `raw` the
    /// spoken instruction.
    public struct Action: Codable, Equatable, Sendable {
        public var source: VoiceAction.Source
        /// Whisper code of the language a translation went into; `nil` for any other instruction.
        public var target: String?

        public init(source: VoiceAction.Source, target: String? = nil) {
            self.source = source
            self.target = target
        }
    }

    /// Words the user said: the text of a dictation, the instruction of a voice action.
    public var spokenWordCount: Int {
        action == nil ? wordCount : Words.split(raw).count
    }
}
