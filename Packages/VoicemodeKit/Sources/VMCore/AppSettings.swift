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

    public enum SpeechLanguage: String, Codable, CaseIterable, Sendable {
        case russian = "ru"
        case english = "en"
        case auto
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

    public var language = SpeechLanguage.russian
    public var punctuation = true
    public var smartStructure = true
    public var smartStructureMinWords = 40
    public var fillerMode = FillerMode.hesitations
    public var latinTerms = true
    public var dictionary: [DictionaryEntry] = DictionaryEntry.starter
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
        punctuation = try c.decodeIfPresent(Bool.self, forKey: .punctuation) ?? defaults.punctuation
        smartStructure = try c.decodeIfPresent(Bool.self, forKey: .smartStructure) ?? defaults.smartStructure
        smartStructureMinWords = try c.decodeIfPresent(Int.self, forKey: .smartStructureMinWords) ?? defaults.smartStructureMinWords
        fillerMode = try c.decodeIfPresent(FillerMode.self, forKey: .fillerMode) ?? defaults.fillerMode
        latinTerms = try c.decodeIfPresent(Bool.self, forKey: .latinTerms) ?? defaults.latinTerms
        dictionary = try c.decodeIfPresent([DictionaryEntry].self, forKey: .dictionary) ?? defaults.dictionary
        dropTrailingPeriodInShortPhrases = try c.decodeIfPresent(Bool.self, forKey: .dropTrailingPeriodInShortPhrases) ?? defaults.dropTrailingPeriodInShortPhrases
        microphoneUID = try c.decodeIfPresent(String.self, forKey: .microphoneUID)
        whisperModel = try c.decodeIfPresent(String.self, forKey: .whisperModel) ?? defaults.whisperModel
        systemEngineFallback = try c.decodeIfPresent(Bool.self, forKey: .systemEngineFallback) ?? defaults.systemEngineFallback
        historyRetentionDays = try c.decodeIfPresent(Int.self, forKey: .historyRetentionDays) ?? defaults.historyRetentionDays
    }
}
