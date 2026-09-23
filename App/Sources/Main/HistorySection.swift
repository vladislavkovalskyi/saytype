import AppKit
import SwiftUI
import VMCore

struct HistorySection: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var mode = RecordDetail.Mode.result

    var body: some View {
        let dictation = model.dictation
        // Recordings that have no text yet are listed here, and only here.
        let history = dictation.records
        let stats = dictation.stats
        ZStack(alignment: .topLeading) {
            HeaderArt(name: "ObjectStack", width: 280, right: -10, top: -40)

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("History") {
                    RetentionLine()
                }
                .frame(height: 84, alignment: .topLeading)

                HStack(spacing: 12) {
                    StatTile(value: stats.wordsToday, caption: String(localized: "\(stats.wordsToday) words today", comment: "Caption under the number; the plural forms leave the number out"))
                    StatTile(value: stats.wordsPerMinute, caption: String(localized: "\(stats.wordsPerMinute) words per minute", comment: "Caption under the number; the plural forms leave the number out"))
                    StatTile(value: stats.wordsThisWeek, caption: String(localized: "\(stats.wordsThisWeek) words this week", comment: "Caption under the number; the plural forms leave the number out"))
                }
                .frame(width: 780, height: 84)

                Group {
                    if history.isEmpty {
                        Text("Nothing yet")
                            .font(.onest(21, .semibold))
                            .frame(width: 1068, height: 480)
                            .frost()
                    } else {
                        let visible = filtered(history)
                        let selected = visible.first { $0.id == selectedID } ?? visible.first
                        HStack(alignment: .top, spacing: 16) {
                            RecordList(records: visible, selectedID: selected?.id, query: $query) { selectedID = $0 }
                                .frame(width: 450, height: 480)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .frost()
                            Group {
                                if let selected {
                                    RecordDetail(record: selected, mode: $mode)
                                        .id(selected.id)
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: 602, height: 480, alignment: .topLeading)
                            .frost()
                        }
                    }
                }
                .padding(.top, 20)
            }
        }
    }

    private func filtered(_ records: [DictationRecord]) -> [DictationRecord] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return records }
        return records.filter { $0.text.localizedCaseInsensitiveContains(needle) }
    }
}

/// "Kept on this Mac for 30 days ⌄ · audio for 1 day ⌄".
private struct RetentionLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let days = model.settings.value.historyRetentionDays
        let audio = model.settings.value.audioRetention
        HStack(spacing: 5) {
            Text("Kept on this Mac for", comment: "Followed by a menu with the retention period, e.g. 30 days")
            PopupMenu(items: [7, 30, 90].map { option in
                MenuOption(title: String(localized: "\(option) days"), isOn: option == days) {
                    model.settings.value.historyRetentionDays = option
                }
            }) {
                MenuValue(text: Text("\(days) days"))
            }
            Text(verbatim: "·")
            if audio == .off {
                Text("audio", comment: "After the history's retention menu, before the audio's: \"· audio not kept\"")
            } else {
                Text("audio for", comment: "After the history's retention menu, before the audio's: \"· audio for 1 day\"")
            }
            PopupMenu(items: audioItems(audio)) {
                switch audio {
                case .off: MenuValue(text: Text("not kept", comment: "Audio retention readout: no recordings are kept"))
                case .day: MenuValue(text: Text("\(1) days"))
                case .week: MenuValue(text: Text("\(7) days"))
                }
            }
        }
    }

    private func audioItems(_ current: AppSettings.AudioRetention) -> [MenuOption] {
        let limit = model.settings.value.audioLimit
        return [
            MenuOption(title: String(localized: "Don't Keep", comment: "Audio retention menu: no recordings are kept"), isOn: current == .off) { set(.off) },
            MenuOption(title: String(localized: "\(1) days"), isOn: current == .day) { set(.day) },
            MenuOption(title: String(localized: "\(7) days"), isOn: current == .week) { set(.week) },
            .separator,
            MenuOption(title: String(localized: "Up to \(limit) recordings", comment: "Audio retention menu, a disabled line: the newest recordings kept at most"), isOn: false, action: {}, isEnabled: false),
        ]
    }

    private func set(_ retention: AppSettings.AudioRetention) {
        model.settings.value.audioRetention = retention
        model.dictation.audioRetentionChanged()
    }
}

/// The value of an inline menu: underlined, with a chevron.
private struct MenuValue: View {
    let text: Text

    var body: some View {
        HStack(spacing: 2) {
            text.underline(color: .white.opacity(0.35))
            Icon(.chevronDown, size: 14)
        }
        .foregroundStyle(.white.opacity(0.86))
    }
}

private struct StatTile: View {
    let value: Int
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Format.grouped(value))
                .font(.onest(28, .bold))
                .tracking(-0.56)
            Text(caption)
                .font(.onest(13))
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .frost()
    }
}

// MARK: List

private struct RecordList: View {
    let records: [DictationRecord]
    let selectedID: UUID?
    @Binding var query: String
    let select: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SearchField(prompt: "Search", text: $query, width: nil, height: 34, frosted: false)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 4)
            if records.isEmpty {
                Text("No results")
                    .font(.onest(15, .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.title) { group in
                            PanelLabel(verbatim: group.title)
                                .padding(.horizontal, 18)
                                .padding(.top, 14)
                                .padding(.bottom, 6)
                            ForEach(group.records) { record in
                                RecordRow(record: record, isSelected: record.id == selectedID) {
                                    select(record.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var groups: [(title: String, records: [DictationRecord])] {
        var result: [(title: String, records: [DictationRecord])] = []
        for record in records {
            let title = Format.day(record.date)
            if result.last?.title == title {
                result[result.count - 1].records.append(record)
            } else {
                result.append((title, [record]))
            }
        }
        return result
    }
}

private struct RecordRow: View {
    @Environment(AppModel.self) private var model
    let record: DictationRecord
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let player = model.dictation.player
        // The row is a tap target rather than a button, so the play button inside it gets its clicks.
        VStack(alignment: .leading, spacing: 5) {
            if let failure = record.failure {
                Text(failure.title)
                    .font(.onest(14, .medium))
                    .foregroundStyle(.white.opacity(0.62))
            } else {
                Text(record.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.onest(14))
                    .lineSpacing(3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 8) {
                if record.audio != nil {
                    PlayButton(isPlaying: player.isPlaying(record.id), size: 20, prominent: false) {
                        model.dictation.togglePlayback(record)
                    }
                }
                SpeechBars(
                    count: min(14, max(2, Int(record.duration.rounded()))),
                    seed: Int(record.id.uuid.0) + Int(record.id.uuid.1),
                    minHeight: 2,
                    maxHeight: 11,
                    barWidth: 2,
                    spacing: 1.5
                )
                .foregroundStyle(.white.opacity(0.85))
                .playhead(player.recordID == record.id ? player.progress : nil)
                Text(([record.appName, Format.time(record.date)].compactMap { $0 } + [Format.duration(record.duration)]).joined(separator: " · "))
            }
            .font(.onest(12))
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                Rectangle().fill(.white.opacity(0.2))
                    .overlay(alignment: .leading) { Rectangle().fill(.white).frame(width: 3) }
            }
        }
        .overlay(alignment: .bottom) { RowDivider(opacity: 0.12) }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityAddTraits(.isButton)
        .draggable(record.text)
    }
}

// MARK: Audio

/// Round play and pause button.
private struct PlayButton: View {
    let isPlaying: Bool
    var size: CGFloat = 32
    /// White with dark ink; otherwise a translucent chip.
    var prominent = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .offset(x: isPlaying ? 0 : size * 0.03)
                .foregroundStyle(prominent ? Color.ink : .white)
                .frame(width: size, height: size)
                .background(Circle().fill(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.18))))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isPlaying ? Text("Pause", comment: "Tooltip of the button that pauses a recording") : Text("Play", comment: "Tooltip of the button that plays a recording"))
    }
}

private extension View {
    /// Dims what lies past the playhead while a recording plays; `nil` leaves the view as it is.
    @ViewBuilder func playhead(_ progress: Double?) -> some View {
        if let progress {
            self.opacity(0.45)
                .overlay(alignment: .leading) {
                    self.mask(alignment: .leading) {
                        GeometryReader { geometry in
                            Rectangle().frame(width: geometry.size.width * progress)
                        }
                    }
                }
        } else {
            self
        }
    }
}

extension DictationRecord.Failure {
    /// What the history shows in place of the text.
    var title: LocalizedStringKey {
        switch self {
        case .interrupted: "Not transcribed"
        case .nothingHeard: "Nothing heard"
        case .recognitionFailed: "Couldn't transcribe"
        }
    }
}

// MARK: Detail

private struct RecordDetail: View {
    enum Mode: Hashable {
        case result, raw, diff
    }

    @Environment(AppModel.self) private var model
    let record: DictationRecord
    @Binding var mode: Mode
    @State private var copied = false
    /// Words of the final text picked for a spelling fix.
    @State private var picked: ClosedRange<Int>?
    /// "хедер → Header" for a moment after a fix was added.
    @State private var added: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(([record.appName].compactMap { $0 } + [Format.moment(record.date)]).joined(separator: " · "))
                        .font(.onest(16, .semibold))
                    Text(verbatim: record.isTranscribed ? "\(Format.duration(record.duration)) · " + String(localized: "\(record.wordCount) words") : Format.duration(record.duration))
                        .font(.onest(13))
                        .foregroundStyle(.white.opacity(0.74))
                }
                Spacer(minLength: 12)
                if record.isTranscribed {
                    WorldSegmented(selection: $mode, options: [(.result, "Final"), (.raw, "As spoken"), (.diff, "Changes")])
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            if record.audio != nil {
                AudioStrip(record: record)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }

            if let failure = record.failure {
                Text(failure.title)
                    .font(.onest(21, .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                transcript
            }

            if let picked {
                FixWordBar(record: record, words: picked) {
                    self.picked = nil
                } done: { entry in
                    self.picked = nil
                    confirm(entry)
                }
                .id(picked)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .padding(.top, 8)
            } else {
                actions
            }
        }
        .onChange(of: mode) { picked = nil }
        // A re-transcription or its undo replaced the words the picked range pointed at.
        .onChange(of: record.text) { picked = nil }
    }

    private var transcript: some View {
        ScrollView {
            Group {
                switch mode {
                case .result: DictatedText(text: record.text, selection: $picked)
                case .raw: DictatedText(text: record.raw)
                case .diff: DiffText(raw: record.raw, text: record.text)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .draggable(record.text)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let added {
                Label {
                    HStack(spacing: 0) {
                        Text("Added to dictionary")
                        Text(verbatim: " · \(added)")
                    }
                } icon: { Icon(.check, size: 14, stroke: 2.2) }
                    .labelStyle(IconFirstLabelStyle())
                    .font(.onest(13, .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(.white).shadow(color: Color(hex: 0x140A1E, opacity: 0.18), radius: 7, y: 4))
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if record.isTranscribed {
                textActions
            }

            Spacer()

            Button {
                model.dictation.removeFromHistory(record.id)
            } label: {
                Label { Text("Delete") } icon: { Icon(.trash, size: 14, stroke: 2) }
                    .labelStyle(IconFirstLabelStyle())
            }
            .buttonStyle(ChipButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .padding(.top, 8)
    }

    @ViewBuilder private var textActions: some View {
        Button(action: copy) {
            Label { Text(copied ? "Copied" : "Copy") } icon: { Icon(copied ? .check : .copy, size: 14, stroke: 2) }
                .labelStyle(IconFirstLabelStyle())
        }
        .buttonStyle(WhiteButtonStyle())

        Label { Text("Drag") } icon: { Icon(.grip, size: 14) }
            .labelStyle(IconFirstLabelStyle())
            .font(.onest(13, .medium))
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(ChipFill())
            .contentShape(Capsule())
            .draggable(record.text)

        Button("Paste again", action: insertAgain)
            .buttonStyle(ChipButtonStyle())
    }

    private func confirm(_ entry: DictionaryEntry) {
        let readout = entry.readout
        withAnimation(.snappy(duration: 0.2)) { added = readout }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard added == readout else { return }
            withAnimation(.snappy(duration: 0.3)) { added = nil }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.text, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    /// Gives focus back to the app the text came from, then pastes into it.
    private func insertAgain() {
        if let bundleID = record.bundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        } else {
            NSApp.hide(nil)
        }
        let dictation = model.dictation
        let record = record
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            dictation.insertAgain(record)
        }
    }
}

/// The kept recording of a record: play, the playhead, and transcribing it again.
private struct AudioStrip: View {
    @Environment(AppModel.self) private var model
    let record: DictationRecord

    var body: some View {
        let dictation = model.dictation
        let player = dictation.player
        let loaded = player.recordID == record.id
        let job = dictation.retranscription
        let ownJob = job?.recordID == record.id ? job : nil
        HStack(spacing: 12) {
            PlayButton(isPlaying: player.isPlaying(record.id)) {
                dictation.togglePlayback(record)
            }
            Text(verbatim: "\(Self.time(loaded ? player.position : 0)) / \(Self.time(record.duration))")
                .font(.mono(12))
                .foregroundStyle(.white.opacity(0.74))
                .monospacedDigit()
                .fixedSize()
            PlayheadTrack(progress: loaded ? player.progress : 0) { fraction in
                if !loaded { dictation.togglePlayback(record) }
                player.seek(record.id, to: fraction)
            }
            if let ownJob, ownJob.isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini).environment(\.colorScheme, .dark)
                    Text(ownJob.state.readout)
                        .lineLimit(1)
                }
                .font(.onest(13, .medium))
                .fixedSize()
                .padding(.trailing, 10)
            } else {
                if case .failed(let failure) = ownJob?.state {
                    Text(failure.readout)
                        .font(.onest(13))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .fixedSize()
                }
                if record.previous != nil {
                    Button("Undo") { dictation.undoRetranscription(record.id) }
                        .buttonStyle(ChipButtonStyle())
                        .help(Text("Restore the previous text", comment: "Tooltip of Undo next to a recording: the text before the last transcription comes back"))
                }
                if dictation.canRetranscribe(record) {
                    MenuChip(
                        title: record.isTranscribed ? String(localized: "Transcribe Again", comment: "Menu with the ways to transcribe a kept recording again") : String(localized: "Transcribe", comment: "Menu that transcribes a recording that has no text yet"),
                        items: RetranscribeMenu.items(for: record, dictation: dictation)
                    )
                    .disabled(job?.isRunning == true)
                    .opacity(job?.isRunning == true ? 0.5 : 1)
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .frame(height: 44)
        .background(Capsule().fill(.white.opacity(0.1)).overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1)))
    }

    /// 72.4 → "1:12".
    static func time(_ seconds: Double) -> String {
        Duration.seconds(Int(seconds.rounded(.down))).formatted(.time(pattern: .minuteSecond))
    }
}

/// A thin track with the played part filled; a click jumps there.
private struct PlayheadTrack: View {
    let progress: Double
    let seek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(.white).frame(width: max(4, geometry.size.width * progress))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard geometry.size.width > 0 else { return }
                seek(location.x / geometry.size.width)
            }
        }
        .frame(minWidth: 60, maxHeight: 24)
    }
}

extension Retranscription.State {
    var readout: String {
        switch self {
        case .loading(let model): String(localized: "Loading \(model)", comment: "Re-transcription stage: another Whisper model loads; the argument is its name")
        case .transcribing: String(localized: "Transcribing", comment: "Re-transcription stage")
        case .rewriting: String(localized: "Rewriting")
        case .failed(let failure): failure.readout
        }
    }
}

extension Retranscription.Failure {
    var readout: String {
        switch self {
        case .nothingHeard: String(localized: "Nothing heard")
        case .recognitionFailed: String(localized: "Couldn't transcribe")
        case .modelFailed: String(localized: "Model failed to load")
        case .modelNotReady: String(localized: "Model not ready", comment: "Re-transcription failed: the current model is still loading")
        case .audioMissing: String(localized: "Recording not found", comment: "Re-transcription failed: the audio file is gone")
        }
    }
}

/// Picked words → how to write them, added to the dictionary.
private struct FixWordBar: View {
    @Environment(AppModel.self) private var model
    let record: DictationRecord
    let words: ClosedRange<Int>
    let cancel: () -> Void
    let done: (DictionaryEntry) -> Void
    /// What Whisper heard for the picked words; aligned once, not on every key press.
    private let heard: String
    @State private var spelling = ""
    @FocusState private var isFocused: Bool

    init(record: DictationRecord, words: ClosedRange<Int>, cancel: @escaping () -> Void, done: @escaping (DictionaryEntry) -> Void) {
        self.record = record
        self.words = words
        self.cancel = cancel
        self.done = done
        heard = HistoryCorrection.heard(raw: record.raw, text: record.text, words: words)
    }

    var body: some View {
        let entry = HistoryCorrection.entry(heard: heard, written: spelling)
        HStack(spacing: 8) {
            Text(verbatim: heard)
                .font(.onest(14, .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Icon(.arrowRight, size: 14, stroke: 2)
                .opacity(0.8)
            TextField(text: $spelling) { EmptyView() }
                .textFieldStyle(.plain)
                .font(.onest(14))
                .foregroundStyle(.white)
                .tint(.white)
                .focused($isFocused)
                .onSubmit { add(entry) }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .frame(minWidth: 160, maxWidth: .infinity)
                .background(Capsule().fill(.white.opacity(0.14)).overlay(Capsule().strokeBorder(.white.opacity(isFocused ? 0.5 : 0.24), lineWidth: 1)))
            Button("Add to dictionary") { add(entry) }
                .buttonStyle(WhiteButtonStyle())
                .disabled(entry == nil)
                .opacity(entry == nil ? 0.6 : 1)
            Button(action: cancel) {
                Icon(.xmark, size: 14, stroke: 2)
                    .frame(width: 32, height: 32)
                    .background(ChipFill())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            // Starts from the picked words as they were written, e.g. "Хедер" for "Header".
            let picked = Words.split(record.text)
            spelling = words.upperBound < picked.count
                ? picked[words].map { $0.trimmingCharacters(in: .punctuationCharacters) }.joined(separator: " ")
                : ""
            isFocused = true
        }
    }

    private func add(_ entry: DictionaryEntry?) {
        guard let entry else { return }
        model.settings.value.dictionary.addCorrection(entry)
        done(entry)
    }
}
