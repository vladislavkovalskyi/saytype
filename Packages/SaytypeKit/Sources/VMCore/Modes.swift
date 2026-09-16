import Foundation

/// A set of text rules for one kind of writing: a chat message, a prompt for a coding agent,
/// a commit. Picked by the app that has focus, or by hand.
///
/// The standard mode has no rules of its own: it is the Text section. Every other mode
/// replaces the style fields below and keeps the rest (dictionary, filters, language).
public struct DictationMode: Codable, Equatable, Identifiable, Sendable {
    public enum Rewrite: String, Codable, CaseIterable, Sendable {
        /// No language model: the text stays as spoken.
        case none
        /// Goal, context, steps and constraints for a coding agent.
        case prompt
        /// A Conventional Commit message in English.
        case commit
        /// Removes repeats and self-corrections: "не X, а Y" → Y.
        case cleaner
        /// The user's own instruction in `instruction`.
        case custom
    }

    public var id: String
    /// Shown for custom modes; built-in modes are named by the app in the interface language.
    public var name: String
    /// Bundle identifiers of apps that switch to this mode.
    public var apps: [String]

    public var punctuationStyle: AppSettings.PunctuationStyle
    public var letterCase: AppSettings.LetterCase
    public var fillerMode: AppSettings.FillerMode
    public var smartStructure: Bool
    public var dropTrailingPeriod: Bool
    /// Spoken casing, paths and symbols: "кэмел кейс юзер дата" → userData.
    public var developer: Bool
    /// Wraps code-like words in backticks for Markdown: `useEffect`.
    public var backticks: Bool
    public var translateToEnglish: Bool
    public var rewrite: Rewrite
    /// Instruction for `Rewrite.custom`, e.g. "Сделай из этого баг-репорт".
    public var instruction: String
    /// Return after paste, in addition to the per-app list.
    public var pressReturn: Bool
    /// `nil` keeps the output mode from settings.
    public var outputMode: AppSettings.OutputMode?

    public init(
        id: String,
        name: String = "",
        apps: [String] = [],
        punctuationStyle: AppSettings.PunctuationStyle = .full,
        letterCase: AppSettings.LetterCase = .asSpoken,
        fillerMode: AppSettings.FillerMode = .hesitations,
        smartStructure: Bool = true,
        dropTrailingPeriod: Bool = false,
        developer: Bool = false,
        backticks: Bool = false,
        translateToEnglish: Bool = false,
        rewrite: Rewrite = .none,
        instruction: String = "",
        pressReturn: Bool = false,
        outputMode: AppSettings.OutputMode? = nil
    ) {
        self.id = id
        self.name = name
        self.apps = apps
        self.punctuationStyle = punctuationStyle
        self.letterCase = letterCase
        self.fillerMode = fillerMode
        self.smartStructure = smartStructure
        self.dropTrailingPeriod = dropTrailingPeriod
        self.developer = developer
        self.backticks = backticks
        self.translateToEnglish = translateToEnglish
        self.rewrite = rewrite
        self.instruction = instruction
        self.pressReturn = pressReturn
        self.outputMode = outputMode
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DictationMode(id: "")
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        apps = try c.decodeIfPresent([String].self, forKey: .apps) ?? []
        punctuationStyle = try c.decodeIfPresent(AppSettings.PunctuationStyle.self, forKey: .punctuationStyle) ?? defaults.punctuationStyle
        letterCase = try c.decodeIfPresent(AppSettings.LetterCase.self, forKey: .letterCase) ?? defaults.letterCase
        fillerMode = try c.decodeIfPresent(AppSettings.FillerMode.self, forKey: .fillerMode) ?? defaults.fillerMode
        smartStructure = try c.decodeIfPresent(Bool.self, forKey: .smartStructure) ?? defaults.smartStructure
        dropTrailingPeriod = try c.decodeIfPresent(Bool.self, forKey: .dropTrailingPeriod) ?? defaults.dropTrailingPeriod
        developer = try c.decodeIfPresent(Bool.self, forKey: .developer) ?? defaults.developer
        backticks = try c.decodeIfPresent(Bool.self, forKey: .backticks) ?? defaults.backticks
        translateToEnglish = try c.decodeIfPresent(Bool.self, forKey: .translateToEnglish) ?? defaults.translateToEnglish
        rewrite = try c.decodeIfPresent(Rewrite.self, forKey: .rewrite) ?? defaults.rewrite
        instruction = try c.decodeIfPresent(String.self, forKey: .instruction) ?? ""
        pressReturn = try c.decodeIfPresent(Bool.self, forKey: .pressReturn) ?? defaults.pressReturn
        outputMode = try c.decodeIfPresent(AppSettings.OutputMode.self, forKey: .outputMode)
    }

    public var isStandard: Bool { id == Self.standardID }
    public var isBuiltIn: Bool { Self.builtInIDs.contains(id) }
    /// Needs a language model: a rewrite, or a translation the model does better than Whisper.
    public var usesLanguageModel: Bool { rewrite != .none }

    public static let standardID = "standard"
    public static let messageID = "message"
    public static let promptID = "prompt"
    public static let commitID = "commit"
    public static let emailID = "email"
    static let builtInIDs: Set<String> = [standardID, messageID, promptID, commitID, emailID]

    /// Modes of a new install. Only the standard mode applies everywhere; the others
    /// switch on in their apps.
    public static let defaults: [DictationMode] = [
        DictationMode(id: standardID),
        DictationMode(
            id: messageID,
            apps: [
                "ru.keepcoder.Telegram", "com.tdesktop.Telegram", "net.whatsapp.WhatsApp", "desktop.WhatsApp",
                "com.apple.MobileSMS", "com.hnc.Discord", "com.facebook.archon", "com.viber.osx",
            ],
            punctuationStyle: .commas,
            letterCase: .lowercase,
            fillerMode: .all,
            smartStructure: false
        ),
        DictationMode(
            id: promptID,
            apps: [
                "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
                "com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode", "dev.zed.Zed", "com.exafunction.windsurf",
                "com.anthropic.claudefordesktop", "com.openai.chat", "com.openai.codex",
            ],
            fillerMode: .all,
            developer: true,
            backticks: true
        ),
        DictationMode(
            id: commitID,
            fillerMode: .all,
            smartStructure: false,
            dropTrailingPeriod: true,
            developer: true,
            translateToEnglish: true,
            rewrite: .commit
        ),
        DictationMode(
            id: emailID,
            apps: ["com.apple.mail", "com.readdle.SparkDesktop", "com.microsoft.Outlook", "com.superhuman.electron"],
            fillerMode: .all
        ),
    ]
}

extension AppSettings {
    /// The mode for a dictation into the app with this bundle identifier.
    public func mode(for bundleID: String?) -> DictationMode {
        if let fixedModeID, let fixed = modes.first(where: { $0.id == fixedModeID }) {
            return fixed
        }
        if let bundleID, let mode = modes.first(where: { !$0.isStandard && $0.apps.contains(bundleID) }) {
            return mode
        }
        return standardMode
    }

    public var standardMode: DictationMode {
        modes.first(where: \.isStandard) ?? DictationMode(id: DictationMode.standardID)
    }

    /// Settings with the mode's style in place of the Text section's.
    public func applying(_ mode: DictationMode) -> AppSettings {
        guard !mode.isStandard else { return self }
        var settings = self
        settings.punctuationStyle = mode.punctuationStyle
        settings.letterCase = mode.letterCase
        settings.fillerMode = mode.fillerMode
        settings.smartStructure = smartStructure && mode.smartStructure
        settings.dropTrailingPeriodInShortPhrases = mode.dropTrailingPeriod
        if let output = mode.outputMode { settings.outputMode = output }
        return settings
    }

    /// Automatic, then every mode in order, then automatic again. For the mode shortcut.
    public mutating func cycleMode() {
        let ids = modes.map(\.id)
        guard let current = fixedModeID, let index = ids.firstIndex(of: current) else {
            fixedModeID = ids.first
            return
        }
        fixedModeID = index + 1 < ids.count ? ids[index + 1] : nil
    }
}
