import Foundation

/// A global shortcut: a physical key (HIToolbox `kVK_*`, the same key on every layout)
/// with modifiers.
public struct KeyShortcut: Codable, Hashable, Sendable {
    public var keyCode: Int
    public var control: Bool
    public var option: Bool
    public var command: Bool
    public var shift: Bool

    public init(keyCode: Int, control: Bool = false, option: Bool = false, command: Bool = false, shift: Bool = false) {
        self.keyCode = keyCode
        self.control = control
        self.option = option
        self.command = command
        self.shift = shift
    }

    /// ⌃⌥V
    public static let pasteAgain = KeyShortcut(keyCode: 0x09, control: true, option: true)
    /// ⌃⌥C
    public static let copyLast = KeyShortcut(keyCode: 0x08, control: true, option: true)
    /// ⌃⌥M
    public static let cycleMode = KeyShortcut(keyCode: 0x2E, control: true, option: true)
}

extension AppSettings {
    /// Global shortcuts; `nil` turns a shortcut off.
    public struct Shortcuts: Codable, Equatable, Sendable {
        public var pasteAgain: KeyShortcut? = .pasteAgain
        public var copyLast: KeyShortcut? = .copyLast
        public var cycleMode: KeyShortcut? = .cycleMode

        public init() {}

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Shortcuts()
            // A missing key is a new shortcut; an explicit null is one the user turned off.
            pasteAgain = c.contains(.pasteAgain) ? try c.decodeIfPresent(KeyShortcut.self, forKey: .pasteAgain) : defaults.pasteAgain
            copyLast = c.contains(.copyLast) ? try c.decodeIfPresent(KeyShortcut.self, forKey: .copyLast) : defaults.copyLast
            cycleMode = c.contains(.cycleMode) ? try c.decodeIfPresent(KeyShortcut.self, forKey: .cycleMode) : defaults.cycleMode
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pasteAgain, forKey: .pasteAgain)
            try c.encode(copyLast, forKey: .copyLast)
            try c.encode(cycleMode, forKey: .cycleMode)
        }

        private enum CodingKeys: String, CodingKey {
            case pasteAgain, copyLast, cycleMode
        }
    }

    /// Where rewrites and translations run. Everything stays on this Mac.
    public struct LanguageModel: Codable, Equatable, Sendable {
        public enum Engine: String, Codable, CaseIterable, Sendable {
            case off
            /// Qwen3 4B through MLX, downloaded by saytype.
            case builtIn
            /// Ollama's OpenAI-compatible server.
            case ollama
            /// LM Studio's OpenAI-compatible server.
            case lmStudio
        }

        public var engine = Engine.off
        public var ollamaURL = "http://localhost:11434"
        public var ollamaModel = ""
        public var lmStudioURL = "http://localhost:1234"
        public var lmStudioModel = ""
        /// Past this the dictation is inserted without the rewrite.
        public var timeoutSeconds: Double = 20

        public init() {}

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = LanguageModel()
            engine = try c.decodeIfPresent(Engine.self, forKey: .engine) ?? defaults.engine
            ollamaURL = try c.decodeIfPresent(String.self, forKey: .ollamaURL) ?? defaults.ollamaURL
            ollamaModel = try c.decodeIfPresent(String.self, forKey: .ollamaModel) ?? defaults.ollamaModel
            lmStudioURL = try c.decodeIfPresent(String.self, forKey: .lmStudioURL) ?? defaults.lmStudioURL
            lmStudioModel = try c.decodeIfPresent(String.self, forKey: .lmStudioModel) ?? defaults.lmStudioModel
            timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? defaults.timeoutSeconds
        }
    }
}
