import Foundation
import VMCore
import WhisperKit

/// Whisper through WhisperKit on the Neural Engine.
public actor WhisperKitEngine: TranscriptionEngine {
    private let store: ModelStore
    private let variant: String
    private var pipe: WhisperKit?
    /// Stage timings of the last transcription, for benchmarks.
    public private(set) var lastTimings: EngineTimings?

    public init(store: ModelStore = ModelStore(), variant: String) {
        self.store = store
        self.variant = variant
    }

    public var isLoaded: Bool { pipe != nil }

    /// Whether Whisper's own English translation works with this variant. large-v3-turbo
    /// (the v20240930 builds) was fine-tuned on transcription only: asked to translate Russian
    /// speech it returned Russian text for 8 of 8 phrases. large-v3 was trained to translate.
    public static func supportsTranslation(_ variant: String) -> Bool {
        !variant.contains("turbo") && !variant.contains("v20240930")
    }

    public func prepare() async throws {
        guard pipe == nil else { return }
        let config = WhisperKitConfig(
            modelFolder: store.folder(for: variant).path,
            tokenizerFolder: store.base,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )
        pipe = try await WhisperKit(config)
    }

    public func unload() async {
        await pipe?.unloadModels()
        pipe = nil
    }

    /// WhisperKit starts no window in the last `windowClipTime` of the audio (1 s by default),
    /// and its VAD chunker keeps a fixed second of its own. As it was, a recording under a second
    /// got no window at all; with a plain second of padding instead, a window started on the
    /// silence after the last word and Whisper answered it with "Thank you.". So the engine puts
    /// the margin `voiceEndMargin` before the last frame of voice, whatever follows it: zeros
    /// when the voice ends less than a second before the end, for the chunker, and a
    /// `windowClipTime` that reaches back from the end of the audio to that point. The first
    /// window always starts.
    static let windowClip = 16_000
    static let voiceEndMargin = 4_800
    static let firstWindowRoom = 800
    /// Segments that start this close to the end of the recording, or later, are made up.
    static let tailSlack = 0.1

    /// Where WhisperKit may start windows over this recording, in samples, and how the engine
    /// holds it there: zeros after the recording and `windowClipTime` in seconds.
    static func windowPlan(_ samples: [Float]) -> (limit: Int, padding: Int, clipTime: Float) {
        let limit = VoiceGate.voiceEnd(samples).map { max(Int($0 * 16_000) - voiceEndMargin, firstWindowRoom) } ?? samples.count
        let padding = max(0, limit + windowClip - samples.count)
        return (limit, padding, Float(samples.count + padding - limit) / 16_000)
    }

    public func transcribe(_ samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        try await prepare()
        guard let pipe, !samples.isEmpty else { return .empty }
        let duration = Double(samples.count) / 16_000

        var options = DecodingOptions(
            verbose: false,
            task: hints.translate ? .translate : .transcribe,
            language: hints.language,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: hints.language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            // Word timings are misaligned whenever there is a prompt: WhisperKit reads the
            // alignment from the start of the decoder context, which the prompt occupies. The
            // wrong timings dropped whole segments. Segment timestamps are not affected.
            wordTimestamps: false,
            // WhisperKit's own check, not Whisper's: an unlikely first token re-decodes the window
            // at a higher temperature. After the prompt the first token is a timestamp that often
            // looks unlikely, so a third of the windows went through up to five random re-decodes
            // (29 fallbacks on 40 single words, 3 on one 70 s dictation, one chunk came back
            // empty). Silence is the voice gate's and the hallucination filter's job.
            firstTokenLogProbThreshold: nil,
            chunkingStrategy: samples.count > 30 * 16_000 ? .vad : ChunkingStrategy.none
        )
        if let tokenizer = pipe.tokenizer {
            let prompt = PromptBuilder.prompt(glossary: hints.glossary) { Self.promptTokens($0, tokenizer: tokenizer).count }
            options.promptTokens = prompt.map { Self.promptTokens($0, tokenizer: tokenizer) }
        }

        let (limit, padding, clipTime) = Self.windowPlan(samples)
        options.windowClipTime = clipTime
        let results = try await pipe.transcribe(audioArray: samples + [Float](repeating: 0, count: padding), decodeOptions: options)
        if let t = results.first?.timings {
            lastTimings = EngineTimings(encoding: t.encoding, decodingLoop: t.decodingLoop, total: t.fullPipeline)
        }
        // Subtitle credits are cleaned per segment too, so the segments keep matching the text
        // and still place paragraph breaks.
        let segments: [TranscriptSegment] = results.flatMap(\.segments).compactMap { segment in
            // A window begun after the voice ended (the VAD chunker keeps only its own second) and
            // a segment begun in the padding are made up.
            guard segment.seek < limit, Double(segment.start) < duration - Self.tailSlack else { return nil }
            let text = HallucinationFilter.clean(segment.text.trimmingCharacters(in: .whitespaces))
            return text.isEmpty ? nil : TranscriptSegment(text: text, start: Double(segment.start), end: Double(segment.end))
        }
        var text = HallucinationFilter.clean(segments.map(\.text).joined(separator: " "))
        if !hints.translate, HallucinationFilter.isStandalone(text) { text = "" }
        return Transcript(text: text, segments: text.isEmpty ? [] : segments)
    }

    /// The prompt as WhisperKit sees it: text tokens after a leading space.
    static func promptTokens(_ prompt: String, tokenizer: any WhisperTokenizer) -> [Int] {
        tokenizer.encode(text: " " + prompt.trimmingCharacters(in: .whitespaces))
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
    }
}

public struct EngineTimings: Sendable {
    public let encoding: Double
    public let decodingLoop: Double
    public let total: Double
}
