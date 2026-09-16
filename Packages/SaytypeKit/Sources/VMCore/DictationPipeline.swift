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

        // A line collects the raw words up to the next break and is formatted as one text, so
        // "удали последнее предложение" works on Whisper's sentences in every punctuation style.
        var output = ""
        var line = ""
        var send = false
        let capitalizeLines = style.punctuationStyle == .full && style.letterCase == .asSpoken
        func flushLine() {
            guard !line.isEmpty else { return }
            let source = mode.developer ? DeveloperFormatter.apply(line) : line
            var text = TextFormatter.format(Transcript(text: source), settings: style)
            line = ""
            guard !text.isEmpty else { return }
            let afterBreak = output.last?.isNewline == true
            if afterBreak, capitalizeLines { text = text.capitalizingFirstWord() }
            if !output.isEmpty, !afterBreak { output += " " }
            output += text
        }
        for piece in pieces {
            switch piece {
            case .text(let raw):
                line = line.isEmpty ? raw : line + " " + raw
            case .command(.newLine):
                flushLine()
                output = output.trimmingTrailingSpaces() + "\n"
            case .command(.newParagraph):
                flushLine()
                output = output.trimmingTrailingWhitespace() + "\n\n"
            case .command(.deleteLastSentence):
                if line.contains(where: { !$0.isWhitespace }) {
                    line = VoiceCommands.droppingLastSentence(line)
                } else {
                    output = VoiceCommands.droppingLastSentence(output)
                }
            case .command(.send):
                send = true
            }
        }
        flushLine()
        return PipelineResult(text: output.trimmingCharacters(in: .whitespacesAndNewlines), send: send)
    }
}

extension String {
    fileprivate func trimmingTrailingSpaces() -> String {
        var s = Substring(self)
        while s.last == " " { s = s.dropLast() }
        return String(s)
    }

    fileprivate func trimmingTrailingWhitespace() -> String {
        var s = Substring(self)
        while s.last?.isWhitespace == true { s = s.dropLast() }
        return String(s)
    }

    /// "как дела?" → "Как дела?" at the start of a line. Terms keep their case: useEffect, iPhone, src/app.tsx.
    fileprivate func capitalizingFirstWord() -> String {
        guard let index = firstIndex(where: \.isLetter), self[index].isLowercase,
              self[..<index].allSatisfy({ "«\"'(„“".contains($0) }) else { return self }
        let word = self[index...].prefix { !$0.isWhitespace }
        guard !word.dropFirst().contains(where: \.isUppercase), !Words.isCodeLike(String(word)) else { return self }
        return replacingCharacters(in: index...index, with: self[index].uppercased())
    }
}
