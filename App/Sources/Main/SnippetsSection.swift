import SwiftUI
import VMCore

/// Phrases that insert saved text: a list on the left, the selected snippet on the right.
struct SnippetsSection: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: UUID?

    var body: some View {
        @Bindable var settings = model.settings
        ZStack(alignment: .topLeading) {
            HeaderArt(name: "ObjectBraces", width: 250, right: 14, top: -22)

            VStack(alignment: .leading, spacing: 16) {
                SectionHeader("Snippets", subtitle: "Phrases that insert saved text")
                    .frame(height: 78, alignment: .topLeading)

                HStack(alignment: .top, spacing: 16) {
                    SnippetList(selectedID: $selectedID, add: add)
                        .frame(width: 330)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .frost()

                    Group {
                        if let id = selectedID, settings.value.snippets.contains(where: { $0.id == id }) {
                            SnippetEditor(snippets: $settings.value.snippets, id: id) {
                                delete(id)
                            }
                            .id(id)
                        } else {
                            VStack {
                                Button(action: add) {
                                    Label { Text("New snippet") } icon: { Icon(.plus, size: 14, stroke: 2.4) }
                                        .labelStyle(IconFirstLabelStyle())
                                }
                                .buttonStyle(WhiteButtonStyle())
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: 722)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .frost()
                }
                .frame(height: 560)
            }
        }
        .onAppear {
            if !settings.value.snippets.contains(where: { $0.id == selectedID }) {
                selectedID = settings.value.snippets.first?.id
            }
        }
        .onDisappear(perform: dropEmpty)
    }

    private func add() {
        // An untouched new snippet is reused instead of piling up empty ones.
        if let blank = model.settings.value.snippets.first(where: \.isBlank) {
            selectedID = blank.id
            return
        }
        let snippet = Snippet()
        withAnimation(.snappy(duration: 0.2)) {
            model.settings.value.snippets.append(snippet)
            selectedID = snippet.id
        }
    }

    private func delete(_ id: UUID) {
        let snippets = model.settings.value.snippets
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            model.settings.value.snippets.remove(at: index)
            let rest = model.settings.value.snippets
            selectedID = rest.isEmpty ? nil : rest[min(index, rest.count - 1)].id
        }
    }

    /// A snippet left without a phrase and without text never fires; it goes when the section closes.
    private func dropEmpty() {
        if model.settings.value.snippets.contains(where: \.isBlank) {
            model.settings.value.snippets.removeAll(where: \.isBlank)
        }
    }
}

extension Snippet {
    fileprivate var isBlank: Bool {
        triggers.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Screenshots and previews show these, never the user's own.
    static let previewSamples: [Snippet] = [
        Snippet(triggers: ["мой имейл", "my email"], text: "vlad@example.com"),
        Snippet(triggers: ["ссылка на репо"], text: "https://github.com/vladislavkovalskyi/saytype"),
        Snippet(
            triggers: ["шаблон ревью", "review template"],
            text: "Review {selection} for bugs, missing tests and unclear names.\nList the problems by severity, one line each. Do not rewrite the code."
        ),
        Snippet(triggers: ["код из буфера"], text: "```\n{clipboard}\n```"),
    ]
}

// MARK: List

private struct SnippetList: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedID: UUID?
    let add: () -> Void

    var body: some View {
        let snippets = model.settings.value.snippets
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PanelLabel("Snippets")
                if !snippets.isEmpty {
                    Text(verbatim: Format.grouped(snippets.count))
                        .font(.onest(12.5, .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            RowDivider()

            if snippets.isEmpty {
                Text("No snippets")
                    .font(.onest(14.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(snippets) { snippet in
                            SnippetRow(snippet: snippet, isSelected: snippet.id == selectedID) {
                                selectedID = snippet.id
                            }
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.never)
            }

            RowDivider()
            Button(action: add) {
                HStack(spacing: 6) {
                    Icon(.plus, size: 14, stroke: 2)
                    Text("New snippet")
                }
            }
            .buttonStyle(ChipButtonStyle())
            .padding(14)
        }
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.onest(14.5, .medium))
                    .lineLimit(1)
                preview
                    .font(.onest(12.5))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(isSelected ? 0.2 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var title: some View {
        if let phrase = snippet.triggers.first {
            Text(verbatim: phrase)
        } else {
            Text("No phrase").foregroundStyle(.white.opacity(0.55))
        }
    }

    @ViewBuilder private var preview: some View {
        // The first line with words in it: a code fence says nothing about the snippet.
        let lines = snippet.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let line = lines.first { $0.contains { $0.isLetter || $0.isNumber } } ?? lines.first ?? ""
        if line.isEmpty {
            Text("Empty").foregroundStyle(.white.opacity(0.45))
        } else {
            Text(verbatim: line)
        }
    }
}

// MARK: Editor

/// The snippet with `id`, looked up on every change, so a delete never leaves a stale index behind.
private struct SnippetEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var snippets: [Snippet]
    let id: UUID
    let delete: () -> Void

    @State private var phraseDraft = ""
    @State private var selection: TextSelection?
    @FocusState private var phraseFocused: Bool

    private var index: Int? { snippets.firstIndex { $0.id == id } }

    var body: some View {
        if let index {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    header(snippets[index])
                    phrases(index)
                    textGroup(snippets[index])
                    variables
                }
                .padding(20)
            }
            .scrollIndicators(.never)
            .onAppear {
                // A new snippet starts with its first phrase.
                if snippets[index].triggers.isEmpty {
                    Task { @MainActor in phraseFocused = true }
                }
            }
        }
    }

    private func header(_ snippet: Snippet) -> some View {
        HStack(spacing: 10) {
            Group {
                if let phrase = snippet.triggers.first {
                    Text(verbatim: phrase)
                } else {
                    Text("New snippet").foregroundStyle(.white.opacity(0.6))
                }
            }
            .font(.onest(22, .bold))
            .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: delete) {
                HStack(spacing: 6) {
                    Icon(.trash, size: 14)
                    Text("Delete")
                }
            }
            .buttonStyle(ChipButtonStyle())
        }
        .frame(height: 32)
    }

    private func phrases(_ index: Int) -> some View {
        let voiceCommands = model.settings.value.voiceCommands
        return EditorGroup(title: "Phrases") {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(Array(snippets[index].triggers.enumerated()), id: \.offset) { offset, phrase in
                    PhraseChip(phrase: phrase, issue: Snippet.issue(trigger: offset, of: index, in: snippets, voiceCommands: voiceCommands)) {
                        update { $0.triggers.remove(at: offset) }
                    }
                }
                AddPhraseField(text: $phraseDraft, isFocused: $phraseFocused, commit: addPhrase)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private func textGroup(_ snippet: Snippet) -> some View {
        EditorGroup(title: "Text") {
            ZStack(alignment: .topLeading) {
                if snippet.text.isEmpty {
                    Text("Text to insert")
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text, selection: $selection)
                    .scrollContentBackground(.hidden)
                    .tint(.white)
            }
            .font(.mono(13))
            .lineSpacing(3)
            .frame(height: 188)
            .padding(12)
        }
    }

    private var variables: some View {
        EditorGroup(title: "Variables") {
            // Date and time show what they would insert now.
            TimelineView(.everyMinute) { context in
                let now = SnippetValues(now: context.date)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    VariableChip(variable: .clipboard, value: nil, help: "Text on the clipboard", insert: insert)
                    VariableChip(variable: .selection, value: nil, help: "Text selected in the app you dictate into", insert: insert)
                    VariableChip(variable: .date, value: now.date, help: "Today's date", insert: insert)
                    VariableChip(variable: .time, value: now.time, help: "Current time", insert: insert)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var text: Binding<String> {
        Binding {
            snippets.first { $0.id == id }?.text ?? ""
        } set: { value in
            update { $0.text = value }
        }
    }

    private func update(_ change: (inout Snippet) -> Void) {
        guard let index else { return }
        change(&snippets[index])
    }

    private func addPhrase(_ raw: String) {
        let phrase = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        phraseDraft = ""
        let key = SnippetMatcher.key(phrase)
        guard !key.isEmpty, let index, !snippets[index].triggers.contains(where: { SnippetMatcher.key($0) == key }) else { return }
        update { $0.triggers.append(phrase) }
    }

    /// Puts the variable where the caret is, or at the end when the field was never clicked.
    private func insert(_ variable: SnippetVariable) {
        guard let index else { return }
        var value = snippets[index].text
        let token = variable.token
        if case .selection(let range) = selection?.indices, range.upperBound <= value.endIndex {
            let offset = value.distance(from: value.startIndex, to: range.lowerBound)
            value.replaceSubrange(range, with: token)
            update { $0.text = value }
            selection = TextSelection(insertionPoint: value.index(value.startIndex, offsetBy: offset + token.count))
        } else {
            update { $0.text = value + token }
        }
    }
}

/// A titled group inside the editor, as in Modes.
private struct EditorGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelLabel(title).padding(.leading, 4)
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1))
        }
    }
}

/// A trigger phrase with its ✕; a phrase that never fires is dimmed and says why.
private struct PhraseChip: View {
    let phrase: String
    let issue: SnippetTriggerIssue?
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: phrase)
                .opacity(issue == nil ? 1 : 0.6)
            if let issue {
                Text(label(issue))
                    .font(.onest(11.5, .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(.white.opacity(0.14)))
            }
            Button(action: remove) {
                Icon(.xmark, size: 11, stroke: 2)
                    .frame(width: 16, height: 16)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(0.8)
            .help("Remove")
        }
        .font(.onest(13, .medium))
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 30)
        .background(Capsule().fill(.white.opacity(0.2)))
    }

    private func label(_ issue: SnippetTriggerIssue) -> LocalizedStringKey {
        switch issue {
        case .tooShort: "too short"
        case .voiceCommand: "voice command"
        case .duplicate: "duplicate"
        }
    }
}

/// Chip-sized field that adds a phrase on Return.
private struct AddPhraseField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let commit: (String) -> Void

    var body: some View {
        HStack(spacing: 5) {
            Icon(.plus, size: 13, stroke: 2)
                .opacity(0.8)
            // The placeholder or the typed phrase sets the width; the field sits on top.
            (text.isEmpty ? Text("Add phrase") : Text(verbatim: text + "  "))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(isFocused.wrappedValue ? 0.45 : 0.7))
                .opacity(text.isEmpty ? 1 : 0)
                .frame(maxWidth: 260, alignment: .leading)
                .fixedSize()
                .overlay(alignment: .leading) {
                    TextField(text: $text) { EmptyView() }
                        .textFieldStyle(.plain)
                        .focused(isFocused)
                        .onSubmit { commit(text) }
                }
        }
        .font(.onest(13, .medium))
        .foregroundStyle(.white)
        .tint(.white)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 30)
        .background(Capsule().strokeBorder(.white.opacity(isFocused.wrappedValue ? 0.5 : 0.28), style: StrokeStyle(lineWidth: 1, dash: isFocused.wrappedValue ? [] : [3, 3])))
        .contentShape(Capsule())
        .onTapGesture { isFocused.wrappedValue = true }
        .onChange(of: isFocused.wrappedValue) { _, focused in
            // Clicking away keeps a typed phrase instead of dropping it.
            if !focused, !text.isEmpty { commit(text) }
        }
    }
}

/// `{date}` and today's value; a click puts the variable into the text.
private struct VariableChip: View {
    let variable: SnippetVariable
    let value: String?
    let help: LocalizedStringKey
    let insert: (SnippetVariable) -> Void

    var body: some View {
        Button {
            insert(variable)
        } label: {
            HStack(spacing: 7) {
                Text(verbatim: variable.token)
                    .font(.mono(12.5, .medium))
                if let value {
                    Text(verbatim: value)
                        .font(.onest(12.5))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(ChipFill())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
