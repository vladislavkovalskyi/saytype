import Foundation

/// Everything the user can change. Persisted as one JSON document, so adding a
/// field only needs a default here.
public struct AppSettings: Codable, Equatable, Sendable {
    public enum RecordKey: String, Codable, CaseIterable, Sendable {
        case fn
        case rightOption
        case rightCommand
    }

    public enum OverlayStyle: String, Codable, CaseIterable, Sendable {
        case island
        case pill
    }

    public enum Glass: String, Codable, CaseIterable, Sendable {
        case dark
        case light
    }

    public enum OutputMode: String, Codable, CaseIterable, Sendable {
        /// Paste into the focused field, then restore the clipboard.
        case paste
        /// Keep the text as a draggable card in the overlay.
        case card
        /// Put the text on the clipboard only.
        case clipboard
    }

    public enum PunctuationStyle: String, Codable, CaseIterable, Sendable {
        /// Sentences, paragraphs after pauses and lists.
        case full
        /// Commas only, the way people text: "го завтра, я поздно".
        case commas
        /// No punctuation at all.
        case none
    }

    public enum LetterCase: String, Codable, CaseIterable, Sendable {
        /// Capital letters where Whisper puts them.
        case asSpoken
        /// Everything lowercase except terms like useEffect, API or GitHub.
        case lowercase
    }

    public enum FillerMode: String, Codable, CaseIterable, Sendable {
        /// Keep every word.
        case keep
        /// Remove hesitation sounds only: эээ, ммм.
        case hesitations
        /// Also remove ну, типа, короче, как бы.
        case all
    }

    public var onboardingCompleted = false

    public var recordKey = RecordKey.fn
    public var doubleTapHandsFree = true
    public var sounds = true

    public var overlayStyle = OverlayStyle.island
    public var glass = Glass.dark

    public var outputMode = OutputMode.paste
    /// Bundle identifiers of apps that get Return after a paste.
    public var autoEnterApps: [String] = ["com.apple.Terminal", "com.googlecode.iterm2"]

    public var language = SpeechLanguage.systemDefault
    public var punctuationStyle = PunctuationStyle.full
    public var letterCase = LetterCase.asSpoken
    public var smartStructure = true
    public var smartStructureMinWords = 40
    public var fillerMode = FillerMode.hesitations
    public var latinTerms = true
    /// The user's own entries. The built-in dictionary lives in `BuiltInDictionary`.
    public var dictionary: [DictionaryEntry] = []
    /// Hundreds of developer, AI and design terms shipped with the app.
    public var builtInDictionary = true
    /// Words and phrases removed from every dictation, e.g. "короче", "literally".
    public var wordFilters: [String] = []
    /// Masks swear words as "б***".
    public var censorProfanity = false
    public var dropTrailingPeriodInShortPhrases = false

    /// Core Audio UID of the chosen microphone; `nil` follows the system default.
    public var microphoneUID: String?
    public var whisperModel = "large-v3-v20240930_turbo_632MB"
    public var systemEngineFallback = true
    public var historyRetentionDays = 30

    public init() {}

    public init(from decoder: any Decoder) throws {
        // Decode field by field so an older or partial document keeps its values
        // and new fields fall back to defaults.
        let defaults = AppSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? defaults.onboardingCompleted
        recordKey = try c.decodeIfPresent(RecordKey.self, forKey: .recordKey) ?? defaults.recordKey
        doubleTapHandsFree = try c.decodeIfPresent(Bool.self, forKey: .doubleTapHandsFree) ?? defaults.doubleTapHandsFree
        sounds = try c.decodeIfPresent(Bool.self, forKey: .sounds) ?? defaults.sounds
        overlayStyle = try c.decodeIfPresent(OverlayStyle.self, forKey: .overlayStyle) ?? defaults.overlayStyle
        glass = try c.decodeIfPresent(Glass.self, forKey: .glass) ?? defaults.glass
        outputMode = try c.decodeIfPresent(OutputMode.self, forKey: .outputMode) ?? defaults.outputMode
        autoEnterApps = try c.decodeIfPresent([String].self, forKey: .autoEnterApps) ?? defaults.autoEnterApps
        language = try c.decodeIfPresent(SpeechLanguage.self, forKey: .language) ?? defaults.language
        // Before 0.1.3 punctuation was a single on/off switch.
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        let legacyStyle = try legacy.decodeIfPresent(Bool.self, forKey: .punctuation).map { $0 ? PunctuationStyle.full : .none }
        punctuationStyle = try c.decodeIfPresent(PunctuationStyle.self, forKey: .punctuationStyle) ?? legacyStyle ?? defaults.punctuationStyle
        letterCase = try c.decodeIfPresent(LetterCase.self, forKey: .letterCase) ?? defaults.letterCase
        smartStructure = try c.decodeIfPresent(Bool.self, forKey: .smartStructure) ?? defaults.smartStructure
        smartStructureMinWords = try c.decodeIfPresent(Int.self, forKey: .smartStructureMinWords) ?? defaults.smartStructureMinWords
        fillerMode = try c.decodeIfPresent(FillerMode.self, forKey: .fillerMode) ?? defaults.fillerMode
        latinTerms = try c.decodeIfPresent(Bool.self, forKey: .latinTerms) ?? defaults.latinTerms
        dictionary = try c.decodeIfPresent([DictionaryEntry].self, forKey: .dictionary) ?? defaults.dictionary
        builtInDictionary = try c.decodeIfPresent(Bool.self, forKey: .builtInDictionary) ?? defaults.builtInDictionary
        wordFilters = try c.decodeIfPresent([String].self, forKey: .wordFilters) ?? defaults.wordFilters
        censorProfanity = try c.decodeIfPresent(Bool.self, forKey: .censorProfanity) ?? defaults.censorProfanity
        dropTrailingPeriodInShortPhrases = try c.decodeIfPresent(Bool.self, forKey: .dropTrailingPeriodInShortPhrases) ?? defaults.dropTrailingPeriodInShortPhrases
        microphoneUID = try c.decodeIfPresent(String.self, forKey: .microphoneUID)
        whisperModel = try c.decodeIfPresent(String.self, forKey: .whisperModel) ?? defaults.whisperModel
        systemEngineFallback = try c.decodeIfPresent(Bool.self, forKey: .systemEngineFallback) ?? defaults.systemEngineFallback
        historyRetentionDays = try c.decodeIfPresent(Int.self, forKey: .historyRetentionDays) ?? defaults.historyRetentionDays
    }

    private enum LegacyKeys: String, CodingKey {
        case punctuation
    }

    /// Lowercase with commas only: how people text in messengers.
    public var isChatStyle: Bool {
        get { letterCase == .lowercase && punctuationStyle == .commas }
        set {
            letterCase = newValue ? .lowercase : .asSpoken
            punctuationStyle = newValue ? .commas : .full
        }
    }
}
