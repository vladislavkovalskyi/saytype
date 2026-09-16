import SwiftUI
import VMCore

struct DictionarySection: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    /// Key of the built-in category being browsed; nil shows every term.
    @State private var category: String?
    /// A row added with "Add" that has no spelling yet. It joins the dictionary
    /// once "Written" is filled, so a half-typed entry never rewrites dictation.
    @State private var draft: DictionaryEntry?
    @FocusState private var focus: DictionaryField?
    private let world = MainSection.dictionary.world

    var body: some View {
        @Bindable var settings = model.settings
        ZStack(alignment: .topLeading) {
            HeaderArt(name: "ObjectAa", width: 250, right: 10, top: -24)

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Dictionary", subtitle: "How spoken terms are written")
                    .frame(height: 84, alignment: .topLeading)

                ToggleRow("Built-in dictionary", detailText: Text(verbatim: BuiltInCatalog.summary), isOn: $settings.value.builtInDictionary, accent: world.accent)
                    .frame(width: 620)
                    .frost()

                HStack(spacing: 10) {
                    SearchField(prompt: "Find term", text: $query)
                    MenuChip(title: categoryTitle, items: categoryItems)
                    Button(action: add) {
                        Label { Text("Add") } icon: { Icon(.plus, size: 14, stroke: 2.4) }
                            .labelStyle(IconFirstLabelStyle())
                    }
                    .buttonStyle(WhiteButtonStyle())
                }
                .frame(height: 38)
                .padding(.top, 16)

                table(entries: settings.value.dictionary, builtInOn: settings.value.builtInDictionary)
                    .frame(width: 1068, height: 458, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frost()
                    .padding(.top, 16)
            }
        }
        .onDisappear {
            draft = nil
        }
    }

    // MARK: Table

    private func table(entries: [DictionaryEntry], builtInOn: Bool) -> some View {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        // The user's terms have no category, so browsing one lists built-in terms only.
        let own = category == nil ? filtered(entries, needle: needle) : []
        let showsOwn = category == nil && (needle.isEmpty || !own.isEmpty || draft != nil)
        let builtIn = BuiltInCatalog.items(category: category, needle: needle)
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

            if !showsOwn && builtIn.isEmpty {
                Text("No results")
                    .font(.onest(15, .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if showsOwn {
                            GroupHeader(title: "Your terms", count: own.count)
                            if let draft {
                                row(draft, isDraft: true)
                            }
                            if own.isEmpty && draft == nil {
                                EmptyGroupRow()
                            }
                            ForEach(own) { entry in
                                row(entry, isDraft: false)
                            }
                        }
                        if !builtIn.isEmpty {
                            GroupHeader(title: "Built-in", count: builtIn.count)
                            ForEach(builtIn) { item in
                                BuiltInTermRow(item: item, isOn: builtInOn)
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
                // Another category starts from the top of its list.
                .id(category)
            }
        }
    }

    private var categoryTitle: String {
        BuiltInDictionary.categories.first { $0.key == category }?.localizedTitle ?? Self.allCategories
    }

    private var categoryItems: [MenuOption] {
        [MenuOption(title: Self.allCategories, isOn: category == nil) { category = nil }]
            + BuiltInDictionary.categories.map { item in
                MenuOption(title: item.localizedTitle, isOn: item.key == category) { category = item.key }
            }
    }

    private static var allCategories: String {
        String(localized: "All categories", comment: "Dictionary filter with no category chosen")
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
                SourceLabel(title: entry.source == .manual ? "manual" : "from history")
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

    private func filtered(_ entries: [DictionaryEntry], needle: String) -> [DictionaryEntry] {
        guard !needle.isEmpty else { return entries }
        return entries.filter { $0.heard.lowercased().contains(needle) || $0.written.lowercased().contains(needle) }
    }

    // MARK: Editing

    private func add() {
        query = ""
        category = nil
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

// MARK: Built-in terms

/// A built-in term with its search text and code look worked out once.
private struct BuiltInItem: Identifiable, Sendable {
    let term: BuiltInDictionary.Term
    /// "клод код, клауд код".
    let heard: String
    let isCode: Bool
    private let haystack: [String]

    var id: String { term.id }

    init(_ term: BuiltInDictionary.Term) {
        self.term = term
        heard = term.heard.joined(separator: ", ")
        isCode = CodeWords.isCode(term.written)
        haystack = ([term.written] + term.heard).map { $0.lowercased() }
    }

    /// True when the written form or any heard form contains the lowercased query.
    func matches(_ needle: String) -> Bool {
        haystack.contains { $0.contains(needle) }
    }
}

private enum BuiltInCatalog {
    static let all = BuiltInDictionary.terms.map(BuiltInItem.init)

    /// "653 terms · AI, frontend, backend, design".
    static var summary: String {
        String(localized: "\(BuiltInDictionary.terms.count) terms") + " · "
            + String(localized: "AI, frontend, backend, design", comment: "Topics of the built-in dictionary, after its term count")
    }

    static func items(category: String?, needle: String) -> [BuiltInItem] {
        guard category != nil || !needle.isEmpty else { return all }
        return all.filter { item in
            (category == nil || item.term.category == category) && (needle.isEmpty || item.matches(needle))
        }
    }
}

extension BuiltInDictionary.Category {
    /// The catalog ships English titles; the interface shows them in its own language.
    var localizedTitle: String {
        switch key {
        case "ai": String(localized: "AI and agents", comment: "Built-in dictionary category")
        case "frontend": String(localized: "Frontend", comment: "Built-in dictionary category")
        case "backend": String(localized: "Backend", comment: "Built-in dictionary category")
        case "data": String(localized: "Databases and data", comment: "Built-in dictionary category")
        case "devops": String(localized: "DevOps and cloud", comment: "Built-in dictionary category")
        case "mobile": String(localized: "Apple and mobile", comment: "Built-in dictionary category")
        case "design": String(localized: "Design", comment: "Built-in dictionary category")
        case "tools": String(localized: "Tools and services", comment: "Built-in dictionary category")
        case "slang": String(localized: "Acronyms and slang", comment: "Built-in dictionary category")
        default: title
        }
    }
}

/// Read-only row of the built-in dictionary, dimmed while the dictionary is off.
private struct BuiltInTermRow: View {
    let item: BuiltInItem
    let isOn: Bool

    var body: some View {
        VStack(spacing: 0) {
            DictionaryRowLayout {
                Group {
                    if item.heard.isEmpty {
                        Text(verbatim: "—").foregroundStyle(.white.opacity(0.4))
                    } else {
                        Text(verbatim: item.heard)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(item.heard)
                    }
                }
                .padding(.trailing, 16)
            } arrow: {
                Icon(.arrowRight, size: 16, stroke: 2).opacity(0.6)
            } written: {
                if item.isCode {
                    Text(verbatim: item.term.written)
                        .font(.mono(13.5))
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.2)))
                } else {
                    Text(verbatim: item.term.written)
                        .lineLimit(1)
                }
            } source: {
                SourceLabel(title: "built-in")
            } delete: {
                Color.clear
            }
            .frame(height: 52)
            .opacity(isOn ? 1 : 0.55)
            RowDivider(opacity: 0.13)
        }
    }
}

// MARK: Parts

/// "Your terms 12" above a group of rows.
private struct GroupHeader: View {
    let title: LocalizedStringKey
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                PanelLabel(title)
                if count > 0 {
                    Text(verbatim: Format.grouped(count))
                        .font(.onest(12.5, .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 22)
            .frame(height: 38)
            .background(.white.opacity(0.05))
            RowDivider(opacity: 0.13)
        }
    }
}

/// Stands in for the user's rows while there are none.
private struct EmptyGroupRow: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("No terms")
                .font(.onest(14.5))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.leading, 22)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            RowDivider(opacity: 0.13)
        }
    }
}

/// "manual", "from history", "built-in".
private struct SourceLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.onest(12))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(.white.opacity(0.16)))
    }
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
