import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VMCore

struct ModesSection: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID = DictationMode.standardID
    private let world = MainSection.modes.world

    var body: some View {
        @Bindable var settings = model.settings
        ZStack(alignment: .topLeading) {
            HeaderArt(name: "ObjectSwitches", width: 230, right: 10, top: -30)

            VStack(alignment: .leading, spacing: 16) {
                SectionHeader("Modes", subtitle: "Text rules for each app")
                    .frame(height: 78, alignment: .topLeading)

                HStack(alignment: .top, spacing: 16) {
                    ModeList(selectedID: $selectedID)
                        .frame(width: 330)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .frost()

                    if let index = settings.value.modes.firstIndex(where: { $0.id == selectedID }) {
                        ModeEditor(mode: $settings.value.modes[index], world: world) {
                            delete(settings.value.modes[index])
                        }
                        .id(selectedID)
                        .frame(width: 722)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .frost()
                    }
                }
                .frame(height: 560)
            }
        }
        .onAppear {
            if !settings.value.modes.contains(where: { $0.id == selectedID }) {
                selectedID = DictationMode.standardID
            }
        }
    }

    private func delete(_ mode: DictationMode) {
        guard !mode.isBuiltIn else { return }
        withAnimation(.snappy(duration: 0.2)) {
            model.settings.value.modes.removeAll { $0.id == mode.id }
            if model.settings.value.fixedModeID == mode.id { model.settings.value.fixedModeID = nil }
            selectedID = DictationMode.standardID
        }
    }
}

// MARK: List

private struct ModeList: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedID: String

    var body: some View {
        let settings = model.settings.value
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PanelLabel("Active")
                Spacer()
                MenuChip(title: settings.fixedModeID.flatMap { id in settings.modes.first { $0.id == id }?.title } ?? DictationMode.automaticTitle, items: selectionItems)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            RowDivider()

            ScrollView(.vertical) {
                VStack(spacing: 4) {
                    ForEach(settings.modes) { mode in
                        ModeRow(mode: mode, isSelected: mode.id == selectedID, isActive: settings.fixedModeID == mode.id) {
                            selectedID = mode.id
                        }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.never)

            RowDivider()
            Button(action: addMode) {
                HStack(spacing: 6) {
                    Icon(.plus, size: 14, stroke: 2)
                    Text("New mode")
                }
            }
            .buttonStyle(ChipButtonStyle())
            .padding(14)
        }
    }

    private var selectionItems: [MenuOption] {
        let settings = model.settings
        var items = [MenuOption(title: DictationMode.automaticTitle, isOn: settings.value.fixedModeID == nil) {
            settings.value.fixedModeID = nil
        }, .separator]
        for mode in settings.value.modes {
            items.append(MenuOption(title: mode.title, isOn: settings.value.fixedModeID == mode.id) {
                settings.value.fixedModeID = mode.id
            })
        }
        return items
    }

    private func addMode() {
        let settings = model.settings.value
        // A new mode starts from the Text section, so it behaves like the standard mode until changed.
        let mode = DictationMode(
            id: UUID().uuidString,
            name: String(localized: "New mode", comment: "Default name of a mode the user creates"),
            punctuationStyle: settings.punctuationStyle,
            letterCase: settings.letterCase,
            fillerMode: settings.fillerMode,
            smartStructure: settings.smartStructure,
            dropTrailingPeriod: settings.dropTrailingPeriodInShortPhrases
        )
        withAnimation(.snappy(duration: 0.2)) {
            model.settings.value.modes.append(mode)
            selectedID = mode.id
        }
    }
}

private struct ModeRow: View {
    let mode: DictationMode
    let isSelected: Bool
    /// Picked by hand, so it applies in every app.
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.onest(14.5, .medium))
                        .lineLimit(1)
                    Text(summary)
                        .font(.onest(12.5))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isActive {
                    Text("on")
                        .font(.onest(11.5, .semibold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Capsule().fill(.white))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(isSelected ? 0.2 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// "Telegram, WhatsApp +4", or where the mode applies when it has no apps.
    private var summary: String {
        if mode.isStandard { return String(localized: "all other apps", comment: "Where the standard mode applies") }
        let installed = ModeApps.installed(mode.apps)
        guard !installed.isEmpty else { return String(localized: "by hand", comment: "A mode without apps is picked in the menu or with the shortcut") }
        let names = installed.prefix(2).map(ModeApps.name(for:)).joined(separator: ", ")
        return installed.count > 2 ? names + " +\(installed.count - 2)" : names
    }
}

// MARK: Editor

private struct ModeEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var mode: DictationMode
    let world: World
    let delete: () -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                header
                AppsGroup(mode: $mode)
                styleGroup
                codeGroup
                languageModelGroup
                deliveryGroup
            }
            .padding(20)
        }
        .scrollIndicators(.never)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if mode.isBuiltIn {
                Text(mode.title).font(.onest(22, .bold))
            } else {
                TextField(text: $mode.name) { Text("Mode name") }
                    .textFieldStyle(.plain)
                    .font(.onest(22, .bold))
                    .tint(.white)
            }
            Spacer(minLength: 0)
            if mode.isBuiltIn, !mode.isStandard, let original = DictationMode.defaults.first(where: { $0.id == mode.id }), original != mode {
                Button("Restore") {
                    withAnimation(.snappy(duration: 0.2)) { mode = original }
                }
                .buttonStyle(ChipButtonStyle())
            }
            if !mode.isBuiltIn {
                Button(action: delete) {
                    HStack(spacing: 6) {
                        Icon(.trash, size: 14)
                        Text("Delete")
                    }
                }
                .buttonStyle(ChipButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var styleGroup: some View {
        let settings = model.settings.value
        GroupBox(title: "Style") {
            if mode.isStandard {
                SettingsRow("Punctuation, letter case, filler words", detailText: Text(standardStyleSummary(settings))) {
                    Button("Open Text") { model.mainSection = .text }
                        .buttonStyle(ChipButtonStyle())
                }
            } else {
                SettingsRow("Punctuation") {
                    WorldSegmented(selection: $mode.punctuationStyle, options: [(.full, "Full"), (.commas, "Commas"), (.none, "None")])
                }
                RowDivider()
                SettingsRow("Letter case") {
                    WorldSegmented(selection: $mode.letterCase, titles: [(.asSpoken, Text(verbatim: "Aa")), (.lowercase, Text(verbatim: "aa"))])
                }
                RowDivider()
                SettingsRow("Filler words") {
                    WorldSegmented(selection: $mode.fillerMode, options: [(.keep, "Keep"), (.hesitations, "Hesitations"), (.all, "All")])
                }
                RowDivider()
                ToggleRow("Smart structure", detail: settings.smartStructure ? "lists and paragraphs in long dictations" : "turned off in Text", isOn: $mode.smartStructure, accent: world.accent)
                    .disabled(mode.punctuationStyle != .full || !settings.smartStructure)
                    .opacity(mode.punctuationStyle == .full && settings.smartStructure ? 1 : 0.5)
                RowDivider()
                ToggleRow("Drop the period after short phrases", isOn: $mode.dropTrailingPeriod, accent: world.accent)
                    .disabled(mode.punctuationStyle != .full)
                    .opacity(mode.punctuationStyle == .full ? 1 : 0.5)
            }
        }
    }

    private var codeGroup: some View {
        GroupBox(title: "Code") {
            ToggleRow("Spoken code", detailText: Text(CodeWords.attributed(String(localized: "“camel case user data” → userData, paths, =>"), size: 12.5)), isOn: $mode.developer, accent: world.accent)
            RowDivider()
            ToggleRow("Code in backticks", detailText: Text(CodeWords.attributed(String(localized: "`useEffect` for Markdown in agents and GitHub"), size: 12.5)), isOn: $mode.backticks, accent: world.accent)
        }
    }

    @ViewBuilder
    private var languageModelGroup: some View {
        let engineOff = model.settings.value.languageModel.engine == .off
        GroupBox(title: "Language model") {
            SettingsRow("Rewrite", detailText: Text(rewriteDetail)) {
                MenuChip(title: rewriteTitle(mode.rewrite), items: DictationMode.Rewrite.allCases.map { style in
                    MenuOption(title: rewriteTitle(style), isOn: mode.rewrite == style) { mode.rewrite = style }
                })
            }
            if mode.rewrite == .custom {
                InstructionField(text: $mode.instruction)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
            }
            RowDivider()
            ToggleRow("Translate to English", detail: "speak in any language", isOn: $mode.translateToEnglish, accent: world.accent)
            if engineOff, mode.rewrite != .none || mode.translateToEnglish {
                RowDivider()
                SettingsRow("Language model is off", detail: mode.rewrite != .none ? "text is inserted without the rewrite" : "Whisper translates, terms may change") {
                    Button("Set up") { model.mainSection = .model }
                        .buttonStyle(WhiteButtonStyle())
                }
            }
        }
    }

    private var deliveryGroup: some View {
        let global = model.settings.value.outputMode
        return GroupBox(title: "After recording") {
            SettingsRow("Output") {
                MenuChip(title: outputTitle(mode.outputMode, global: global), items: [nil, AppSettings.OutputMode.paste, .card, .clipboard].map { output in
                    MenuOption(title: outputTitle(output, global: global), isOn: mode.outputMode == output) { mode.outputMode = output }
                })
            }
            RowDivider()
            ToggleRow("Return after paste", detail: "in every app of this mode", isOn: $mode.pressReturn, accent: world.accent)
        }
    }

    private var rewriteDetail: String {
        switch mode.rewrite {
        case .none: String(localized: "text as spoken", comment: "Rewrite: none")
        case .prompt: String(localized: "goal, context, steps; files and names stay", comment: "Rewrite: agent prompt")
        case .commit: String(localized: "Conventional Commit in English", comment: "Rewrite: commit")
        case .cleaner: String(localized: "without repeats and corrections", comment: "Rewrite: cleaner")
        case .custom: String(localized: "your instruction", comment: "Rewrite: custom")
        }
    }

    private func rewriteTitle(_ style: DictationMode.Rewrite) -> String {
        switch style {
        case .none: String(localized: "Off", comment: "Rewrite style menu")
        case .prompt: String(localized: "Agent prompt", comment: "Rewrite style menu")
        case .commit: String(localized: "Commit", comment: "Rewrite style menu")
        case .cleaner: String(localized: "Cleaner", comment: "Rewrite style menu")
        case .custom: String(localized: "Own instruction", comment: "Rewrite style menu")
        }
    }

    private func outputTitle(_ output: AppSettings.OutputMode?, global: AppSettings.OutputMode) -> String {
        switch output {
        case nil: String(localized: "As in Key and overlay", comment: "Mode output follows the global setting")
        case .paste: String(localized: "Paste")
        case .card: String(localized: "Card")
        case .clipboard: String(localized: "Clipboard")
        }
    }

    private func standardStyleSummary(_ settings: AppSettings) -> String {
        if settings.isChatStyle { return String(localized: "chat style", comment: "Summary of the Text section style") }
        switch settings.punctuationStyle {
        case .full: return String(localized: "full punctuation", comment: "Summary of the Text section style")
        case .commas: return String(localized: "commas only", comment: "Summary of the Text section style")
        case .none: return String(localized: "no punctuation", comment: "Summary of the Text section style")
        }
    }
}

/// A titled frost group inside the editor.
private struct GroupBox<Content: View>: View {
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

private struct InstructionField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("For example: turn this into a bug report with steps to reproduce")
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .tint(.white)
        }
        .font(.onest(13.5))
        .frame(height: 76)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(isFocused ? 0.18 : 0.12)))
    }
}

// MARK: Apps

private struct AppsGroup: View {
    @Binding var mode: DictationMode

    var body: some View {
        GroupBox(title: "Apps") {
            if mode.isStandard {
                SettingsRow("Every app without its own mode", detail: "the other modes switch on in their apps") { EmptyView() }
            } else {
                let installed = ModeApps.installed(mode.apps)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(installed, id: \.self) { bundleID in
                        AppChip(bundleID: bundleID) {
                            mode.apps.removeAll { $0 == bundleID }
                        }
                    }
                    Button(action: chooseApp) {
                        HStack(spacing: 6) {
                            Icon(.plus, size: 14, stroke: 2)
                            Text("Add app")
                        }
                        .font(.onest(13, .medium))
                        .padding(.leading, 9)
                        .padding(.trailing, 12)
                        .frame(height: 30)
                        .background(ChipFill())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                if installed.isEmpty {
                    Text("Without apps the mode is picked in the menu bar, on the island or with ⌃⌥M.")
                        .font(.onest(12.5))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
            }
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add", comment: "Confirm button of the app picker")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier, !mode.apps.contains(bundleID) else { continue }
            mode.apps.append(bundleID)
        }
    }
}

private struct AppChip: View {
    let bundleID: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if !AppModel.isPreviewLaunch, let url = InstalledApps.url(for: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(ModeApps.name(for: bundleID))
            Button(action: remove) {
                Icon(.xmark, size: 11, stroke: 2)
                    .frame(width: 16, height: 16)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(0.8)
        }
        .font(.onest(13, .medium))
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 30)
        .background(Capsule().fill(.white.opacity(0.2)))
    }
}

/// Apps of a mode that are on this Mac. Previews show a fixed set with readable names,
/// so screenshots don't depend on what is installed here.
private enum ModeApps {
    private static let previewNames = [
        "ru.keepcoder.Telegram": "Telegram", "net.whatsapp.WhatsApp": "WhatsApp", "com.hnc.Discord": "Discord",
        "com.apple.Terminal": "Terminal", "com.todesktop.230313mzl4w4u92": "Cursor", "com.mitchellh.ghostty": "Ghostty",
        "com.anthropic.claudefordesktop": "Claude", "com.openai.chat": "ChatGPT", "com.microsoft.VSCode": "Visual Studio Code",
        "com.apple.mail": "Mail", "com.readdle.SparkDesktop": "Spark",
    ]

    static func installed(_ apps: [String]) -> [String] {
        if AppModel.isPreviewLaunch { return apps.filter { previewNames[$0] != nil } }
        return apps.filter { InstalledApps.url(for: $0) != nil }
    }

    static func name(for bundleID: String) -> String {
        if AppModel.isPreviewLaunch, let name = previewNames[bundleID] { return name }
        return InstalledApps.name(for: bundleID)
    }
}
