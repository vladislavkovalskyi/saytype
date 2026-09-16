import VMCore

/// Turns a raw transcript into the text that gets inserted.
struct TextPipeline {
    let settings: AppSettings

    func format(_ transcript: Transcript) -> String {
        var text = transcript.text
        if settings.latinTerms {
            text = DictionaryRewriter(entries: settings.dictionary).apply(to: text)
        }
        text = Cleanup.removeFillers(text, mode: settings.fillerMode)
        if settings.dropTrailingPeriodInShortPhrases {
            text = Cleanup.dropTrailingPeriod(text)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
