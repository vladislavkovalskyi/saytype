import VMCore

/// Turns a raw transcript into the text that gets inserted.
struct TextPipeline {
    let settings: AppSettings

    func format(_ transcript: Transcript) -> String {
        TextFormatter.format(transcript, settings: settings)
    }
}
