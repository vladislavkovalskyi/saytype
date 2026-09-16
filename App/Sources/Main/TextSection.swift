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
                SectionHeader("Текст", subtitle: "Как сказанное становится текстом")
                    .frame(height: 78, alignment: .topLeading)

                ExamplePanel(world: world)
                    .frame(width: 1068, height: 150)
                    .frost(hot: true)

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 0) {
                        ToggleRow("Пунктуация и абзацы", detail: "новый абзац после паузы 1,5 с", isOn: $settings.value.punctuation, accent: world.accent)
                        RowDivider()
                        ToggleRow("Умная структура", detail: model.dictation.smart.detail, isOn: model.smartStructureBinding, accent: world.accent)
                        RowDivider()
                        SettingsRow("Включать с") {
                            MenuChip(title: Format.count(settings.value.smartStructureMinWords, "слова", "слов", "слов"), items: [20, 40, 80].map { words in
                                MenuOption(title: "\(words) слов", isOn: settings.value.smartStructureMinWords == words) {
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
                    SettingsRow("Язык речи") {
                        WorldSegmented(selection: $settings.value.language, options: [(.russian, "Русский"), (.english, "English"), (.auto, "Авто")])
                    }
                    RowDivider()
                    ToggleRow("Термины латиницей", detailText: Text(CodeWords.attributed("useEffect, Vercel, Supabase остаются как в коде", size: 12.5)), isOn: $settings.value.latinTerms, accent: world.accent)
                    RowDivider()
                    ToggleRow("Удалять точку в конце короткой фразы", detail: "для команд агенту и поиска", isOn: $settings.value.dropTrailingPeriodInShortPhrases, accent: world.accent)
                }
                .frame(width: 1068)
                .frost()
            }
        }
    }
}

private struct ExamplePanel: View {
    let world: World

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                PanelLabel("Как сказал")
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
                PanelLabel("Результат")
                DictatedText(text: "Так, поправь useEffect в Header, он дёргается при каждом рендере.", size: 17, lineHeight: 1.5, codeOpacity: 0.22, codeWords: ["Header"])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var raw: AttributedString {
        var filler = AttributedString("эээ")
        filler.strikethroughStyle = .single
        filler.foregroundColor = .white.opacity(0.5)
        return filler + AttributedString(" так поправь юз эффект в хедере он дёргается при каждом рендере")
    }
}

private struct FillerPanel: View {
    @Environment(AppModel.self) private var model

    private static let hesitations = ["эээ", "ммм", "ааа"]
    private static let fillers = ["ну", "типа", "короче", "как бы", "в общем"]

    var body: some View {
        @Bindable var settings = model.settings
        let mode = settings.value.fillerMode
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Слова-паразиты").font(.onest(14.5, .medium))
                Spacer()
                WorldSegmented(selection: $settings.value.fillerMode, options: [(.keep, "Оставлять"), (.hesitations, "Мычание"), (.all, "Все")])
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
            Text("Остальные слова не меняются.")
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
