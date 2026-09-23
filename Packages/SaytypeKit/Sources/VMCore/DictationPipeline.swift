import Foundation

/// Text ready to deliver, before the optional language model steps.
public struct PipelineResult: Equatable, Sendable {
    public var text: String
    /// The dictation ended with "отправь".
    public var send: Bool
    /// Snippets the text holds as markers: ⟦1⟧ is the first. `SnippetPlacement` puts them in.
    public var snippets: [Snippet]

    public init(text: String, send: Bool = false, snippets: [Snippet] = []) {
        self.text = text
        self.send = send
        self.snippets = snippets
    }
}

/// The deterministic part of a dictation: voice commands, developer rules and the text
/// formatter, in the mode's style. Runs in milliseconds; language model steps come after.
public enum DictationPipeline {
    /// - Parameter snippets: phrases to replace with markers. Voice commands are found first, so
    ///   a command always wins over a snippet with the same words.
    public static func format(_ transcript: Transcript, settings: AppSettings, mode: DictationMode, projectTerms: [String] = [], snippets: [Snippet] = []) -> PipelineResult {
        let style = settings.applying(mode)
        var pieces = settings.voiceCommands ? VoiceCommands.parse(transcript.text) : [.text(transcript.text)]
        var found: [Snippet] = []
        if !snippets.isEmpty {
            let matcher = SnippetMatcher(snippets)
            for index in pieces.indices {
                guard case .text(let raw) = pieces[index] else { continue }
                pieces[index] = .text(matcher.replacing(in: raw, found: &found))
            }
        }

        // Without commands the formatter keeps the segment timings, which place paragraph breaks.
        if pieces.count == 1, case .text(let raw) = pieces[0] {
            let source = mode.developer ? DeveloperFormatter.apply(raw) : raw
            // Paragraphs fall back to plain text when the segments no longer match the text,
            // which a marker in place of the trigger's words always makes them do.
            let segments = found.isEmpty ? transcript.segments : []
            return PipelineResult(text: TextFormatter.format(Transcript(text: source, segments: segments), settings: style, projectTerms: projectTerms), snippets: found)
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
            var text = TextFormatter.format(Transcript(text: source), settings: style, projectTerms: projectTerms)
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
        return PipelineResult(text: output.trimmingCharacters(in: .whitespacesAndNewlines), send: send, snippets: found)
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
