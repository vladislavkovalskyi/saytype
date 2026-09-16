import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
import VMCore

/// Labels sentences with a local language model on the GPU and rebuilds the text from the
/// labels. The words themselves never pass through the model's output.
public actor SmartStructurer {
    private let store: SmartModelStore
    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?

    public init(store: SmartModelStore = SmartModelStore()) {
        self.store = store
    }

    public var isLoaded: Bool { container != nil }

    public func load() async throws {
        guard container == nil else { return }
        let task: Task<ModelContainer, Error>
        if let loading {
            task = loading
        } else {
            let folder = store.folder
            Memory.cacheLimit = 64 * 1024 * 1024
            task = Task { try await loadModelContainer(from: folder, using: TransformersTokenizerLoader()) }
            loading = task
        }
        do {
            let loaded = try await task.value
            // unload() may have run while the model was loading.
            if loading == task { container = loaded }
        } catch {
            if loading == task { loading = nil }
            throw error
        }
    }

    public func unload() {
        loading = nil
        container = nil
        Memory.clearCache()
    }

    /// Returns the restructured text, or `nil` when the model changed nothing.
    public func structure(_ text: String, allowDroppingFillers: Bool = false) async throws -> String? {
        let sentences = SmartStructure.sentences(text)
        guard sentences.count >= 2 else { return nil }
        let labels = try await labels(for: sentences)
        let result = SmartStructure.render(sentences, labels: labels, paragraphStarts: SmartStructure.paragraphStarts(text))
        guard result != text, StructureValidator.accepts(original: text, candidate: result, allowDroppingFillers: allowDroppingFillers) else {
            return nil
        }
        return result
    }

    public func labels(for sentences: [String]) async throws -> [StructureLabel] {
        try await load()
        guard let container else { return [] }
        let session = ChatSession(
            container,
            instructions: SmartStructure.systemPrompt,
            generateParameters: GenerateParameters(maxTokens: sentences.count * 4 + 8, temperature: 0),
            additionalContext: ["enable_thinking": false]
        )
        let output = try await session.respond(to: SmartStructure.userMessage(sentences))
        try Task.checkCancellation()
        return SmartStructure.parseLabels(output, count: sentences.count)
    }
}

struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await AutoTokenizer.from(modelFolder: directory))
    }
}

struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
