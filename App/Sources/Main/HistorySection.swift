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
        let history = dictation.history
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

/// "Kept on this Mac for 30 days ⌄".
private struct RetentionLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let days = model.settings.value.historyRetentionDays
        HStack(spacing: 5) {
            Text("Kept on this Mac for", comment: "Followed by a menu with the retention period, e.g. 30 days")
            PopupMenu(items: [7, 30, 90].map { option in
                MenuOption(title: String(localized: "\(option) days"), isOn: option == days) {
                    model.settings.value.historyRetentionDays = option
                }
            }) {
                HStack(spacing: 2) {
                    Text("\(days) days")
                        .underline(color: .white.opacity(0.35))
                    Icon(.chevronDown, size: 14)
                }
                .foregroundStyle(.white.opacity(0.86))
            }
        }
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
    let record: DictationRecord
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(record.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.onest(14))
                    .lineSpacing(3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    SpeechBars(
                        count: min(14, max(2, Int(record.duration.rounded()))),
                        seed: Int(record.id.uuid.0) + Int(record.id.uuid.1),
                        minHeight: 2,
                        maxHeight: 11,
                        barWidth: 2,
                        spacing: 1.5
                    )
                    .foregroundStyle(.white.opacity(0.85))
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
        }
        .buttonStyle(.plain)
        .draggable(record.text)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(([record.appName].compactMap { $0 } + [Format.moment(record.date)]).joined(separator: " · "))
                        .font(.onest(16, .semibold))
                    Text(verbatim: "\(Format.duration(record.duration)) · " + String(localized: "\(record.wordCount) words"))
                        .font(.onest(13))
                        .foregroundStyle(.white.opacity(0.74))
                }
                Spacer(minLength: 12)
                WorldSegmented(selection: $mode, options: [(.result, "Final"), (.raw, "As spoken"), (.diff, "Changes")])
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            ScrollView {
                Group {
                    switch mode {
                    case .result: DictatedText(text: record.text)
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

            HStack(spacing: 8) {
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
