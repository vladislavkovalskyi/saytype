import AppKit
import Observation
import VMAudio
import VMCore
import VMSystem
import VMTranscription

/// Runs one dictation at a time: record key → microphone → live text → final
/// pass → delivery into the focused app.
@MainActor
@Observable
final class DictationController {
    enum Phase: Equatable {
        case idle
        case listening
        case finishing
        case inserted(appName: String?)
        case card(String)
        case notice(String)
    }

    enum ModelState: Equatable {
        case missing
        case downloading(Double)
        /// Core ML is compiling the model for this chip. The first time takes minutes.
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase = Phase.idle
    private(set) var modelState = ModelState.missing
    private(set) var handsFree = false
    private(set) var levels = [Float](repeating: 0, count: 28)
    private(set) var committedText = ""
    private(set) var pendingText = ""
    private(set) var startedAt: Date?
    private(set) var history: [DictationRecord] = []
    var stats: HistoryStats { HistoryStats(records: history) }
    private(set) var keyMonitorActive = false

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var gesture = RecordKeyGesture()
    @ObservationIgnored private var monitor: RecordKeyMonitor?
    @ObservationIgnored private let capture = AudioCapture()
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var samples: [Float] = []
    @ObservationIgnored private var live = LiveAgreement()
    @ObservationIgnored private var engine: WhisperKitEngine?
    @ObservationIgnored private var engineVariant: String?
    @ObservationIgnored private var targetBundleID: String?
    @ObservationIgnored private var targetAppName: String?
    @ObservationIgnored private let store = ModelStore()
    @ObservationIgnored private let historyStore = HistoryStore()
    /// Optional local LLM that adds lists and paragraphs to long dictations.
    let smart = SmartStructureService()

    /// Live passes stop above this length; the final pass still covers everything.
    private let liveLimitSeconds = 30.0

    init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: Lifecycle

    func activate() {
        startKeyMonitor()
        loadModelIfPresent()
        Task { history = await historyStore.all() }
    }

    var isModelDownloaded: Bool { store.isDownloaded(settings.value.whisperModel) }

    /// Downloads the selected model, then loads it.
    func downloadModel() {
        if case .downloading = modelState { return }
        let variant = settings.value.whisperModel
        modelState = .downloading(0)
        let store = store
        Task {
            do {
                _ = try await store.download(variant) { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.modelState else { return }
                        self.modelState = .downloading(fraction)
                    }
                }
                modelState = .missing
                loadModelIfPresent()
            } catch {
                modelState = .failed(error.localizedDescription)
            }
        }
    }

    func removeFromHistory(_ id: UUID) {
        Task { history = await historyStore.remove(id) }
    }

    func clearHistory() {
        Task {
            await historyStore.clear()
            history = []
        }
    }

    /// Pastes a past dictation again into the focused app.
    func insertAgain(_ record: DictationRecord) {
        Task { _ = await Paster.paste(record.text) }
    }

    func startKeyMonitor() {
        gesture.handsFreeEnabled = settings.value.doubleTapHandsFree
        guard Permissions.state(of: .inputMonitoring) == .granted else {
            keyMonitorActive = false
            return
        }
        let monitor = RecordKeyMonitor(key: settings.value.recordKey) { [weak self] input in
            self?.handle(input)
        }
        keyMonitorActive = monitor.start()
        self.monitor = monitor
    }

    func loadModelIfPresent() {
        let variant = settings.value.whisperModel
        guard store.isDownloaded(variant) else {
            modelState = .missing
            return
        }
        if engineVariant != variant {
            // Switching models: the old engine's state says nothing about the new one.
            if let old = engine { Task { await old.unload() } }
            engine = WhisperKitEngine(store: store, variant: variant)
            engineVariant = variant
            modelState = .missing
        }
        guard let engine, modelState != .ready, modelState != .loading else { return }
        modelState = .loading
        Task {
            do {
                try await engine.prepare()
                guard engineVariant == variant else { return }
                modelState = .ready
            } catch {
                guard engineVariant == variant else { return }
                modelState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Record key

    func handle(_ input: RecordKeyGesture.Input) {
        guard let command = gesture.handle(input) else { return }
        switch command {
        case .startRecording: startRecording(handsFree: false)
        case .startHandsFree: startRecording(handsFree: true)
        case .finishRecording: finishRecording()
        case .cancelRecording: cancelRecording()
        }
    }

    private func startRecording(handsFree: Bool) {
        hideTask?.cancel()
        if FocusInspector.isSecureFieldFocused() {
            show(.notice("Поле пароля"), for: 2)
            return
        }
        guard modelState == .ready || modelState == .loading else {
            show(.notice(modelState == .missing ? "Модель не скачана" : "Модель не загрузилась"), for: 2.5)
            return
        }
        if phase == .listening {
            // Double tap arrives while the first tap's recording is still running.
            self.handsFree = handsFree
            return
        }
        targetBundleID = FocusInspector.frontmostBundleID()
        targetAppName = FocusInspector.frontmostAppName()
        samples = []
        live = LiveAgreement()
        committedText = ""
        pendingText = ""
        levels = levels.map { _ in 0 }
        self.handsFree = handsFree
        startedAt = Date()
        do {
            let stream = try capture.start()
            captureTask = Task { [weak self] in
                for await chunk in stream {
                    self?.consume(chunk)
                }
            }
        } catch {
            show(.notice("Микрофон недоступен"), for: 2.5)
            return
        }
        phase = .listening
        smart.warmUp(settings: settings.value)
        if settings.value.sounds { Sounds.start() }
        runLiveLoop()
    }

    private func consume(_ chunk: AudioCapture.Chunk) {
        samples.append(contentsOf: chunk.samples)
        levels.removeFirst()
        levels.append(chunk.level)
    }

    private func runLiveLoop() {
        liveTask?.cancel()
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, self.phase == .listening, let engine = self.engine, self.modelState == .ready else { continue }
                let snapshot = self.samples
                let seconds = Double(snapshot.count) / AudioCapture.sampleRate
                guard seconds >= 0.8, seconds <= self.liveLimitSeconds else { continue }
                let language = self.settings.value.language.whisperCode
                guard let transcript = try? await engine.transcribe(snapshot, hints: TranscriptionHints(language: language, prompt: nil, wordTimestamps: false)) else { continue }
                guard self.phase == .listening, !Task.isCancelled else { return }
                self.live.update(with: transcript.text)
                self.committedText = self.live.committedText
                self.pendingText = self.live.pendingText
            }
        }
    }

    private func cancelRecording() {
        stopCapture()
        phase = .idle
        handsFree = false
    }

    private func finishRecording() {
        guard phase == .listening else { return }
        stopCapture()
        let recorded = samples
        let duration = Double(recorded.count) / AudioCapture.sampleRate
        guard duration >= 0.4, let engine else {
            phase = .idle
            return
        }
        phase = .finishing
        Task {
            await finalize(recorded, duration: duration, engine: engine)
        }
    }

    private func stopCapture() {
        liveTask?.cancel()
        liveTask = nil
        capture.stop()
        captureTask?.cancel()
        captureTask = nil
    }

    // MARK: Final pass and delivery

    private func finalize(_ recorded: [Float], duration: Double, engine: WhisperKitEngine) async {
        let value = settings.value
        let terms = DictionaryRewriter.promptTerms(entries: value.dictionary)
        let hints = TranscriptionHints(language: value.language.whisperCode, prompt: PromptBuilder.prompt(glossary: terms), wordTimestamps: true)
        let transcript: Transcript
        do {
            transcript = try await engine.transcribe(recorded, hints: hints)
        } catch {
            show(.notice("Не удалось распознать"), for: 2.5)
            return
        }
        let formatted = TextPipeline(settings: value).format(transcript)
        let text = await smart.apply(to: formatted, settings: value)
        guard !text.isEmpty else {
            show(.notice("Ничего не слышно"), for: 1.5)
            return
        }
        let record = DictationRecord(text: text, raw: transcript.text, appName: targetAppName, bundleID: targetBundleID, duration: duration, date: Date())
        history.insert(record, at: 0)
        let retention = value.historyRetentionDays
        Task { history = await historyStore.add(record, retentionDays: retention) }
        await deliver(text, settings: value)
    }

    private func deliver(_ text: String, settings value: AppSettings) async {
        switch value.outputMode {
        case .paste:
            let pressReturn = targetBundleID.map(value.autoEnterApps.contains) ?? false
            switch await Paster.paste(text, pressReturn: pressReturn) {
            case .pasted:
                if value.sounds { Sounds.inserted() }
                show(.inserted(appName: targetAppName), for: 1.1)
            case .secureField:
                show(.notice("Поле пароля"), for: 2)
            }
        case .card:
            hideTask?.cancel()
            phase = .card(text)
        case .clipboard:
            Paster.copy(text)
            show(.notice("Скопировано"), for: 1.1)
        }
        handsFree = false
    }

    func dismissCard() {
        if case .card = phase { phase = .idle }
    }

    func copyCard() {
        if case .card(let text) = phase {
            Paster.copy(text)
            show(.notice("Скопировано"), for: 1.1)
        }
    }

    func demoSet(phase: Phase, committed: String, pending: String) {
        self.phase = phase
        committedText = committed
        pendingText = pending
        if startedAt == nil { startedAt = Date() }
    }

    func demoHistory(_ records: [DictationRecord]) {
        history = records
    }

    func demoLevels() {
        levels = levels.map { _ in Float.random(in: 0.15...0.9) }
    }

    private func show(_ phase: Phase, for seconds: Double) {
        hideTask?.cancel()
        self.phase = phase
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.phase == phase else { return }
            self.phase = .idle
        }
    }
}

extension AppSettings.SpeechLanguage {
    var whisperCode: String? {
        switch self {
        case .russian: "ru"
        case .english: "en"
        case .auto: nil
        }
    }
}

enum Sounds {
    static func start() { play("Tink") }
    static func inserted() { play("Pop") }

    private static func play(_ name: String) {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = 0.25
        sound.play()
    }
}
