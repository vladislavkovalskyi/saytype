import Foundation
import Observation
import OSLog
import VMCore
import VMSmart
import VMTranscription

/// Rewrites and translations with a language model on this Mac: the built-in Qwen3 4B,
/// Ollama or LM Studio. Without a ready engine every call returns `nil` and the dictation
/// is inserted as formatted.
@MainActor
@Observable
final class RewriteService {
    typealias Engine = AppSettings.LanguageModel.Engine

    enum State: Equatable {
        case off
        case missing
        case downloading(Double)
        case ready
        case failed(String)
    }

    /// The last health check of Ollama or LM Studio.
    struct ServerStatus: Equatable {
        enum Phase: Equatable {
            case unknown
            case checking
            case connected
            case unreachable(String)
        }

        var phase = Phase.unknown
        var models: [String] = []
        /// The address the check went to; a changed address needs a new check.
        var url = ""
        var checkedAt: Date?
    }

    /// How the last rewrite ended, for the settings screen.
    struct LastRun: Equatable {
        enum Outcome: Equatable {
            case applied
            case rejected(String)
            case timedOut
            case failed(String)
        }

        let outcome: Outcome
        let seconds: Double
        let tokensPerSecond: Double
    }

    private(set) var builtInDownloaded: Bool
    /// Download progress of the built-in model, `nil` when no download runs.
    private(set) var downloadProgress: Double?
    private(set) var builtInError: String?
    private(set) var builtInLoaded = false
    private(set) var builtInLoading = false
    /// Weights plus the cached prompt while the built-in model is in memory.
    private(set) var memoryBytes = 0
    private(set) var servers: [Engine: ServerStatus] = [:]
    private(set) var lastRun: LastRun?

    /// On disk, from the Hugging Face listing: 2.28 GB.
    let downloadGigabytes = 2.3
    /// While loaded, measured with vm-smart: 2.26 GB of weights, 2.3 GB active after loading,
    /// 3.0 GB at the peak of a 150-word prompt.
    let loadedGigabytes = 2.6
    /// The built-in model leaves memory after this much idle time.
    let idleUnload: Duration = .seconds(300)
    /// A server check this recent is trusted without asking again.
    let healthCacheSeconds: TimeInterval = 30

    @ObservationIgnored private weak var settings: SettingsStore?
    @ObservationIgnored private let store = SmartModelStore(repo: SmartModelStore.rewriteRepo)
    @ObservationIgnored private lazy var local = LocalRewriter(store: store)
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var warmTask: Task<Void, Never>?
    @ObservationIgnored private var unloadTask: Task<Void, Never>?
    @ObservationIgnored private var checkTasks: [Engine: Task<Void, Never>] = [:]
    @ObservationIgnored private var preloadedAt: [String: Date] = [:]

    private static let log = Logger(subsystem: "dev.kovalskyi.saytype", category: "rewrite")

    init() {
        builtInDownloaded = AppModel.isPreviewLaunch || store.isDownloaded
    }

    /// Connects the service to the settings: the current engine drives `state`, and a server
    /// engine is checked right away so the first dictation can use it.
    func attach(_ settings: SettingsStore) {
        self.settings = settings
        if AppModel.isPreviewLaunch {
            applyPreviewState(settings)
        } else {
            checkServer(settings.value)
        }
    }

    // MARK: State

    /// State of the engine chosen in settings.
    var state: State {
        guard let settings else { return .off }
        return state(for: settings.value)
    }

    func state(for settings: AppSettings) -> State {
        switch settings.languageModel.engine {
        case .off:
            return .off
        case .builtIn:
            if let downloadProgress { return .downloading(downloadProgress) }
            if let builtInError { return .failed(builtInError) }
            return builtInDownloaded ? .ready : .missing
        case .ollama, .lmStudio:
            let status = status(for: settings)
            switch status.phase {
            case .unreachable(let message): return .failed(message)
            case .connected where isReady(settings): return .ready
            default: return .missing
            }
        }
    }

    /// The check of the engine's server at the address in settings.
    func status(for settings: AppSettings) -> ServerStatus {
        let engine = settings.languageModel.engine
        guard let status = servers[engine], status.url == Self.url(settings, engine) else { return ServerStatus() }
        return status
    }

    /// True when a rewrite can run now.
    func isReady(_ settings: AppSettings) -> Bool {
        let model = settings.languageModel
        switch model.engine {
        case .off:
            return false
        case .builtIn:
            return builtInDownloaded && downloadProgress == nil
        case .ollama, .lmStudio:
            let name = Self.modelName(settings, model.engine)
            let status = status(for: settings)
            return status.phase == .connected && !name.isEmpty && (status.models.isEmpty || status.models.contains(name))
        }
    }

    /// Whisper large-v3-turbo was not trained to translate and answers in the spoken language,
    /// so with it only a language model translates. The modes screen shows this.
    func translationNeedsLanguageModel(_ settings: AppSettings) -> Bool {
        !isReady(settings) && !WhisperKitEngine.supportsTranslation(settings.whisperModel)
    }

    // MARK: Warm-up

    /// Loads the model when a dictation that needs it starts, so the final pass does not wait.
    func warmUp(_ settings: AppSettings, mode: DictationMode? = nil) {
        guard !AppModel.isPreviewLaunch else { return }
        let request = mode.flatMap { RewriteRequest(mode: $0, language: settings.language) }
        guard mode == nil || request != nil else { return }
        switch settings.languageModel.engine {
        case .off:
            return
        case .builtIn:
            guard isReady(settings) else { return }
            unloadTask?.cancel()
            guard warmTask == nil else { return }
            let local = local
            builtInLoading = !builtInLoaded
            warmTask = Task {
                do {
                    // With a mode, its system prompt is processed now and cached for the rewrite.
                    try await local.warmUp(for: request)
                    builtInLoaded = true
                    builtInError = nil
                    memoryBytes = await local.residentBytes
                } catch is CancellationError {
                } catch {
                    Self.log.error("built-in model failed to load: \(error.localizedDescription, privacy: .public)")
                    builtInError = error.localizedDescription
                }
                builtInLoading = false
                warmTask = nil
                scheduleUnload()
            }
        case .ollama, .lmStudio:
            checkServer(settings, preload: true)
        }
    }

    // MARK: Rewrite

    /// The rewritten text, or `nil` when the engine is off, slow, failed or dropped content.
    func rewrite(_ text: String, mode: DictationMode, settings: AppSettings) async -> String? {
        guard !AppModel.isPreviewLaunch, isReady(settings),
              let request = RewriteRequest(mode: mode, language: settings.language)
        else { return nil }

        let engine = settings.languageModel.engine
        let timeout = settings.languageModel.timeoutSeconds
        let work: @Sendable () async throws -> RewriteGeneration
        switch engine {
        case .off:
            return nil
        case .builtIn:
            unloadTask?.cancel()
            let local = local
            work = { try await local.rewrite(text, request: request) }
        case .ollama, .lmStudio:
            let server = ServerRewriter(api: engine == .ollama ? .ollama : .openAI, url: Self.url(settings, engine), model: Self.modelName(settings, engine))
            preloadedAt[server.model] = Date()
            work = { try await server.rewrite(text, request: request, timeout: timeout + 5) }
        }

        let start = ContinuousClock.now
        let outcome = await Self.run(work, timeout: timeout)
        let seconds = Self.seconds(since: start)
        if engine == .builtIn {
            builtInLoaded = await local.isLoaded
            memoryBytes = await local.residentBytes
            scheduleUnload()
        }

        switch outcome {
        case .cancelled:
            return nil
        case .timedOut:
            Self.log.info("rewrite timed out after \(seconds, format: .fixed(precision: 2)) s")
            lastRun = LastRun(outcome: .timedOut, seconds: seconds, tokensPerSecond: 0)
            return nil
        case .failed(let message, let connection):
            Self.log.error("rewrite failed: \(message, privacy: .public)")
            lastRun = LastRun(outcome: .failed(message), seconds: seconds, tokensPerSecond: 0)
            if connection { markUnreachable(engine, settings: settings) }
            return nil
        case .finished(let generation):
            let cleaned = RewriteRequest.clean(generation.text, input: text)
            var verdict = RewriteValidator.check(original: text, candidate: cleaned, request: request, terms: Self.terms(settings))
            if generation.truncated { verdict = .rejected(.tooLong) }
            Self.log.info("rewrite \(String(describing: verdict), privacy: .public) in \(seconds, format: .fixed(precision: 2)) s, \(generation.generatedTokens) tokens, \(generation.cachedTokens)/\(generation.promptTokens) prompt tokens cached")
            switch verdict {
            case .accepted:
                lastRun = LastRun(outcome: .applied, seconds: seconds, tokensPerSecond: generation.tokensPerSecond)
                return cleaned
            case .rejected(let reason):
                lastRun = LastRun(outcome: .rejected(reason.description), seconds: seconds, tokensPerSecond: generation.tokensPerSecond)
                return nil
            }
        }
    }

    private enum Outcome: Sendable {
        case finished(RewriteGeneration)
        /// `connection` is true when the server could not be reached at all.
        case failed(String, connection: Bool)
        case timedOut
        case cancelled
    }

    /// The model's answer, or `.timedOut` once the limit passes, without waiting for the model
    /// to notice: MLX stops at the next token, a closed connection stops the servers, and a
    /// model still loading finishes loading for the next dictation.
    private nonisolated static func run(_ work: @escaping @Sendable () async throws -> RewriteGeneration, timeout: Double) async -> Outcome {
        let race = Race<Outcome>()
        let job = Task<Outcome, Never> {
            do {
                return .finished(try await work())
            } catch is CancellationError {
                return .cancelled
            } catch let error as URLError {
                let connection = [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet].contains(error.code)
                return error.code == .cancelled ? .cancelled : .failed(error.localizedDescription, connection: connection)
            } catch {
                return .failed(error.localizedDescription, connection: false)
            }
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.wait(continuation)
                let timer = Task {
                    try? await Task.sleep(for: .seconds(timeout))
                    guard !Task.isCancelled else { return }
                    job.cancel()
                    race.finish(.timedOut)
                }
                Task {
                    race.finish(await job.value)
                    timer.cancel()
                }
            }
        } onCancel: {
            job.cancel()
            race.finish(.cancelled)
        }
    }

    private nonisolated static func seconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    /// Spellings the rewrite must keep: the user's dictionary and the built-in terms.
    static func terms(_ settings: AppSettings) -> [String] {
        settings.dictionary.map(\.written) + PromptBuilder.builtInTerms + (settings.builtInDictionary ? builtInTerms : [])
    }

    private static let builtInTerms = BuiltInDictionary.terms.map(\.written)

    private func scheduleUnload() {
        unloadTask?.cancel()
        let local = local
        let idle = idleUnload
        unloadTask = Task { [weak self] in
            try? await Task.sleep(for: idle)
            guard !Task.isCancelled else { return }
            await local.unload()
            self?.builtInLoaded = false
            self?.memoryBytes = 0
        }
    }

    // MARK: Built-in model

    func downloadBuiltIn() {
        guard downloadProgress == nil, !AppModel.isPreviewLaunch else { return }
        downloadProgress = 0
        builtInError = nil
        let store = store
        downloadTask = Task {
            do {
                try await store.download { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.downloadProgress != nil else { return }
                        self.downloadProgress = fraction
                    }
                }
                builtInDownloaded = store.isDownloaded
                if !builtInDownloaded { builtInError = String(localized: "Download did not finish") }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                builtInError = error.localizedDescription
            }
            downloadProgress = nil
            downloadTask = nil
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func removeBuiltIn() {
        guard !AppModel.isPreviewLaunch else { return }
        downloadTask?.cancel()
        warmTask?.cancel()
        unloadTask?.cancel()
        let local = local
        let store = store
        Task {
            await local.unload()
            try? store.remove()
            builtInLoaded = false
            memoryBytes = 0
            builtInDownloaded = store.isDownloaded
            builtInError = nil
        }
    }

    // MARK: Servers

    /// Lists the server's models, which doubles as the health check. A check younger than
    /// `healthCacheSeconds` for the same address is reused unless `force` is set.
    func checkServer(_ settings: AppSettings, force: Bool = false, preload: Bool = false) {
        let engine = settings.languageModel.engine
        guard engine == .ollama || engine == .lmStudio, !AppModel.isPreviewLaunch else { return }
        let url = Self.url(settings, engine)
        let model = Self.modelName(settings, engine)
        let current = servers[engine]
        let fresh = current?.url == url && current?.phase == .connected
            && (current?.checkedAt.map { Date().timeIntervalSince($0) < healthCacheSeconds } ?? false)
        if fresh, !force {
            if preload { preloadIfNeeded(engine, url: url, model: model) }
            return
        }
        if checkTasks[engine] != nil, current?.url == url, !force { return }
        checkTasks[engine]?.cancel()
        var checking = current?.url == url ? current ?? ServerStatus() : ServerStatus()
        checking.url = url
        checking.phase = .checking
        servers[engine] = checking

        let server = ServerRewriter(api: engine == .ollama ? .ollama : .openAI, url: url, model: model)
        checkTasks[engine] = Task {
            var status = ServerStatus(url: url, checkedAt: Date())
            do {
                status.models = try await server.models()
                status.phase = .connected
            } catch is CancellationError {
                return
            } catch {
                status.phase = .unreachable(Self.describe(error))
            }
            guard !Task.isCancelled else { return }
            servers[engine] = status
            checkTasks[engine] = nil
            if preload, status.phase == .connected { preloadIfNeeded(engine, url: url, model: model) }
        }
    }

    /// Asks the server to load the model unless it answered for it in the last minutes.
    private func preloadIfNeeded(_ engine: Engine, url: String, model: String) {
        guard !model.isEmpty else { return }
        if let last = preloadedAt[model], Date().timeIntervalSince(last) < 300 { return }
        preloadedAt[model] = Date()
        let server = ServerRewriter(api: engine == .ollama ? .ollama : .openAI, url: url, model: model)
        Task.detached(priority: .utility) {
            try? await server.preload()
        }
    }

    /// A refused connection during a rewrite: the next dictation skips the server until it answers again.
    private func markUnreachable(_ engine: Engine, settings: AppSettings) {
        guard var status = servers[engine], status.url == Self.url(settings, engine) else { return }
        status.phase = .unreachable(String(localized: "not running", comment: "Language model server state"))
        servers[engine] = status
    }

    private static func describe(_ error: any Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost: return String(localized: "not running", comment: "Language model server state")
            case .timedOut: return String(localized: "no answer", comment: "Language model server state")
            default: break
            }
        }
        return error.localizedDescription
    }

    static func url(_ settings: AppSettings, _ engine: Engine) -> String {
        engine == .ollama ? settings.languageModel.ollamaURL : settings.languageModel.lmStudioURL
    }

    static func modelName(_ settings: AppSettings, _ engine: Engine) -> String {
        engine == .ollama ? settings.languageModel.ollamaModel : settings.languageModel.lmStudioModel
    }

    // MARK: Preview

    /// Screenshots of the settings: `--show-language-model builtIn:loaded`, `ollama`, `lmStudio:unreachable`.
    /// Nothing here touches the network or the model files.
    private func applyPreviewState(_ settings: SettingsStore) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "--show-language-model"), i + 1 < arguments.count else { return }
        let parts = arguments[i + 1].split(separator: ":").map(String.init)
        guard let engine = Engine(rawValue: parts[0]) else { return }
        let mock = parts.count > 1 ? parts[1] : "ready"
        settings.value.languageModel.engine = engine
        switch engine {
        case .off:
            break
        case .builtIn:
            builtInDownloaded = mock != "missing" && mock != "downloading"
            if mock == "downloading" { downloadProgress = 0.42 }
            if mock == "failed" { builtInError = "The network connection was lost." }
            if mock == "loaded" {
                builtInLoaded = true
                memoryBytes = 2_430_000_000
                lastRun = LastRun(outcome: .applied, seconds: 1.8, tokensPerSecond: 41)
            }
        case .ollama, .lmStudio:
            let models = engine == .ollama
                ? ["qwen3:4b-instruct-2507-q4_K_M", "gemma3:4b", "llama3.2:3b"]
                : ["qwen3-4b-instruct-2507", "google/gemma-3-4b"]
            if engine == .ollama { settings.value.languageModel.ollamaModel = models[0] } else { settings.value.languageModel.lmStudioModel = models[0] }
            let url = Self.url(settings.value, engine)
            servers[engine] = mock == "unreachable"
                ? ServerStatus(phase: .unreachable(String(localized: "not running", comment: "Language model server state")), url: url, checkedAt: Date())
                : ServerStatus(phase: .connected, models: models, url: url, checkedAt: Date())
        }
    }
}

/// Resumes a continuation once with whichever result comes first; later results are dropped.
private final class Race<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var result: Value?
    private var done = false

    func wait(_ continuation: CheckedContinuation<Value, Never>) {
        lock.lock()
        if let result {
            done = true
            lock.unlock()
            continuation.resume(returning: result)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func finish(_ value: Value) {
        lock.lock()
        guard !done, result == nil else {
            lock.unlock()
            return
        }
        if let continuation {
            done = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: value)
        } else {
            result = value
            lock.unlock()
        }
    }
}
