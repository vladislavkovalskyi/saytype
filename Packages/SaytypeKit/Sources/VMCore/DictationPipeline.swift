import Foundation

/// Text ready to deliver, before the optional language model steps.
public struct PipelineResult: Equatable, Sendable {
    public var text: String
    /// The dictation ended with "отправь".
    public var send: Bool

    public init(text: String, send: Bool = false) {
        self.text = text
        self.send = send
    }
}

/// The deterministic part of a dictation: voice commands, developer rules and the text
/// formatter, in the mode's style. Runs in milliseconds; language model steps come after.
public enum DictationPipeline {
    public static func format(_ transcript: Transcript, settings: AppSettings, mode: DictationMode) -> PipelineResult {
        let style = settings.applying(mode)
        let pieces = settings.voiceCommands ? VoiceCommands.parse(transcript.text) : [.text(transcript.text)]

        // Without commands the formatter keeps the word timings, which place paragraph breaks.
        if pieces.count == 1, case .text(let raw) = pieces[0] {
            let source = mode.developer ? DeveloperFormatter.apply(raw) : raw
            // Paragraphs fall back to plain text when the words no longer match the timings.
            return PipelineResult(text: TextFormatter.format(Transcript(text: source, words: transcript.words), settings: style))
        }

        var output = ""
        var send = false
        for piece in pieces {
            switch piece {
            case .text(let raw):
                let source = mode.developer ? DeveloperFormatter.apply(raw) : raw
                let text = TextFormatter.format(Transcript(text: source), settings: style)
                guard !text.isEmpty else { continue }
                if let last = output.last, !last.isNewline { output += " " }
                output += text
            case .command(.newLine):
                output = output.trimmingTrailingSpaces() + "\n"
            case .command(.newParagraph):
                output = output.trimmingTrailingSpaces() + "\n\n"
            case .command(.deleteLastSentence):
                output = VoiceCommands.droppingLastSentence(output)
            case .command(.send):
                send = true
            }
        }
        return PipelineResult(text: output.trimmingCharacters(in: .whitespacesAndNewlines), send: send)
    }
}

extension String {
    fileprivate func trimmingTrailingSpaces() -> String {
        var s = Substring(self)
        while s.last == " " { s = s.dropLast() }
        return String(s)
    }
}
