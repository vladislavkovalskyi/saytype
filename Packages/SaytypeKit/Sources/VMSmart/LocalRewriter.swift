import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import VMCore

/// One model answer with the numbers the benchmark and logs need.
public struct RewriteGeneration: Sendable {
    public var text: String
    public var promptTokens: Int
    /// Prompt tokens whose attention state came from the previous request.
    public var cachedTokens: Int
    public var generatedTokens: Int
    /// From the call to the first generated token: prompt processing, or the server's whole wait.
    public var timeToFirstToken: Double
    public var generationSeconds: Double
    /// Generation hit the token limit, so the answer is cut off.
    public var truncated: Bool
    /// Tokens guessed from the dictation and checked by the model, and how many of them it kept.
    public var draftedTokens: Int
    public var acceptedTokens: Int

    public init(text: String, promptTokens: Int = 0, cachedTokens: Int = 0, generatedTokens: Int = 0, timeToFirstToken: Double = 0, generationSeconds: Double = 0, truncated: Bool = false, draftedTokens: Int = 0, acceptedTokens: Int = 0) {
        self.text = text
        self.promptTokens = promptTokens
        self.cachedTokens = cachedTokens
        self.generatedTokens = generatedTokens
        self.timeToFirstToken = timeToFirstToken
        self.generationSeconds = generationSeconds
        self.truncated = truncated
        self.draftedTokens = draftedTokens
        self.acceptedTokens = acceptedTokens
    }

    public var tokensPerSecond: Double {
        generationSeconds > 0 ? Double(generatedTokens) / generationSeconds : 0
    }
}

/// Rewrites with a model on this Mac's GPU through MLX. Keeps the attention state of the last
/// prompt, so the next rewrite only processes what changed: usually just the dictation, because
/// the system prompt comes first and repeats.
public actor LocalRewriter {
    private let store: SmartModelStore
    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?
    private let promptCache = PromptCache()
    public private(set) var weightBytes = 0
    private var promptBytes = 0
    /// Off only to measure what the prompt cache saves.
    public private(set) var reusesPrompt = true
    /// Off only to measure what drafting from the dictation saves.
    public private(set) var draftsFromDictation = true

    public func setReusesPrompt(_ value: Bool) {
        reusesPrompt = value
    }

    public func setDraftsFromDictation(_ value: Bool) {
        draftsFromDictation = value
    }

    public init(store: SmartModelStore = SmartModelStore(repo: SmartModelStore.rewriteRepo)) {
        self.store = store
    }

    public var isLoaded: Bool { container != nil }

    /// GPU memory MLX holds in this process, for benchmarks.
    public static var activeMemory: Int { Memory.activeMemory }
    public static var peakMemory: Int { Memory.peakMemory }

    /// Bytes the model holds on the GPU: weights plus the cached prompt.
    public var residentBytes: Int { weightBytes + promptBytes }

    public func load() async throws {
        guard container == nil else { return }
        let task: Task<ModelContainer, Error>
        if let loading {
            task = loading
        } else {
            let folder = store.folder
            Memory.cacheLimit = 256 * 1024 * 1024
            task = Task { try await loadModelContainer(from: folder, using: TransformersTokenizerLoader()) }
            loading = task
        }
        do {
            let loaded = try await task.value
            // unload() may have run while the model was loading.
            guard loading == task else { return }
            container = loaded
            weightBytes = await loaded.perform { context in
                context.model.parameters().flattened().reduce(0) { $0 + $1.1.nbytes }
            }
        } catch {
            if loading == task { loading = nil }
            throw error
        }
    }

    public func unload() async {
        let loaded = container
        loading = nil
        container = nil
        weightBytes = 0
        promptBytes = 0
        let cache = promptCache
        // A generation may still hold the cache; reset it after that one finishes.
        if let loaded {
            await loaded.perform { _ in cache.reset() }
        }
        Memory.clearCache()
    }

    /// Loads the weights and runs a one-token answer, so Metal compiles its kernels now and not
    /// during the first dictation. With a request, its system prompt is processed and cached too.
    public func warmUp(for request: RewriteRequest? = nil) async throws {
        try await load()
        let system = request?.systemPrompt ?? "Reply with OK."
        _ = try await generate(system: system, user: "OK", maxTokens: 1)
    }

    public func rewrite(_ text: String, request: RewriteRequest) async throws -> RewriteGeneration {
        try await load()
        let user = request.userMessage(text)
        return try await generate(system: request.systemPrompt(for: text), user: user, maxTokens: nil, request: request)
    }

    /// - Parameter maxTokens: `nil` takes the request's limit for the counted prompt.
    func generate(system: String, user: String, maxTokens: Int?, request: RewriteRequest? = nil) async throws -> RewriteGeneration {
        guard let container else { throw CancellationError() }
        let cache = promptCache
        let reuse = reusesPrompt
        let drafts = draftsFromDictation
        let start = Date.timeIntervalSinceReferenceDate
        let (generation, bytes) = try await container.perform { context in
            // A rewrite skipped while waiting for the model must not start processing its prompt.
            try Task.checkCancellation()
            let messages: [[String: any Sendable]] = [["role": "system", "content": system], ["role": "user", "content": user]]
            let tokens = try context.tokenizer.applyChatTemplate(messages: messages, tools: nil, additionalContext: ["enable_thinking": false])
            let userTokens = context.tokenizer.encode(text: user, addSpecialTokens: false)
            let limit = maxTokens ?? request?.maxTokens(inputTokens: userTokens.count) ?? 256

            if !reuse { cache.reset() }
            let reused = cache.prepare(for: tokens, model: context.model, parameters: GenerateParameters(temperature: 0))
            do {
                defer { cache.keepPrompt(tokens) }
                var decoder = GreedyDecoder(model: context.model, layers: cache.layers, stops: Self.stopTokens(context), source: drafts ? userTokens : [])
                try decoder.prefill(Array(tokens[reused...]))
                let firstToken = Date.timeIntervalSinceReferenceDate
                try decoder.run(limit: limit)
                let end = Date.timeIntervalSinceReferenceDate
                let generation = RewriteGeneration(
                    text: context.tokenizer.decode(tokenIds: decoder.output, skipSpecialTokens: true),
                    promptTokens: tokens.count,
                    cachedTokens: reused,
                    generatedTokens: decoder.output.count,
                    timeToFirstToken: firstToken - start,
                    generationSeconds: end - firstToken,
                    truncated: !decoder.finished,
                    draftedTokens: decoder.drafted,
                    acceptedTokens: decoder.accepted
                )
                return (generation, cache.bytes)
            } catch is CancellationError {
                // The prompt is intact; only the partial answer goes.
                throw CancellationError()
            } catch {
                cache.reset()
                throw error
            }
        }
        promptBytes = bytes
        return generation
    }

    private static func stopTokens(_ context: ModelContext) -> Set<Int> {
        var stops = context.configuration.eosTokenIds
        if let eos = context.tokenizer.eosTokenId { stops.insert(eos) }
        for token in context.configuration.extraEOSTokens.union(["<|im_end|>", "<|endoftext|>"]) {
            if let id = context.tokenizer.convertTokenToId(token) { stops.insert(id) }
        }
        return stops
    }
}

/// Greedy decoding that guesses ahead from the dictation. A rewrite copies long runs of the
/// dictation (names, paths, whole clauses), so after the last generated tokens the dictation often
/// says what comes next. The guess and the pending token go through the model in one pass; the
/// model keeps the guessed tokens it would have produced itself and the cache drops the rest.
/// The answer is exactly what one-token-at-a-time greedy decoding gives, in fewer passes.
struct GreedyDecoder {
    let model: any LanguageModel
    let layers: [KVCache]
    let stops: Set<Int>
    /// Token ids of the dictation, where guesses come from.
    let source: [Int]

    private(set) var output: [Int] = []
    private(set) var finished = false
    private(set) var drafted = 0
    private(set) var accepted = 0
    private var pending = 0
    private var draftLength = 4
    /// Where in `source` the last accepted guess ended; the next match is looked for near it.
    private var cursor = 0

    init(model: any LanguageModel, layers: [KVCache], stops: Set<Int>, source: [Int]) {
        self.model = model
        self.layers = layers
        self.stops = stops
        self.source = source
    }

    /// Processes the new prompt tokens and picks the first answer token. Logits are computed for
    /// the last token only.
    mutating func prefill(_ tokens: [Int]) throws {
        var index = 0
        while tokens.count - index > 1 {
            let end = min(tokens.count - 1, index + 1024)
            _ = forward(Array(tokens[index..<end]))
            eval(layers)
            index = end
            try Task.checkCancellation()
        }
        pending = predictions(forward([tokens[tokens.count - 1]]))[0]
    }

    mutating func run(limit: Int) throws {
        while true {
            if stops.contains(pending) {
                finished = true
                return
            }
            output.append(pending)
            guard output.count < limit else { return }
            try Task.checkCancellation()

            let draft = guess(count: min(draftLength, limit - output.count))
            let predicted = predictions(forward([pending] + draft))
            var kept = 0
            while kept < draft.count, predicted[kept] == draft[kept], !stops.contains(draft[kept]) { kept += 1 }
            if kept < draft.count { trimPromptCache(layers, numTokens: draft.count - kept) }
            drafted += draft.count
            accepted += kept
            if !draft.isEmpty {
                draftLength = kept == draft.count ? min(draftLength * 2, 16) : max(2, kept + 1)
            }
            for token in draft[..<kept] {
                output.append(token)
                guard output.count < limit else { return }
            }
            pending = predicted[kept]
        }
    }

    private func forward(_ tokens: [Int]) -> MLXArray {
        let input = LMInput.Text(tokens: MLXArray(tokens.map { Int32($0) })[.newAxis])
        return model(input, cache: layers, state: nil).logits
    }

    private func predictions(_ logits: MLXArray) -> [Int] {
        argMax(logits[0], axis: -1).asArray(Int32.self).map(Int.init)
    }

    /// The tokens that followed the latest occurrence of the answer's last two or three tokens
    /// in the dictation, preferring the occurrence closest after the previous guess.
    private mutating func guess(count: Int) -> [Int] {
        guard count > 0, !source.isEmpty else { return [] }
        for n in [3, 2] where output.count >= n {
            let tail = Array(output.suffix(n))
            var best: Int?
            var i = 0
            while i + n < source.count {
                if source[i] == tail[0], Array(source[i..<i + n]) == tail {
                    let start = i + n
                    if best == nil || (start >= cursor && (best! < cursor || start < best!)) { best = start }
                }
                i += 1
            }
            if let best {
                cursor = best
                return Array(source[best..<min(source.count, best + count)])
            }
        }
        return []
    }
}

/// The key–value state of the last prompt. Only touched inside `ModelContainer.perform`,
/// which runs one closure at a time.
private final class PromptCache: @unchecked Sendable {
    private(set) var layers: [KVCache] = []
    private var tokens: [Int] = []

    var bytes: Int {
        layers.reduce(0) { total, layer in total + layer.state.reduce(0) { $0 + $1.nbytes } }
    }

    /// Trims the cache to the longest prefix it shares with `prompt` and returns that length.
    /// At least one prompt token is left to process, since generation starts from its logits.
    func prepare(for prompt: [Int], model: any LanguageModel, parameters: GenerateParameters) -> Int {
        guard !layers.isEmpty, canTrimPromptCache(layers) else {
            layers = model.newCache(parameters: parameters)
            tokens = []
            return 0
        }
        var shared = 0
        let limit = min(tokens.count, prompt.count - 1)
        while shared < limit, tokens[shared] == prompt[shared] { shared += 1 }
        let offset = layers.first?.offset ?? 0
        if offset > shared { trimPromptCache(layers, numTokens: offset - shared) }
        return shared
    }

    /// Drops the generated tokens and remembers the prompt for the next request.
    func keepPrompt(_ prompt: [Int]) {
        guard let offset = layers.first?.offset else { return }
        if offset > prompt.count { trimPromptCache(layers, numTokens: offset - prompt.count) }
        tokens = Array(prompt.prefix(min(offset, prompt.count)))
    }

    func reset() {
        layers = []
        tokens = []
    }
}
