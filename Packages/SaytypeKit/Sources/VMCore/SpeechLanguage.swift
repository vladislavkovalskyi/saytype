import Foundation

extension AppSettings {
    /// The language Whisper listens for: one of its 99 languages, or detection from speech.
    ///
    /// Stored as the Whisper code ("ru", "pl", "auto"), the same JSON the earlier
    /// three-case enum produced.
    public struct SpeechLanguage: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public var id: String { rawValue }

        public static let auto = SpeechLanguage(rawValue: "auto")
        public static let russian = SpeechLanguage(rawValue: "ru")
        public static let english = SpeechLanguage(rawValue: "en")

        /// Code passed to Whisper; `nil` asks it to detect the language.
        public var whisperCode: String? {
            rawValue == Self.auto.rawValue ? nil : rawValue
        }

        /// saytype's formatting (fillers, lists, transliterated terms) is tuned for these.
        public var isTuned: Bool {
            self == .russian || self == .english
        }

        /// Name in the interface language, e.g. "польский" in a Russian UI.
        public func localizedName(locale: Locale = .current) -> String {
            guard let code = whisperCode else { return "Auto" }
            return locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code
        }

        /// Name in the language itself, e.g. "polski".
        public var nativeName: String {
            guard let code = whisperCode else { return "Auto" }
            let locale = Locale(identifier: code)
            return locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code
        }

        /// Every language Whisper large-v3 transcribes, in Whisper's order of training data size.
        public static let whisperCodes = [
            "en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr", "pl", "ca", "nl", "ar", "sv", "it",
            "id", "hi", "fi", "vi", "he", "uk", "el", "ms", "cs", "ro", "da", "hu", "ta", "no", "th", "ur",
            "hr", "bg", "lt", "la", "mi", "ml", "cy", "sk", "te", "fa", "lv", "bn", "sr", "az", "sl", "kn",
            "et", "mk", "br", "eu", "is", "hy", "ne", "mn", "bs", "kk", "sq", "sw", "gl", "mr", "pa", "si",
            "km", "sn", "yo", "so", "af", "oc", "ka", "be", "tg", "sd", "gu", "am", "yi", "lo", "uz", "fo",
            "ht", "ps", "tk", "nn", "mt", "sa", "lb", "my", "bo", "tl", "mg", "as", "tt", "haw", "ln", "ha",
            "ba", "jw", "su", "yue",
        ]

        /// Russian, English and detection first, then every other language by name.
        public static func all(locale: Locale = .current) -> [SpeechLanguage] {
            let others = whisperCodes
                .filter { $0 != "ru" && $0 != "en" }
                .map(SpeechLanguage.init(rawValue:))
                .sorted { $0.localizedName(locale: locale).localizedCompare($1.localizedName(locale: locale)) == .orderedAscending }
            return [.russian, .english, .auto] + others
        }

        /// The default for a new install: the system language when Whisper knows it,
        /// otherwise detection from speech.
        public static var systemDefault: SpeechLanguage {
            matching(preferredLanguages: Locale.preferredLanguages)
        }

        /// `["pl-PL", "en-US"]` → Polish: only the first, primary language counts.
        public static func matching(preferredLanguages: [String]) -> SpeechLanguage {
            guard let first = preferredLanguages.first,
                  let code = Locale.Language(identifier: first).languageCode?.identifier
            else { return .auto }
            let whisper = code == "nb" ? "no" : code
            return whisperCodes.contains(whisper) ? SpeechLanguage(rawValue: whisper) : .auto
        }
    }
}
