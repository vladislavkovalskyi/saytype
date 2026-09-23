import Foundation
import VMCore

/// Turns 16 kHz mono samples into text.
public protocol TranscriptionEngine: Sendable {
    /// Loads the model. Can take minutes the first time Core ML specialises it for the chip.
    func prepare() async throws
    /// Transcribes the whole buffer.
    func transcribe(_ samples: [Float], hints: TranscriptionHints) async throws -> Transcript
}

/// Per-request context for the recogniser.
public struct TranscriptionHints: Sendable, Equatable {
    /// ISO code such as "ru"; nil lets the engine detect the language.
    public var language: String?
    /// Terms the decoder sees as preceding context, most important first. The engine keeps as
    /// many as fit `PromptBuilder.tokenLimit`, counted with its own tokenizer.
    public var glossary: [String]
    /// English text from speech in any language, Whisper's own translation.
    public var translate: Bool

    public init(language: String? = "ru", glossary: [String] = [], translate: Bool = false) {
        self.language = language
        self.glossary = glossary
        self.translate = translate
    }
}
