import SwiftUI
import VMCore

struct TextSection: View {
    @Environment(AppModel.self) private var model
    private let world = MainSection.text.world

    var body: some View {
        @Bindable var settings = model.settings
        ZStack(alignment: .topLeading) {
            HeaderArt(name: "ObjectTextcard", width: 290, right: -20, top: -36)

            VStack(alignment: .leading, spacing: 16) {
                SectionHeader("Text", subtitle: "How speech becomes text")
                    .frame(height: 78, alignment: .topLeading)

                ExamplePanel(world: world)
                    .frame(width: 1068, height: 150)
                    .frost(hot: true)

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 0) {
                        ToggleRow("Punctuation and paragraphs", detail: "new paragraph after a 1.5 s pause", isOn: $settings.value.punctuation, accent: world.accent)
                        RowDivider()
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
                    .frost()

                    FillerPanel()
                        .frame(width: 526, height: 190, alignment: .topLeading)
                        .frost()
                }

                VStack(spacing: 0) {
                    SettingsRow("Speech language") {
                        // Language names are written in their own language.
                        WorldSegmented(selection: $settings.value.language, titles: [
                            (.russian, Text(verbatim: "Русский")),
                            (.english, Text(verbatim: "English")),
                            (.auto, Text("Auto", comment: "Speech language detected automatically")),
                        ])
                    }
                    RowDivider()
                    ToggleRow("Terms in Latin script", detailText: Text(CodeWords.attributed(String(localized: "useEffect, Vercel, Supabase stay as in code"), size: 12.5)), isOn: $settings.value.latinTerms, accent: world.accent)
                    RowDivider()
                    ToggleRow("Drop the period after short phrases", detail: "for agent commands and search", isOn: $settings.value.dropTrailingPeriodInShortPhrases, accent: world.accent)
                }
                .frame(width: 1068)
                .frost()
            }
        }
    }

    /// "40+ words": smart structure starts at this dictation length.
    private func minimumWords(_ count: Int) -> String {
        String(localized: "\(count)+ words", comment: "Minimum dictation length for smart structure, after Applies to")
    }
}

private struct ExamplePanel: View {
    let world: World

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
                DictatedText(text: String(localized: "So, fix useEffect in Header, it flickers on every render.", comment: "Formatted sample dictation; keep useEffect and Header as they are"), size: 17, lineHeight: 1.5, codeOpacity: 0.22, codeWords: ["Header"])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxHeight: .infinity, alignment: .top)
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

    /// The Russian words the cleanup removes, shown as they are in every language.
    private static let hesitations = ["эээ", "ммм", "ааа"]
    private static let fillers = ["ну", "типа", "короче", "как бы", "в общем"]

    var body: some View {
        @Bindable var settings = model.settings
        let mode = settings.value.fillerMode
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
            }
            .padding(.top, 22)
            Text("Other words stay unchanged.")
                .font(.onest(13))
                .foregroundStyle(.white.opacity(0.74))
                .padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .animation(.snappy(duration: 0.2), value: mode)
    }
}

private struct WordChip: View {
    let word: String
    let isRemoved: Bool

    var body: some View {
        Text(word)
            .font(.onest(13))
            .strikethrough(isRemoved)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(.white.opacity(0.16)))
            .opacity(isRemoved ? 0.6 : 1)
    }
}
