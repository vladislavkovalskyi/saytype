import Foundation
import Testing
@testable import VMTranscription

@Suite struct ModelStoreTests {
    @Test func listsOnlyCompleteVariantsWithoutThePrefix() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "saytype-models-\(UUID().uuidString)", directoryHint: .isDirectory)
        let repo = base.appending(path: "models/\(ModelStore.repo)", directoryHint: .isDirectory)
        for (name, parts) in [
            ("openai_whisper-large-v3-v20240930_turbo_632MB", ModelStore.requiredParts),
            ("openai_whisper-large-v3_947MB", ModelStore.requiredParts),
            ("openai_whisper-small", Array(ModelStore.requiredParts.prefix(2))),
        ] {
            for part in parts {
                try FileManager.default.createDirectory(at: repo.appending(path: "\(name)/\(part)", directoryHint: .isDirectory), withIntermediateDirectories: true)
            }
        }
        let store = ModelStore(base: base)
        #expect(store.downloadedVariants() == ["large-v3-v20240930_turbo_632MB", "large-v3_947MB"])
        #expect(store.downloadedVariants().allSatisfy(store.isDownloaded))
    }
}
