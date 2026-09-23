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
        /// The Edit selection shortcut found nothing selected in the app in front.
        case nothingSelected
        /// The Edit selection shortcut needs a language model and there is none.
        case modelOff
        /// The model did not answer, or answered with nothing; the selection is untouched.
        case editFailed
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
    /// Every entry of the history, newest first, recordings still without text included. Only the
    /// History section lists those; set by the controller and its audio extension only.
    var records: [DictationRecord] = []
    /// Finished dictations, newest first: what Home, the menus, the shortcuts and the stats see.
    var history: [DictationRecord] { records.filter(\.isTranscribed) }
    var stats: HistoryStats { HistoryStats(records: history) }
    private(set) var keyMonitorActive = false
    /// The re-transcription running now, for the History section and the card.
    var retranscription: Retranscription?
    /// Plays kept recordings, one at a time.
    let player = RecordingPlayer()

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored private var gesture = RecordKeyGesture()
    @ObservationIgnored private var monitor: RecordKeyMonitor?
    @ObservationIgnored private let capture = AudioCapture()
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    /// The stop in flight: the tail grace, then the drain of the capture. The record key does
    /// nothing until it is done, so a press can't start a recording over the one being stopped.
    @ObservationIgnored private var stopping: Task<Void, Never>?
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var samples: [Float] = []
    @ObservationIgnored private var live = LiveAgreement()
    @ObservationIgnored private(set) var engine: WhisperKitEngine?
    @ObservationIgnored private(set) var engineVariant: String?
    @ObservationIgnored private(set) var target: TargetApp?
    /// The text selected in another app: this dictation is an instruction over it, not text.
    @ObservationIgnored private(set) var selection: String?
    @ObservationIgnored private var silence = SilenceDetector(limit: 0)
    /// Resumes the final pass without the rewrite; set while the model runs.
    @ObservationIgnored private var skipRewriteAction: (() -> Void)?
    /// The last run of the model ended because the user pressed esc, not because it failed.
    @ObservationIgnored private var skippedRewrite = false
    @ObservationIgnored let store = ModelStore()
    /// Preview launches get a throwaway history file, so they can never show or change the real one.
    @ObservationIgnored let historyStore = AppModel.isPreviewLaunch
        ? HistoryStore(url: FileManager.default.temporaryDirectory.appending(path: "saytype-preview-history-\(UUID().uuidString).json"))
        : HistoryStore()
    /// Recordings of recent dictations; a throwaway folder for preview launches, like the history.
    @ObservationIgnored let archive = AppModel.isPreviewLaunch
        ? RecordingArchive(folder: FileManager.default.temporaryDirectory.appending(path: "saytype-preview-audio-\(UUID().uuidString)", directoryHint: .isDirectory))
        : RecordingArchive()
    /// The recording being written while the microphone runs.
    @ObservationIgnored var recording: RecordingWriter?
    /// Recordings whose final pass runs now: no record points to them yet, and no cleanup may take them.
    @ObservationIgnored var closingAudio: Set<UUID> = []
    @ObservationIgnored var audioSweepTask: Task<Void, Never>?
    /// Optional local LLM that adds lists and paragraphs to long dictations.
    let smart = SmartStructureService()
    /// Optional local LLM for modes that rewrite or translate.
    let rewriter = RewriteService()
    /// Identifiers from the user's code folders.
    let projects: ProjectTermsService

    /// Live passes stop above this length; the final pass still covers everything.
    private let liveLimitSeconds = 30.0
    /// How long the microphone keeps recording after the key is released. The last word is
    /// usually still being said, and the last buffers are still on their way from the device.
    private let tailGrace = Duration.milliseconds(250)

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
            records = Self.sampleHistory()
            modelState = .ready
        } else {
            loadModelIfPresent()
            Task {
                records = await historyStore.all()
                // Recordings a crash left behind become entries before the first cleanup runs.
                await recoverRecordings()
            }
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
        if player.recordID == id { player.stop() }
        Task {
            records = await historyStore.remove(id)
            archive.delete([id])
        }
    }

    func clearHistory() {
        player.stop()
        Task {
            await historyStore.clear()
            records = []
            // Every file is a stray now, except the recording being made.
            await sweepAudio()
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

    private func startRecording(handsFree: Bool, selection: String? = nil) {
        guard stopping == nil else { return }
        hideTask?.cancel()
        self.selection = selection
        // The next card is a new dictation's; the old one must not be what an edit learns from.
        cardRecord = nil
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
        beginRecordingAudio()
        phase = .listening
        finishingStage = .transcribing
        smart.warmUp(settings: settings.value.applying(activeMode))
        rewriter.warmUp(settings.value, mode: selection == nil ? activeMode : nil, translateTo: settings.value.autoTranslate ? settings.value.translateTarget : nil)
        if settings.value.sounds { Sounds.start() }
        runLiveLoop()
    }

    private func consume(_ chunk: AudioCapture.Chunk) {
        samples.append(contentsOf: chunk.samples)
        recording?.append(chunk.samples)
        levels.removeFirst()
        levels.append(chunk.level)
        let seconds = Double(chunk.samples.count) / AudioCapture.sampleRate
        if handsFree, phase == .listening, silence.update(level: chunk.level, duration: seconds) {
            // The silence that ended it is already recorded.
            finishRecording(grace: false)
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
                guard let transcript = try? await engine.transcribe(snapshot, hints: TranscriptionHints(language: language)) else { continue }
                guard self.phase == .listening, !Task.isCancelled else { return }
                self.live.update(with: transcript.text)
                self.committedText = self.live.committedText
                self.pendingText = self.live.pendingText
            }
        }
    }

    private func cancelRecording() {
        // Nothing to cancel when the press started nothing, e.g. one made while a stop was in
        // flight: its quick release must not reset the dictation being finished.
        guard phase == .listening else { return }
        stopCapture()
        discardRecordingAudio()
        selection = nil
        phase = .idle
        handsFree = false
    }

    /// Ends the recording: after the tail grace the capture stops, every chunk it delivered is
    /// collected, and the recording goes to the voice gate and the final pass.
    private func finishRecording(grace: Bool = true) {
        guard phase == .listening, stopping == nil else { return }
        liveTask?.cancel()
        liveTask = nil
        phase = .finishing
        stopping = Task { [weak self, tailGrace] in
            if grace { try? await Task.sleep(for: tailGrace) }
            guard let self else { return }
            let recorded = await self.drainCapture()
            // Every chunk is in the file's queue now; the next recording may start any moment.
            let audio = self.closeRecordingAudio()
            self.stopping = nil
            await self.transcribe(recorded, audio: audio)
        }
    }

    /// Stops the microphone and waits until the stream has handed over what it buffered.
    private func drainCapture() async -> [Float] {
        capture.stop()
        await captureTask?.value
        captureTask = nil
        return samples
    }

    /// The key gesture has already dropped holds shorter than a tap; what gets here is a
    /// dictation unless there is no voice in it. `audio` is the id of its kept recording.
    private func transcribe(_ recorded: [Float], audio: UUID?) async {
        // By the end the recording has its record, or it has none and the next cleanup takes it.
        defer { if let audio { closingAudio.remove(audio) } }
        guard !recorded.isEmpty, let engine else {
            phase = .idle
            return
        }
        let duration = Double(recorded.count) / AudioCapture.sampleRate
        guard VoiceGate.hasVoice(recorded, sampleRate: AudioCapture.sampleRate) else {
            selection = nil
            handsFree = false
            keepUntranscribed(audio, duration: duration, failure: .nothingHeard)
            show(.notice(.nothingHeard), for: 1.5)
            return
        }
        await finalize(recorded, duration: duration, engine: engine, audio: audio)
    }

    private func stopCapture() {
        liveTask?.cancel()
        liveTask = nil
        capture.stop()
        captureTask?.cancel()
        captureTask = nil
    }

    // MARK: Final pass and delivery

    /// What recognition and formatting made of one recording, before it goes anywhere.
    struct PassResult {
        /// Formatted and, where the mode asks, rewritten or translated.
        var text: String
        /// What Whisper heard.
        var raw: String
        /// "отправь" was said: Return goes after the text.
        var send: Bool
    }

    /// Recognition and formatting of one recording: Whisper with the glossary, the formatting
    /// pipeline, then the language model or smart structure, then backticks. It delivers nothing,
    /// saves nothing and reads only its arguments, so a live dictation and a re-transcription of a
    /// kept recording share it.
    /// - Parameters:
    ///   - instruction: the dictation is a spoken instruction over a selection; formatting is the
    ///     last step, the language model runs on the selection afterwards.
    ///   - skippable: esc skips the language model and the formatted text is used (live only).
    ///   - stage: told when the language model starts and ends.
    func recognize(_ recorded: [Float], engine: WhisperKitEngine, settings value: AppSettings, mode: DictationMode, instruction: Bool = false, skippable: Bool, stage: (FinishingStage) -> Void) async throws -> PassResult {
        let projectTerms = projects.terms
        let terms = DictionaryRewriter.promptTerms(entries: value.dictionary, projectTerms: projectTerms)
        // Whisper translates only when no language model will: the model keeps terms intact.
        // Turbo cannot translate at all; its modes stay in the spoken language without a model.
        // The overlay's switch translates everything; without it the mode decides.
        let translateTo = translationTarget(mode: mode, settings: value)
        let whisperTranslates = !instruction && translateTo == .english && !rewriter.isReady(value) && WhisperKitEngine.supportsTranslation(value.whisperModel)
        let hints = TranscriptionHints(
            language: value.language.whisperCode,
            glossary: terms,
            translate: whisperTranslates
        )
        let transcript = try await engine.transcribe(recorded, hints: hints)
        let style = value.applying(mode)
        let formatted = DictationPipeline.format(transcript, settings: value, mode: mode, projectTerms: projectTerms)
        var text = formatted.text
        guard !instruction else { return PassResult(text: text, raw: transcript.text, send: formatted.send) }
        if mode.usesLanguageModel || (translateTo != nil && !whisperTranslates), !text.isEmpty, rewriter.isReady(value) {
            stage(.rewriting)
            let rewritten = skippable
                ? await rewriteSkippably(text, mode: mode, settings: value)
                : await rewriter.rewrite(text, mode: mode, target: value.autoTranslate ? value.translateTarget : nil, settings: value)
            if let rewritten, !rewritten.isEmpty {
                text = rewritten
            }
            stage(.transcribing)
        } else {
            text = await smart.apply(to: text, settings: style)
        }
        if mode.backticks { text = Backticks.wrap(text, terms: projectTerms + value.dictionary.map(\.written)) }
        return PassResult(text: text, raw: transcript.text, send: formatted.send)
    }

    /// A live dictation's final pass: recognition and formatting, then the edit of a selection, or
    /// the history record and the delivery into the app. `audio` is the id of its kept recording.
    private func finalize(_ recorded: [Float], duration: Double, engine: WhisperKitEngine, audio: UUID?) async {
        let value = settings.value
        let mode = activeMode
        let result: PassResult
        do {
            result = try await recognize(recorded, engine: engine, settings: value, mode: mode, instruction: selection != nil, skippable: true) { finishingStage = $0 }
        } catch {
            keepUntranscribed(audio, duration: duration, failure: .recognitionFailed)
            show(.notice(.recognitionFailed), for: 2.5)
            return
        }
        let style = value.applying(mode)
        if let selection {
            await editSelection(selection, instruction: result.text, settings: value, style: style)
            return
        }
        guard !result.text.isEmpty else {
            if result.send, style.outputMode == .paste {
                // Only "отправь": send what is already typed in the field.
                Paster.pressReturn()
                show(.inserted(target), for: 1.2)
            } else {
                keepUntranscribed(audio, duration: duration, failure: .nothingHeard)
                show(.notice(.nothingHeard), for: 1.5)
            }
            handsFree = false
            return
        }
        let record = DictationRecord(id: audio ?? UUID(), text: result.text, raw: result.raw, appName: target?.name, bundleID: target?.bundleID, duration: duration, date: Date(), audio: audio.map(RecordingArchive.fileName(for:)), modeID: mode.id)
        cardRecord = record
        records.insert(record, at: 0)
        let retention = value.historyRetentionDays
        Task {
            records = await historyStore.add(record, retentionDays: retention)
            await sweepAudio()
        }
        await deliver(result.text, settings: style, pressReturn: result.send || mode.pressReturn)
    }

    /// What the overlay's tag says while recording: the selection job, or a mode that is not the
    /// standard one. `nil` leaves the tag out.
    var recordingTag: String? {
        if selection != nil { return String(localized: "Selection", comment: "Overlay tag: this dictation edits the text selected in another app") }
        return activeMode.isStandard ? nil : activeMode.title
    }

    // MARK: Translation

    /// Where this dictation is translated to, or `nil` when it is not translated. The overlay's
    /// switch covers every mode; without it only a mode that asks for English translates.
    func translationTarget(mode: DictationMode, settings value: AppSettings) -> AppSettings.SpeechLanguage? {
        if value.autoTranslate { return value.translateTarget }
        return mode.translateToEnglish ? .english : nil
    }

    /// Something can translate right now: the language model, or Whisper itself into English.
    /// Whisper's own translation only works into English and only on the large-v3 models.
    var canTranslate: Bool {
        if rewriter.isReady(settings.value) { return true }
        return settings.value.translateTarget == .english && WhisperKitEngine.supportsTranslation(settings.value.whisperModel)
    }

    /// The overlay reserves room for the rewrite stage when a model is going to run.
    var expectsRewrite: Bool {
        activeMode.usesLanguageModel || activeMode.translateToEnglish || settings.value.autoTranslate || finishingStage == .rewriting
    }

    // MARK: Editing a selection

    /// The Edit selection shortcut: reads what is selected in the app in front, then records the
    /// instruction. A second press ends the recording, esc cancels it.
    func editSelection() {
        if phase == .listening {
            finishRecording()
            return
        }
        guard phase == .idle || isTransient else { return }
        guard rewriter.isReady(settings.value) else {
            show(.notice(.modelOff), for: 2.5)
            return
        }
        Task {
            guard let text = await SelectionReader.read() else {
                show(.notice(.nothingSelected), for: 2)
                return
            }
            startRecording(handsFree: true, selection: text)
        }
    }

    /// Esc while the model rewrites: insert the formatted text now.
    func skipRewrite() {
        skipRewriteAction?()
    }

    /// The rewrite, or `nil` as soon as the user skips it, even if the model keeps running.
    private func rewriteSkippably(_ text: String, mode: DictationMode, settings value: AppSettings) async -> String? {
        let rewriter = rewriter
        let target = value.autoTranslate ? value.translateTarget : nil
        return await skippable { await rewriter.rewrite(text, mode: mode, target: target, settings: value) }
    }

    /// Runs the model with esc as a way out: the result, or `nil` as soon as the user presses it.
    private func skippable(_ body: @escaping () async -> String?) async -> String? {
        skippedRewrite = false
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let race = FirstResult(continuation)
            let work = Task { await body() }
            skipRewriteAction = { [weak self] in
                self?.skippedRewrite = true
                work.cancel()
                race.finish(nil)
            }
            Task { race.finish(await work.value) }
        }
        skipRewriteAction = nil
        return result
    }

    /// The spoken instruction over the selected text: the model edits the fragment and the
    /// result goes back the usual way, over the selection it came from.
    private func editSelection(_ selection: String, instruction: String, settings value: AppSettings, style: AppSettings) async {
        // The overlay's tag reads this until the edit is delivered; a new recording clears it.
        defer { self.selection = nil }
        guard !instruction.isEmpty else {
            show(.notice(.nothingHeard), for: 1.5)
            handsFree = false
            return
        }
        finishingStage = .rewriting
        let rewriter = rewriter
        let edited = await skippable { await rewriter.editSelection(selection, instruction: instruction, settings: value) }
        finishingStage = .transcribing
        handsFree = false
        // Esc during the rewrite: the user wanted out, and the selection stays as it was.
        guard !skippedRewrite else {
            phase = .idle
            return
        }
        guard let edited, !edited.isEmpty else {
            show(.notice(.editFailed), for: 2.5)
            return
        }
        await deliver(edited, settings: style, pressReturn: false)
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

    /// The history entry of the dictation on the card, for its audio controls.
    var cardHistoryRecord: DictationRecord? {
        guard case .card = phase, let id = cardRecord?.id else { return nil }
        return records.first { $0.id == id }
    }

    /// A re-transcription replaced the text of the dictation the card shows.
    func cardRecordChanged(_ record: DictationRecord) {
        guard cardRecord?.id == record.id, case .card = phase, !cardEditing else { return }
        cardRecord = record
        phase = .card(record.text)
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
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index].text = edited }
        Task { records = await historyStore.update(record.id, text: edited) }
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
        dictionaryAfterLearning = dictionary
        cardLearned = added
        learnedHideTask?.cancel()
        learnedHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.hideLearned()
        }
    }

    /// Takes back what the last edit taught, dictionary and readout both. A dictionary the user
    /// has changed in the meantime is left alone.
    func undoLearned() {
        if let before = dictionaryBeforeLearning, settings.value.dictionary == dictionaryAfterLearning {
            settings.value.dictionary = before
        }
        hideLearned()
    }

    private func hideLearned() {
        learnedHideTask?.cancel()
        learnedHideTask = nil
        dictionaryBeforeLearning = nil
        dictionaryAfterLearning = nil
        if !cardLearned.isEmpty { cardLearned = [] }
    }

    // MARK: Card shortcuts

    @ObservationIgnored private var cardKeys: KeyInterceptor?
    @ObservationIgnored private var cardKeysStop: Task<Void, Never>?
    /// The dictation the card holds: its raw transcript is what an edit learns from.
    @ObservationIgnored private var cardRecord: DictationRecord?
    /// The dictionary as it was before the last edit taught it anything, for the undo.
    @ObservationIgnored private var dictionaryBeforeLearning: [DictionaryEntry]?
    @ObservationIgnored private var dictionaryAfterLearning: [DictionaryEntry]?
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
                if case .card = self.phase, !self.cardEditing { return }
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

    var lastRecord: DictationRecord? { records.first(where: \.isTranscribed) }

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
        self.records = records
    }

    /// The dictation the card shows, for snapshots of its audio controls.
    func demoCardRecord(_ record: DictationRecord?) {
        cardRecord = record
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
