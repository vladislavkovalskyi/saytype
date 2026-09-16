import SwiftUI
import VMCore

struct DictionarySection: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    /// A row added with "Add" that has no spelling yet. It joins the dictionary
    /// once "Written" is filled, so a half-typed entry never rewrites dictation.
    @State private var draft: DictionaryEntry?
    @FocusState private var focus: DictionaryField?

    var body: some View {
        let entries = model.settings.value.dictionary
        ZStack(alignment: .topLeading) {
            HeaderArt(name: "ObjectAa", width: 250, right: 10, top: -24)

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Dictionary", subtitle: "\(entries.count) terms · passed to Whisper as hints")
                    .frame(height: 84, alignment: .topLeading)

                HStack(spacing: 10) {
                    SearchField(prompt: "Find term", text: $query)
                    Button(action: add) {
                        Label { Text("Add") } icon: { Icon(.plus, size: 14, stroke: 2.4) }
                            .labelStyle(IconFirstLabelStyle())
                    }
                    .buttonStyle(WhiteButtonStyle())
                }
                .frame(height: 38)

                table(entries: entries)
                    .frame(width: 1068, height: 530, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frost()
                    .padding(.top, 16)
            }
        }
        .onDisappear {
            draft = nil
        }
    }

    private func table(entries: [DictionaryEntry]) -> some View {
        let visible = filtered(entries)
        return VStack(spacing: 0) {
            DictionaryRowLayout {
                PanelLabel("Heard")
            } arrow: {
                Color.clear
            } written: {
                PanelLabel("Written")
            } source: {
                PanelLabel("Source")
            } delete: {
                Color.clear
            }
            .frame(height: 40)
            RowDivider(opacity: 0.13)

            if visible.isEmpty && draft == nil {
                Text(entries.isEmpty ? "Empty" : "No results")
                    .font(.onest(15, .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let draft {
                            row(draft, isDraft: true)
                        }
                        ForEach(visible) { entry in
                            row(entry, isDraft: false)
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    private func row(_ entry: DictionaryEntry, isDraft: Bool) -> some View {
        VStack(spacing: 0) {
            DictionaryRowLayout {
                EditableCell(value: entry.heard, placeholder: String(localized: "how it sounds", comment: "Placeholder for the heard form of a dictionary term"), isCode: false, field: .heard(entry.id), focus: $focus) { value in
                    commit(entry.id, isDraft: isDraft, heard: value)
                }
            } arrow: {
                Icon(.arrowRight, size: 16, stroke: 2).opacity(0.6)
            } written: {
                EditableCell(value: entry.written, placeholder: String(localized: "how it is written", comment: "Placeholder for the spelling of a dictionary term"), isCode: CodeWords.isCode(entry.written), field: .written(entry.id), focus: $focus) { value in
                    commit(entry.id, isDraft: isDraft, written: value)
                }
            } source: {
                Text(entry.source == .manual ? "manual" : "from history")
                    .font(.onest(12))
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(.white.opacity(0.16)))
            } delete: {
                Button {
                    delete(entry.id, isDraft: isDraft)
                } label: {
                    Icon(.xmark, size: 16)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(0.5)
                .padding(.leading, -6)
                .help("Delete")
            }
            .frame(height: 52)
            RowDivider(opacity: 0.13)
        }
        .id(entry.id)
    }

    private func filtered(_ entries: [DictionaryEntry]) -> [DictionaryEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return entries }
        return entries.filter { $0.heard.lowercased().contains(needle) || $0.written.lowercased().contains(needle) }
    }

    // MARK: Editing

    private func add() {
        query = ""
        let entry = draft ?? DictionaryEntry(heard: "", written: "", source: .manual)
        draft = entry
        Task { @MainActor in
            focus = .heard(entry.id)
        }
    }

    private func commit(_ id: UUID, isDraft: Bool, heard: String? = nil, written: String? = nil) {
        let heard = heard?.trimmingCharacters(in: .whitespacesAndNewlines)
        let written = written?.trimmingCharacters(in: .whitespacesAndNewlines)
        if isDraft {
            guard var entry = draft, entry.id == id else { return }
            if let heard { entry.heard = heard }
            if let written { entry.written = written }
            if entry.written.isEmpty {
                draft = entry
            } else {
                draft = nil
                model.settings.value.dictionary.insert(entry, at: 0)
            }
            return
        }
        guard let index = model.settings.value.dictionary.firstIndex(where: { $0.id == id }) else { return }
        var entry = model.settings.value.dictionary[index]
        if let heard { entry.heard = heard }
        // A term always needs a spelling; clearing it keeps the old one.
        if let written, !written.isEmpty { entry.written = written }
        if entry != model.settings.value.dictionary[index] {
            model.settings.value.dictionary[index] = entry
        }
    }

    private func delete(_ id: UUID, isDraft: Bool) {
        if isDraft {
            draft = nil
        } else {
            model.settings.value.dictionary.removeAll { $0.id == id }
        }
    }
}

enum DictionaryField: Hashable {
    case heard(UUID)
    case written(UUID)
}

/// Column grid of the dictionary table: 1fr · 40 · 1fr · 150 · 60.
private struct DictionaryRowLayout<Heard: View, Arrow: View, Written: View, Source: View, Delete: View>: View {
    @ViewBuilder let heard: Heard
    @ViewBuilder let arrow: Arrow
    @ViewBuilder let written: Written
    @ViewBuilder let source: Source
    @ViewBuilder let delete: Delete

    var body: some View {
        HStack(spacing: 0) {
            heard
                .padding(.leading, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            arrow
                .frame(width: 40, alignment: .leading)
            written
                .frame(maxWidth: .infinity, alignment: .leading)
            source
                .frame(width: 150, alignment: .leading)
            delete
                .frame(width: 60, alignment: .leading)
        }
        .font(.onest(14.5))
    }
}

/// Text that turns into a field in place. Commits on Return and when focus leaves.
private struct EditableCell: View {
    let value: String
    let placeholder: String
    let isCode: Bool
    let field: DictionaryField
    var focus: FocusState<DictionaryField?>.Binding
    let commit: (String) -> Void

    @State private var text = ""
    @State private var textWidth: CGFloat = 0

    var body: some View {
        let isFocused = focus.wrappedValue == field
        ZStack(alignment: .leading) {
            // Sizes the chip to the text.
            Text(text.isEmpty ? placeholder : text)
                .font(font)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            if text.isEmpty {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(.white.opacity(isFocused ? 0.45 : 0.3))
                    .allowsHitTesting(false)
            }
            TextField(text: $text) { EmptyView() }
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(.white)
                .focused(focus, equals: field)
                .onSubmit { commit(text) }
        }
        .frame(width: min(textWidth + 4, 380), alignment: .leading)
        .padding(.horizontal, isCode ? 7 : 0)
        .padding(.vertical, isCode ? 2 : 0)
        .background {
            if isCode {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.2))
            } else if isFocused {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.12)).padding(.horizontal, -6).padding(.vertical, -3)
            }
        }
        .tint(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = field }
        .onAppear { text = value }
        .onChange(of: value) { _, newValue in
            if !isFocused { text = newValue }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit(text) }
        }
    }

    private var font: Font {
        isCode ? .mono(13.5) : .onest(14.5)
    }
}

/// Icon then title with the white-button spacing.
struct IconFirstLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}
