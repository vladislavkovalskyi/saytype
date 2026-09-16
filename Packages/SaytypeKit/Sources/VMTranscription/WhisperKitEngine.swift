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

    public func transcribe(_ samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        try await prepare()
        guard let pipe, !samples.isEmpty else { return .empty }

        var options = DecodingOptions(
            verbose: false,
            task: hints.translate ? .translate : .transcribe,
            language: hints.language,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: hints.language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: hints.wordTimestamps,
            chunkingStrategy: samples.count > 30 * 16_000 ? .vad : ChunkingStrategy.none
        )
        if let prompt = hints.prompt, let tokenizer = pipe.tokenizer {
            options.promptTokens = tokenizer
                .encode(text: " " + prompt.trimmingCharacters(in: .whitespaces))
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }

        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        if let t = results.first?.timings {
            lastTimings = EngineTimings(encoding: t.encoding, decodingLoop: t.decodingLoop, wordTimestamps: t.decodingWordTimestamps, total: t.fullPipeline)
        }
        let segments = results.flatMap(\.segments)
        let text = HallucinationFilter.clean(
            segments.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        )
        let words = segments.flatMap { $0.words ?? [] }.map {
            TranscriptWord(text: $0.word.trimmingCharacters(in: .whitespaces), start: Double($0.start), end: Double($0.end))
        }
        return Transcript(text: text, words: text.isEmpty ? [] : words)
    }
}

public struct EngineTimings: Sendable {
    public let encoding: Double
    public let decodingLoop: Double
    public let wordTimestamps: Double
    public let total: Double
}
