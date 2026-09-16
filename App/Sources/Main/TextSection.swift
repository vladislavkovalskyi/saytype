import SwiftUI
import VMCore

struct TextSection: View {
    @Environment(AppModel.self) private var model
    private let world = MainSection.text.world

    var body: some View {
        @Bindable var settings = model.settings
        ZStack(alignment: .topLeading) {
            HeaderArt(name: "ObjectTextcard", width: 290, right: -20, top: -36)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader("Text", subtitle: "How speech becomes text")
                        .frame(height: 78, alignment: .topLeading)

                    ExamplePanel(world: world, punctuation: settings.value.punctuationStyle, letterCase: settings.value.letterCase)
                        .frame(width: 1068, height: 150)
                        .frost(hot: true)

                    HStack(alignment: .top, spacing: 16) {
                        StylePanel(accent: world.accent)
                            .frame(width: 526)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .frost()

                        FillerPanel()
                            .frame(width: 526, alignment: .topLeading)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .frost()
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 0) {
                            ToggleRow("Smart structure", detailText: Text(model.dictation.smart.detail), isOn: model.smartStructureBinding, accent: world.accent)
                            RowDivider()
                            SettingsRow("Applies to") {
                                MenuChip(title: minimumWords(settings.value.smartStructureMinWords), items: [20, 40, 80].map { words in
                                    MenuOption(title: minimumWords(words), isOn: settings.value.smartStructureMinWords == words) {
                                        settings.value.smartStructureMinWords = words
                                    }
                                })
                            }
                            .opacity(settings.value.smartStructure ? 1 : 0.5)
                            .disabled(!settings.value.smartStructure)
                        }
                        .frame(width: 526)
                        .opacity(settings.value.punctuationStyle == .full ? 1 : 0.5)
                        .disabled(settings.value.punctuationStyle != .full)
                        .frost()

                        VStack(spacing: 0) {
                            SettingsRow("Speech language", detail: settings.value.language.isTuned ? nil : "formatting tuned for Russian and English") {
                                MenuChip(title: languageTitle(settings.value.language), items: languageItems(settings))
                            }
                            RowDivider()
                            ToggleRow("Mask swear words", detail: "first letter stays", isOn: $settings.value.censorProfanity, accent: world.accent)
                        }
                        .frame(width: 526)
                        .frost()
                    }

                    VStack(spacing: 0) {
                        ToggleRow("Terms in Latin script", detailText: Text(CodeWords.attributed(String(localized: "useEffect, Vercel, Supabase stay as in code"), size: 12.5)), isOn: $settings.value.latinTerms, accent: world.accent)
                        RowDivider()
                        ToggleRow("Drop the period after short phrases", detail: "for agent commands and search", isOn: $settings.value.dropTrailingPeriodInShortPhrases, accent: world.accent)
                            .opacity(settings.value.punctuationStyle == .full ? 1 : 0.5)
                            .disabled(settings.value.punctuationStyle != .full)
                        RowDivider()
                        ToggleRow("Voice commands", detail: "“new line”, “new paragraph”, “delete last sentence”, “open quote … close quote”, “send it” at the end", isOn: $settings.value.voiceCommands, accent: world.accent)
                    }
                    .frame(width: 1068)
                    .frost()
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
            // Panels fade out at the bottom edge instead of being cut.
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 20)
                }
            }
        }
    }

    /// "40+ words": smart structure starts at this dictation length.
    private func minimumWords(_ count: Int) -> String {
        String(localized: "\(count)+ words", comment: "Minimum dictation length for smart structure, after Applies to")
    }

    /// Russian and English are named in their own language, the rest in the interface language.
    private func languageTitle(_ language: AppSettings.SpeechLanguage) -> String {
        switch language {
        case .russian: "Русский"
        case .english: "English"
        case .auto: String(localized: "Auto", comment: "Speech language detected automatically")
        default: language.localizedName()
        }
    }

    private func languageItems(_ settings: SettingsStore) -> [MenuOption] {
        var items: [MenuOption] = []
        for language in AppSettings.SpeechLanguage.all() {
            if language != .russian, language != .english, language != .auto, items.count == 3 {
                items.append(.separator)
            }
            items.append(MenuOption(title: languageTitle(language), isOn: settings.value.language == language) {
                settings.value.language = language
            })
        }
        return items
    }
}

/// Chat style, punctuation and letter case.
private struct StylePanel: View {
    @Environment(AppModel.self) private var model
    let accent: Color

    var body: some View {
        @Bindable var settings = model.settings
        let value = settings.value
        VStack(spacing: 0) {
            ToggleRow("Chat style", detail: "lowercase, commas only", isOn: $settings.value.isChatStyle, accent: accent)
            RowDivider()
            SettingsRow("Punctuation", detailText: Text(punctuationDetail(value.punctuationStyle))) {
                WorldSegmented(selection: $settings.value.punctuationStyle, options: [
                    (.full, "Full"),
                    (.commas, "Commas"),
                    (.none, "None"),
                ])
            }
            RowDivider()
            SettingsRow("Letter case", detailText: Text(value.letterCase == .lowercase ? "API and useEffect keep their case" : "capital letter at the start of a sentence")) {
                WorldSegmented(selection: $settings.value.letterCase, titles: [
                    (.asSpoken, Text(verbatim: "Aa")),
                    (.lowercase, Text(verbatim: "aa")),
                ])
            }
        }
    }

    private func punctuationDetail(_ style: AppSettings.PunctuationStyle) -> LocalizedStringKey {
        switch style {
        case .full: "new paragraph after a 1.5 s pause"
        case .commas: "no periods or question marks"
        case .none: "no marks, one paragraph"
        }
    }
}

private struct ExamplePanel: View {
    let world: World
    let punctuation: AppSettings.PunctuationStyle
    let letterCase: AppSettings.LetterCase

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                PanelLabel("As spoken")
                Text(raw)
                    .font(.mono(13.5))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Icon(.arrowRight, size: 20, stroke: 2.2)
                .foregroundStyle(world.accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white).shadow(color: .black.opacity(0.15), radius: 8, y: 6))
                .frame(width: 48)

            VStack(alignment: .leading, spacing: 6) {
                PanelLabel("Result")
                DictatedText(text: result, size: 17, lineHeight: 1.5, codeOpacity: 0.22, codeWords: ["Header"])
                    .animation(.snappy(duration: 0.2), value: result)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The sample in the chosen punctuation and letter case.
    private var result: String {
        var text = String(localized: "So, fix useEffect in Header, it flickers on every render.", comment: "Formatted sample dictation; keep useEffect and Header as they are")
        switch punctuation {
        case .full: break
        case .commas: text = Punctuation.strip(text, keeping: [","])
        case .none: text = Punctuation.strip(text)
        }
        if letterCase == .lowercase { text = Letters.lowercase(text, keeping: ["Header"]) }
        return text
    }

    private var raw: AttributedString {
        var filler = AttributedString(String(localized: "um", comment: "Struck-out hesitation at the start of the raw sample dictation"))
        filler.strikethroughStyle = .single
        filler.foregroundColor = .white.opacity(0.5)
        return filler + AttributedString(" " + String(localized: "so fix use effect in header it flickers on every render", comment: "Raw sample dictation as the speech model hears it, before formatting"))
    }
}

private struct FillerPanel: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""

    /// The Russian words the cleanup removes, shown as they are in every language.
    private static let hesitations = ["эээ", "ммм", "ааа"]
    private static let fillers = ["ну", "типа", "короче", "как бы", "в общем"]

    var body: some View {
        @Bindable var settings = model.settings
        let mode = settings.value.fillerMode
        let filters = settings.value.wordFilters
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Filler words").font(.onest(14.5, .medium))
                Spacer()
                WorldSegmented(selection: $settings.value.fillerMode, options: [(.keep, "Keep"), (.hesitations, "Hesitations"), (.all, "All")])
            }
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(Self.hesitations, id: \.self) { word in
                    WordChip(word: word, isRemoved: mode != .keep)
                }
                ForEach(Self.fillers, id: \.self) { word in
                    WordChip(word: word, isRemoved: mode == .all)
                }
                ForEach(filters, id: \.self) { word in
                    WordChip(word: word, isRemoved: true) {
                        settings.value.wordFilters.removeAll { $0 == word }
                    }
                }
                AddWordField(text: $draft) { add($0) }
            }
            .padding(.top, 18)
            Text(filters.isEmpty ? "Add your own words to remove them everywhere." : "Your words are removed in every mode.")
                .font(.onest(13))
                .foregroundStyle(.white.opacity(0.74))
                .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .animation(.snappy(duration: 0.2), value: mode)
        .animation(.snappy(duration: 0.2), value: filters)
    }

    private func add(_ word: String) {
        let word = word.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        draft = ""
        guard !word.isEmpty, !model.settings.value.wordFilters.contains(word) else { return }
        model.settings.value.wordFilters.append(word)
    }
}

/// Chip-sized field that adds a word to the filters on Return.
private struct AddWordField: View {
    @Binding var text: String
    let commit: (String) -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Icon(.plus, size: 13, stroke: 2)
                .opacity(0.8)
            // The placeholder or the typed word sets the width; the field sits on top.
            (text.isEmpty ? Text("Add word") : Text(verbatim: text + "  "))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(isFocused ? 0.45 : 0.7))
                .opacity(text.isEmpty ? 1 : 0)
                .frame(maxWidth: 200, alignment: .leading)
                .fixedSize()
                .overlay(alignment: .leading) {
                    TextField(text: $text) { EmptyView() }
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit { commit(text) }
                }
        }
        .font(.onest(13))
        .foregroundStyle(.white)
        .tint(.white)
        .padding(.leading, 9)
        .padding(.trailing, 11)
        .frame(height: 28)
        .background(Capsule().strokeBorder(.white.opacity(isFocused ? 0.5 : 0.28), style: StrokeStyle(lineWidth: 1, dash: isFocused ? [] : [3, 3])))
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
    }
}

private struct WordChip: View {
    let word: String
    let isRemoved: Bool
    /// Set for the user's own words: shows a remove button.
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(word)
                .strikethrough(isRemoved)
                .opacity(isRemoved ? 0.6 : 1)
            if let onDelete {
                Button(action: onDelete) {
                    Icon(.xmark, size: 11, stroke: 2)
                        .frame(width: 16, height: 16)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(0.8)
            }
        }
        .font(.onest(13))
        .padding(.leading, 11)
        .padding(.trailing, onDelete == nil ? 11 : 6)
        .frame(height: 28)
        .background(Capsule().fill(.white.opacity(onDelete == nil ? 0.16 : 0.24)))
        .opacity(isRemoved && onDelete == nil ? 0.6 : 1)
    }
}
