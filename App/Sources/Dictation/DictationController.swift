import AppKit
import Carbon.HIToolbox
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
        case inserted(TargetApp?)
        case card(String)
        case notice(Notice)
    }

    /// The app that had focus when recording started; the text goes there.
    struct TargetApp: Equatable {
        let name: String
        let bundleID: String?
        let icon: NSImage?
    }

    /// Short one-line messages; the overlay shows them without expanding.
    enum Notice: Equatable {
        case passwordField
        case modelMissing
        case modelFailed
        case microphoneUnavailable
        case recognitionFailed
        case nothingHeard
        case copied
        /// The mode shortcut picked a mode; the title of the mode or of automatic selection.
        case mode(String)
    }

    /// What the final pass is doing, for the overlay.
    enum FinishingStage: Equatable {
        case transcribing
        /// A language model rewrites or translates; esc inserts the text without it.
        case rewriting
    }

    enum ModelState: Equatable {
        case missing
        case downloading(Double)
        /// Core ML is compiling the model for this chip. The first time takes minutes.
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase = Phase.idle {
        didSet {
            // Anything but a card leaves no card to edit and no fresh entries to show.
            if case .card = phase {} else {
                cardEditing = false
                hideLearned()
            }
            updateCardShortcuts()
        }
    }
    /// ⌘C, V and esc act on the card from any app until the user types something else.
    private(set) var cardShortcutsActive = false
    /// The card is open for editing; while it is, the overlay takes keyboard focus.
    private(set) var cardEditing = false
    /// The card's text while it is being edited.
    var cardDraft = ""
    /// What the last edit taught the dictionary, for the readout under the card and its undo.
    private(set) var cardLearned: [DictionaryEntry] = []
    private(set) var modelState = ModelState.missing
    private(set) var handsFree = false
    private(set) var levels = [Float](repeating: 0, count: 28)
    private(set) var committedText = ""
    private(set) var pendingText = ""
    private(set) var startedAt: Date?
    private(set) var finishingStage = FinishingStage.transcribing
    /// The mode of the current or last dictation.
    private(set) var activeMode = DictationMode(id: DictationMode.standardID)
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
    @ObservationIgnored private var target: TargetApp?
    @ObservationIgnored private var silence = SilenceDetector(limit: 0)
    /// Resumes the final pass without the rewrite; set while the model runs.
    @ObservationIgnored private var skipRewriteAction: (() -> Void)?
    @ObservationIgnored private let store = ModelStore()
    /// Preview launches get a throwaway history file, so they can never show or change the real one.
    @ObservationIgnored private let historyStore = AppModel.isPreviewLaunch
        ? HistoryStore(url: FileManager.default.temporaryDirectory.appending(path: "saytype-preview-history-\(UUID().uuidString).json"))
        : HistoryStore()
    /// Optional local LLM that adds lists and paragraphs to long dictations.
    let smart = SmartStructureService()
    /// Optional local LLM for modes that rewrite or translate.
    let rewriter = RewriteService()
    /// Identifiers from the user's code folders.
    let projects: ProjectTermsService

    /// Live passes stop above this length; the final pass still covers everything.
    private let liveLimitSeconds = 30.0

    init(settings: SettingsStore) {
        self.settings = settings
        projects = ProjectTermsService(settings: settings)
        rewriter.attach(settings)
    }

    // MARK: Lifecycle

    func activate(listening: Bool = true) {
        if listening { startKeyMonitor() }
        projects.activate()
        if AppModel.isPreviewLaunch {
            // Previews draw a set-up app with sample data and never load a model.
            history = Self.sampleHistory()
            modelState = .ready
        } else {
            loadModelIfPresent()
            Task { history = await historyStore.all() }
        }
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
        if input == .escape, phase == .finishing, finishingStage == .rewriting {
            skipRewrite()
            return
        }
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
            show(.notice(.passwordField), for: 2)
            return
        }
        guard modelState == .ready || modelState == .loading else {
            show(.notice(modelState == .missing ? .modelMissing : .modelFailed), for: 2.5)
            return
        }
        if phase == .listening {
            // Double tap arrives while the first tap's recording is still running.
            self.handsFree = handsFree
            if handsFree { silence = SilenceDetector(limit: settings.value.autoStopSilenceSeconds) }
            return
        }
        target = Self.frontmostTarget()
        activeMode = settings.value.mode(for: target?.bundleID)
        silence = SilenceDetector(limit: handsFree ? settings.value.autoStopSilenceSeconds : 0)
        samples = []
        live = LiveAgreement()
        committedText = ""
        pendingText = ""
        levels = levels.map { _ in 0 }
        self.handsFree = handsFree
        startedAt = Date()
        capture.deviceUID = settings.value.microphoneUID
        do {
            let stream = try capture.start()
            captureTask = Task { [weak self] in
                for await chunk in stream {
                    self?.consume(chunk)
                }
            }
        } catch {
            show(.notice(.microphoneUnavailable), for: 2.5)
            return
        }
        phase = .listening
        finishingStage = .transcribing
        smart.warmUp(settings: settings.value.applying(activeMode))
        rewriter.warmUp(settings.value, mode: activeMode)
        if settings.value.sounds { Sounds.start() }
        runLiveLoop()
    }

    private func consume(_ chunk: AudioCapture.Chunk) {
        samples.append(contentsOf: chunk.samples)
        levels.removeFirst()
        levels.append(chunk.level)
        let seconds = Double(chunk.samples.count) / AudioCapture.sampleRate
        if handsFree, phase == .listening, silence.update(level: chunk.level, duration: seconds) {
            finishRecording()
        }
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
        let mode = activeMode
        let projectTerms = projects.terms
        let terms = DictionaryRewriter.promptTerms(entries: value.dictionary, projectTerms: projectTerms)
        // Whisper translates only when no language model will: the model keeps terms intact.
        // Turbo cannot translate at all; its modes stay in the spoken language without a model.
        let whisperTranslates = mode.translateToEnglish && !rewriter.isReady(value) && WhisperKitEngine.supportsTranslation(value.whisperModel)
        let hints = TranscriptionHints(
            language: value.language.whisperCode,
            prompt: PromptBuilder.prompt(glossary: terms),
            wordTimestamps: true,
            translate: whisperTranslates
        )
        let transcript: Transcript
        do {
            transcript = try await engine.transcribe(recorded, hints: hints)
        } catch {
            show(.notice(.recognitionFailed), for: 2.5)
            return
        }
        let style = value.applying(mode)
        let formatted = DictationPipeline.format(transcript, settings: value, mode: mode, projectTerms: projectTerms)
        var text = formatted.text
        if mode.usesLanguageModel || (mode.translateToEnglish && !whisperTranslates), !text.isEmpty, rewriter.isReady(value) {
            finishingStage = .rewriting
            if let rewritten = await rewriteSkippably(text, mode: mode, settings: value), !rewritten.isEmpty {
                text = rewritten
            }
            finishingStage = .transcribing
        } else {
            text = await smart.apply(to: text, settings: style)
        }
        if mode.backticks { text = Backticks.wrap(text, terms: projectTerms + value.dictionary.map(\.written)) }
        guard !text.isEmpty else {
            if formatted.send, style.outputMode == .paste {
                // Only "отправь": send what is already typed in the field.
                Paster.pressReturn()
                show(.inserted(target), for: 1.2)
            } else {
                show(.notice(.nothingHeard), for: 1.5)
            }
            handsFree = false
            return
        }
        let record = DictationRecord(text: text, raw: transcript.text, appName: target?.name, bundleID: target?.bundleID, duration: duration, date: Date())
        cardRecord = record
        history.insert(record, at: 0)
        let retention = value.historyRetentionDays
        Task { history = await historyStore.add(record, retentionDays: retention) }
        await deliver(text, settings: style, pressReturn: formatted.send || mode.pressReturn)
    }

    /// Esc while the model rewrites: insert the formatted text now.
    func skipRewrite() {
        skipRewriteAction?()
    }

    /// The rewrite, or `nil` as soon as the user skips it, even if the model keeps running.
    private func rewriteSkippably(_ text: String, mode: DictationMode, settings value: AppSettings) async -> String? {
        let rewriter = rewriter
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let race = FirstResult(continuation)
            let work = Task { await rewriter.rewrite(text, mode: mode, settings: value) }
            skipRewriteAction = {
                work.cancel()
                race.finish(nil)
            }
            Task { race.finish(await work.value) }
        }
        skipRewriteAction = nil
        return result
    }

    private func deliver(_ text: String, settings value: AppSettings, pressReturn modeReturn: Bool) async {
        switch value.outputMode {
        case .paste:
            let pressReturn = modeReturn || (target?.bundleID.map(value.autoEnterApps.contains) ?? false)
            switch await Paster.paste(text, pressReturn: pressReturn) {
            case .pasted:
                if value.sounds { Sounds.inserted() }
                show(.inserted(target), for: 1.2)
            case .secureField:
                show(.notice(.passwordField), for: 2)
            }
        case .card:
            hideTask?.cancel()
            phase = .card(text)
        case .clipboard:
            Paster.copy(text)
            show(.notice(.copied), for: 1.1)
        }
        handsFree = false
    }

    func dismissCard() {
        guard case .card = phase else { return }
        cardEditing = false
        phase = .idle
    }

    // MARK: Editing the card

    func beginCardEdit() {
        guard case .card(let text) = phase, !cardEditing else { return }
        cardDraft = text
        hideLearned()
        cardEditing = true
        // The keys of the card go to the text field now, not to the tap that swallows them.
        updateCardShortcuts()
    }

    func cancelCardEdit() {
        guard cardEditing else { return }
        cardEditing = false
        updateCardShortcuts()
    }

    /// Keeps the edited text and teaches the dictionary what was fixed.
    func commitCardEdit() {
        guard cardEditing, case .card(let text) = phase else { return }
        let edited = cardDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        cardEditing = false
        guard !edited.isEmpty, edited != text else {
            updateCardShortcuts()
            return
        }
        phase = .card(edited)
        guard let record = cardRecord else { return }
        cardRecord?.text = edited
        if let index = history.firstIndex(where: { $0.id == record.id }) { history[index].text = edited }
        Task { history = await historyStore.update(record.id, text: edited) }
        learn(from: record, edited: edited)
    }

    /// Dictionary entries for the spelling fixes in an edit, added to the user's dictionary.
    private func learn(from record: DictationRecord, edited: String) {
        guard settings.value.learnFromEdits else { return }
        let known = settings.value.dictionary.map(\.written)
            + projects.terms
            + (settings.value.builtInDictionary ? BuiltInDictionary.canonicalTerms : [])
        let corrections = EditLearning.corrections(raw: record.raw, text: record.text, edited: edited, knownTerms: known)
        guard !corrections.isEmpty else { return }
        var dictionary = settings.value.dictionary
        let before = dictionary
        var added: [DictionaryEntry] = []
        for entry in corrections where dictionary.addCorrection(entry) {
            added.append(entry)
        }
        guard !added.isEmpty else { return }
        settings.value.dictionary = dictionary
        dictionaryBeforeLearning = before
        cardLearned = added
        learnedHideTask?.cancel()
        learnedHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.hideLearned()
        }
    }

    /// Takes back what the last edit taught, dictionary and readout both.
    func undoLearned() {
        guard let before = dictionaryBeforeLearning else { return }
        settings.value.dictionary = before
        hideLearned()
    }

    private func hideLearned() {
        learnedHideTask?.cancel()
        learnedHideTask = nil
        dictionaryBeforeLearning = nil
        if !cardLearned.isEmpty { cardLearned = [] }
    }

    // MARK: Card shortcuts

    @ObservationIgnored private var cardKeys: KeyInterceptor?
    @ObservationIgnored private var cardKeysStop: Task<Void, Never>?
    /// The dictation the card holds: its raw transcript is what an edit learns from.
    @ObservationIgnored private var cardRecord: DictationRecord?
    /// The dictionary as it was before the last edit taught it anything, for the undo.
    @ObservationIgnored private var dictionaryBeforeLearning: [DictionaryEntry]?
    @ObservationIgnored private var learnedHideTask: Task<Void, Never>?

    private func updateCardShortcuts() {
        if case .card = phase, !cardEditing {
            cardKeysStop?.cancel()
            // Previews and snapshots must never swallow the user's keys.
            if cardKeys == nil, !AppModel.isPreviewLaunch {
                let keys = KeyInterceptor { [weak self] press in
                    self?.handleCardKey(press) ?? false
                }
                // Swallowing keys needs Accessibility; without it the buttons still work.
                if keys.start() { cardKeys = keys }
            }
            cardShortcutsActive = cardKeys != nil
        } else if cardKeys != nil {
            cardShortcutsActive = false
            // Keep the tap a moment longer so the key-up of V or C is swallowed too.
            cardKeysStop?.cancel()
            cardKeysStop = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !Task.isCancelled else { return }
                if case .card = self.phase { return }
                self.cardKeys?.stop()
                self.cardKeys = nil
            }
        }
    }

    private func handleCardKey(_ press: KeyInterceptor.Press) -> Bool {
        guard case .card = phase, cardShortcutsActive else { return false }
        switch Int(press.keyCode) {
        case kVK_ANSI_C where press.command && !press.option && !press.control:
            copyCard()
            return true
        case kVK_ANSI_V where !press.hasModifiers:
            if !press.isRepeat { insertCard() }
            return true
        case kVK_ANSI_E where !press.hasModifiers:
            if !press.isRepeat { beginCardEdit() }
            return true
        case kVK_Escape where !press.hasModifiers:
            dismissCard()
            return true
        default:
            // Typing in the focused app: leave the card up but stop taking its keys.
            cardShortcutsActive = false
            return false
        }
    }

    func copyCard() {
        if case .card(let text) = phase {
            Paster.copy(text)
            show(.notice(.copied), for: 1.1)
        }
    }

    /// Pastes the card's text into the app that was focused when recording started.
    func insertCard() {
        guard case .card(let text) = phase else { return }
        // Leave the card state first, so a second press can't paste twice.
        hideTask?.cancel()
        phase = .idle
        Task {
            switch await Paster.paste(text) {
            case .pasted: show(.inserted(target), for: 1.2)
            case .secureField: show(.notice(.passwordField), for: 2)
            }
        }
    }

    // MARK: Modes

    /// The mode a dictation would use right now, for the panel and the menu.
    func currentMode() -> DictationMode {
        if phase == .listening || phase == .finishing { return activeMode }
        return settings.value.mode(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    /// The mode shortcut: automatic, then each mode by hand.
    func cycleMode() {
        settings.value.cycleMode()
        guard phase == .idle || isTransient else { return }
        let value = settings.value
        let title = value.fixedModeID.flatMap { id in value.modes.first { $0.id == id }?.title } ?? DictationMode.automaticTitle
        show(.notice(.mode(title)), for: 1.4)
    }

    // MARK: Overlay controls

    /// A click on the record button: hands-free recording, stopped by the stop button or the key.
    func toggleRecordingFromOverlay() {
        if phase == .listening {
            finishRecording()
        } else if phase == .idle || isTransient {
            startRecording(handsFree: true)
        }
    }

    func cancelFromOverlay() {
        guard phase == .listening else { return }
        cancelRecording()
    }

    /// Voice level of the latest audio chunk, 0…1.
    var currentLevel: Float { levels.last ?? 0 }

    var lastRecord: DictationRecord? { history.first }

    private var isTransient: Bool {
        switch phase {
        case .inserted, .notice: true
        default: false
        }
    }

    private static func frontmostTarget() -> TargetApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return TargetApp(name: app.localizedName ?? "", bundleID: app.bundleIdentifier, icon: app.icon)
    }

    func demoSet(phase: Phase, committed: String, pending: String) {
        self.phase = phase
        committedText = committed
        pendingText = pending
        if startedAt == nil { startedAt = Date() }
    }

    func demoCardShortcuts() {
        cardShortcutsActive = true
    }

    func demoCardEdit(_ draft: String?) {
        cardEditing = draft != nil
        cardDraft = draft ?? ""
    }

    func demoLearned(_ entries: [DictionaryEntry]) {
        cardLearned = entries
    }

    func demoModelReady() {
        modelState = .ready
    }

    func demoHistory(_ records: [DictationRecord]) {
        history = records
    }

    func demoLevels() {
        levels = levels.map { _ in Float.random(in: 0.15...0.9) }
    }

    func demoMode(_ mode: DictationMode, stage: FinishingStage = .transcribing, handsFree: Bool = false) {
        activeMode = mode
        finishingStage = stage
        self.handsFree = handsFree
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


enum Sounds {
    static func start() { play("Tink") }
    static func inserted() { play("Pop") }

    private static func play(_ name: String) {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = 0.25
        sound.play()
    }
}

/// Resumes a continuation once, with whichever result arrives first.
@MainActor
private final class FirstResult<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
