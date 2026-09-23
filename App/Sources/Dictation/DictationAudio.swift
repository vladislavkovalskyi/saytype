import Foundation
import VMAudio
import VMCore
import VMTranscription

/// A re-transcription of a kept recording, while it runs and for a moment after it failed.
struct Retranscription: Equatable {
    enum State: Equatable {
        /// Another Whisper model is loading; its name is shown.
        case loading(String)
        case transcribing
        case rewriting
        /// Ended without new text; the record stays as it was.
        case failed(Failure)
    }

    enum Failure: Equatable {
        case nothingHeard
        case recognitionFailed
        case modelFailed
        case modelNotReady
        case audioMissing
    }

    let recordID: UUID
    var state: State

    var isRunning: Bool {
        if case .failed = state { return false }
        return true
    }
}

/// What a re-transcription changes against the current settings.
enum RetranscriptionChange: Equatable {
    case none
    case model(String)
    case language(AppSettings.SpeechLanguage)
    case withoutTranslation
}

/// Kept recordings: writing them while the key is held, cleanup, recovery after a crash, and
/// re-transcription through the shared final pass.
extension DictationController {
    // MARK: Writing

    /// Opens the file for the recording that just started, unless audio is off or the dictation
    /// is an instruction over a selection, which leaves no history record.
    func beginRecordingAudio() {
        recording = nil
        guard settings.value.audioRetention != .off, selection == nil else { return }
        let info = RecordingInfo(date: Date(), appName: target?.name, bundleID: target?.bundleID, modeID: activeMode.id)
        recording = archive.start(id: UUID(), info: info)
    }

    /// Esc or a tap too short to count: the recording goes at once.
    func discardRecordingAudio() {
        guard let writer = recording else { return }
        recording = nil
        Task { await writer.discard() }
    }

    /// The microphone stopped and every chunk is queued: the file is sealed in the background.
    /// Returns the recording's id, which becomes its record's id.
    func closeRecordingAudio() -> UUID? {
        guard let writer = recording else { return nil }
        recording = nil
        closingAudio.insert(writer.id)
        Task { await writer.finish() }
        return writer.id
    }

    /// The words were a voice action, or only "отправь": no record, and the recording goes at once.
    func dropRecordingAudio(_ id: UUID?) {
        guard let id else { return }
        archive.delete([id])
    }

    /// A dictation that ended without text keeps its recording as a record with no text, so it
    /// can be played and transcribed again. App and mode come from the file, written when the
    /// recording started.
    func keepUntranscribed(_ id: UUID?, duration: Double, failure: DictationRecord.Failure) {
        guard let id else { return }
        let file = RecordingArchive.fileName(for: id)
        let info = RecordingFile.info(at: archive.url(for: file))
        let record = DictationRecord(id: id, text: "", raw: "", appName: info?.appName, bundleID: info?.bundleID, duration: duration, date: Date(), audio: file, modeID: info?.modeID, failure: failure)
        records.insert(record, at: 0)
        let retention = settings.value.historyRetentionDays
        Task {
            records = await historyStore.add(record, retentionDays: retention)
            await sweepAudio()
        }
    }

    // MARK: Cleanup and recovery

    /// Recordings a crash or a forced quit left behind become records that are not transcribed;
    /// then the first cleanup runs, and one every hour after it, so "a day" holds without
    /// dictations.
    func recoverRecordings() async {
        let (found, junk) = archive.recover(known: records, active: activeAudio)
        archive.delete(junk)
        if !found.isEmpty {
            records = await historyStore.insert(found)
        }
        await sweepAudio()
        audioSweepTask?.cancel()
        audioSweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3_600))
                guard !Task.isCancelled else { return }
                await self?.sweepAudio()
            }
        }
    }

    /// Recordings being written or waiting for their record.
    private var activeAudio: Set<UUID> {
        closingAudio.union([recording?.id].compactMap { $0 })
    }

    /// Unlinks the audio the setting no longer keeps, drops records that had nothing but audio,
    /// then deletes every file no record points to. The listing and the deletion run without a
    /// pause in between, so a recording that starts meanwhile can't be taken for a stray.
    func sweepAudio() async {
        let value = settings.value
        let expired = AudioKeeping.expired(records, retention: value.audioRetention, limit: value.audioLimit)
        if !expired.isEmpty {
            if let playing = player.recordID, expired.contains(playing) { player.stop() }
            records = await historyStore.dropAudio(expired)
        }
        let strays = AudioKeeping.strays(files: archive.files(), records: records, active: activeAudio)
        archive.delete(strays)
    }

    /// The retention menu changed: Off deletes every recording at once.
    func audioRetentionChanged() {
        Task { await sweepAudio() }
    }

    // MARK: Playback

    func audioURL(for record: DictationRecord) -> URL? {
        record.audio.map(archive.url(for:))
    }

    func togglePlayback(_ record: DictationRecord) {
        guard let url = audioURL(for: record) else { return }
        player.toggle(record.id, url: url)
    }

    // MARK: Re-transcription

    /// Whisper models on disk, the current one included.
    var downloadedModels: [String] {
        store.downloadedVariants()
    }

    /// The mode a re-transcription runs in: the dictation's own, or for records from before it
    /// was saved, the mode its app gets now.
    func recordMode(_ record: DictationRecord) -> DictationMode {
        let value = settings.value
        return value.modes.first { $0.id == record.modeID } ?? value.mode(for: record.bundleID)
    }

    /// Whether a re-transcription of this record with the current settings would translate it,
    /// which is when "Without Translation" means something.
    func wouldTranslate(_ record: DictationRecord) -> Bool {
        translationTarget(mode: recordMode(record), settings: settings.value) != nil
    }

    /// Runs the kept recording through recognition and formatting again, with one change against
    /// the current settings. The new text replaces the record's; the old one stays for one undo.
    /// Another model is loaded for this one run and unloaded after it; the main engine is not
    /// touched.
    func retranscribe(_ id: UUID, _ change: RetranscriptionChange = .none) {
        guard retranscription?.isRunning != true,
              let record = records.first(where: { $0.id == id }),
              canRetranscribe(record),
              let url = audioURL(for: record)
        else { return }
        var value = settings.value
        var mode = recordMode(record)
        switch change {
        case .none: break
        case .model(let variant): value.whisperModel = variant
        case .language(let language): value.language = language
        case .withoutTranslation:
            value.autoTranslate = false
            mode.translateToEnglish = false
        }
        let variant = value.whisperModel
        let mainReady = engineVariant == variant && modelState == .ready
        retranscription = Retranscription(recordID: id, state: mainReady ? .transcribing : .loading(Self.modelTitle(variant, among: downloadedModels)))
        Task {
            let samples: [Float]
            do {
                samples = try await Task.detached { try RecordingFile.samples(at: url) }.value
            } catch {
                return fail(id, .audioMissing)
            }
            guard !samples.isEmpty else { return fail(id, .audioMissing) }

            let engine: WhisperKitEngine
            var borrowed: WhisperKitEngine?
            if mainReady, let main = self.engine {
                engine = main
            } else if variant == engineVariant {
                // The main engine is loading this very model; a second copy would load it twice.
                return fail(id, .modelNotReady)
            } else {
                guard store.isDownloaded(variant) else { return fail(id, .modelFailed) }
                let other = WhisperKitEngine(store: store, variant: variant)
                do {
                    try await other.prepare()
                } catch {
                    await other.unload()
                    return fail(id, .modelFailed)
                }
                engine = other
                borrowed = other
                retranscription?.state = .transcribing
            }

            // The live path without its live parts: no voice gate, no voice action, no delivery.
            // Snippets are resolved, their variables read now (see `compose`).
            let pass = makePass(settings: value, mode: mode, readsSelection: false)
            let transcript: Transcript?
            do {
                transcript = try await hear(samples, engine: engine, pass: pass)
            } catch {
                transcript = nil
            }
            // The other model is done; the language model step doesn't need it.
            if let borrowed { await borrowed.unload() }
            guard let transcript else { return fail(id, .recognitionFailed) }
            let result = await compose(transcript, pass: pass) { stage in
                self.retranscription?.state = stage == .rewriting ? .rewriting : .transcribing
            }
            guard !result.text.isEmpty else { return fail(id, .nothingHeard) }
            let text = result.text
            let raw = result.raw
            records = await historyStore.modify(id) { record in
                record.previous = record.isTranscribed ? DictationRecord.Version(text: record.text, raw: record.raw) : nil
                record.text = text
                record.raw = raw
                record.failure = nil
            }
            retranscription = nil
            if let updated = records.first(where: { $0.id == id }) { cardRecordChanged(updated, snippets: result.snippets) }
        }
    }

    /// Whether this record's recording can be transcribed again: a voice action's text is the
    /// model's work on a selection or the clipboard, which the recording can't bring back.
    func canRetranscribe(_ record: DictationRecord) -> Bool {
        record.audio != nil && record.action == nil
    }

    /// Brings back the text the last re-transcription replaced.
    func undoRetranscription(_ id: UUID) {
        Task {
            records = await historyStore.modify(id) { record in
                guard let previous = record.previous else { return }
                record.text = previous.text
                record.raw = previous.raw
                record.previous = nil
            }
            if let updated = records.first(where: { $0.id == id }) { cardRecordChanged(updated) }
        }
    }

    private func fail(_ id: UUID, _ failure: Retranscription.Failure) {
        let state = Retranscription(recordID: id, state: .failed(failure))
        retranscription = state
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.retranscription == state else { return }
            self.retranscription = nil
        }
    }

    /// "Whisper turbo" for the large-v3-turbo builds (the v20240930 ones), "Whisper large-v3",
    /// or the variant's own name. With `among`, two builds of one model get their sizes:
    /// "Whisper turbo (632 MB)".
    static func modelTitle(_ variant: String, among variants: [String] = []) -> String {
        func family(_ variant: String) -> String {
            if variant.contains("turbo") || variant.contains("v20240930") { return "Whisper turbo" }
            if variant.hasPrefix("large-v3") { return "Whisper large-v3" }
            return "Whisper \(variant)"
        }
        let title = family(variant)
        guard variants.filter({ family($0) == title }).count > 1,
              let size = variant.split(separator: "_").last, size.hasSuffix("MB"), size.dropLast(2).allSatisfy(\.isNumber)
        else { return title }
        return "\(title) (\(size.dropLast(2)) MB)"
    }
}
