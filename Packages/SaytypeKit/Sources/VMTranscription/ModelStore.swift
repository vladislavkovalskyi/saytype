import Foundation
import WhisperKit

/// Downloads Whisper models once and finds them on disk afterwards.
///
/// Layout under `base` follows the Hugging Face hub cache WhisperKit uses:
/// `models/argmaxinc/whisperkit-coreml/<variant>` and the tokenizer under
/// `models/openai/whisper-large-v3`. After `download` nothing touches the network.
public struct ModelStore: Sendable {
    public static let repo = "argmaxinc/whisperkit-coreml"
    static let requiredParts = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"]

    public let base: URL

    public init(base: URL = ModelStore.defaultBase) {
        self.base = base
    }

    public static var defaultBase: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "dev.kovalskyi.saytype/Models", directoryHint: .isDirectory)
    }

    /// WhisperKit stores most variants with an "openai_whisper-" prefix.
    public func folder(for variant: String) -> URL {
        let repoFolder = base.appending(path: "models/\(Self.repo)", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: repoFolder.path)) ?? []
        let name = names.first { $0 == variant || $0.hasSuffix("_" + variant) || $0.hasSuffix("-" + variant) }
        return repoFolder.appending(path: name ?? "openai_whisper-\(variant)", directoryHint: .isDirectory)
    }

    /// True when every Core ML part of the variant is on disk.
    public func isDownloaded(_ variant: String) -> Bool {
        let folder = folder(for: variant)
        return Self.requiredParts.allSatisfy { FileManager.default.fileExists(atPath: folder.appending(path: $0).path) }
    }

    /// Every variant on disk with all its Core ML parts, sorted by name: what a re-transcription
    /// can use besides the current model.
    public func downloadedVariants() -> [String] {
        let repoFolder = base.appending(path: "models/\(Self.repo)", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: repoFolder.path)) ?? []
        return names
            .filter { name in
                Self.requiredParts.allSatisfy { FileManager.default.fileExists(atPath: repoFolder.appending(path: "\(name)/\($0)").path) }
            }
            .map { $0.hasPrefix("openai_whisper-") ? String($0.dropFirst("openai_whisper-".count)) : $0 }
            .sorted()
    }

    /// Downloads the model and its tokenizer. Resumes partial downloads.
    public func download(_ variant: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let folder = try await WhisperKit.download(variant: variant, downloadBase: base, from: Self.repo) { value in
            progress(value.fractionCompleted)
        }
        // Fetch the tokenizer now so the first transcription works offline.
        _ = try await ModelUtilities.loadTokenizer(for: .largev3, tokenizerFolder: base)
        return folder
    }
}
