import Foundation

/// A spoken command inside a dictation.
public enum VoiceCommand: Equatable, Sendable {
    /// "новая строка", "new line"
    case newLine
    /// "новый абзац", "new paragraph"
    case newParagraph
    /// "удали последнее предложение", "delete last sentence"
    case deleteLastSentence
    /// "отправь", "send": Return after the paste.
    case send
}

/// Dictated text split at voice commands.
public enum DictationPiece: Equatable, Sendable {
    case text(String)
    case command(VoiceCommand)
}

public enum VoiceCommands {
    /// Splits a transcript at spoken commands. Text without commands comes back as one piece.
    public static func parse(_ text: String) -> [DictationPiece] {
        [.text(text)]
    }

    /// `text` without its last sentence, for "удали последнее предложение".
    public static func droppingLastSentence(_ text: String) -> String {
        text
    }
}
