import AppKit
import SwiftUI
import VMCore
import VMTranscription

/// Names and sizes of the Whisper variants saytype offers.
struct WhisperModelInfo: Equatable {
    static let turbo = "large-v3-v20240930_turbo_632MB"
    static let large = "large-v3_947MB"

    let variant: String

    var isTurbo: Bool { variant.contains("turbo") }
    var title: String { isTurbo ? "Whisper large-v3-turbo" : "Whisper large-v3" }
    var shortTitle: String { isTurbo ? "Whisper turbo" : "Whisper large-v3" }
    var megabytes: Int { isTurbo ? 632 : 947 }
    /// Approximate resident memory once loaded.
    var memoryGB: Double { isTurbo ? 1.0 : 1.5 }
    var summary: String { isTurbo ? String(localized: "faster, live text") : String(localized: "more accurate, slower") }
    var other: WhisperModelInfo { WhisperModelInfo(variant: isTurbo ? Self.large : Self.turbo) }
}

struct ModelSection: View {
    @Environment(AppModel.self) private var model
    private let world = MainSection.model.world
    /// Previews of the language model panel (`--show-language-model`) open scrolled down to it.
    private let showsLanguageModel = AppModel.isPreviewLaunch && ProcessInfo.processInfo.arguments.contains("--show-language-model")

    var body: some View {
        @Bindable var settings = model.settings
        let info = WhisperModelInfo(variant: settings.value.whisperModel)
        let rewriter = model.dictation.rewriter
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Model", subtitle: "Everything is transcribed on this Mac")
                    .frame(height: 84, alignment: .topLeading)

                HStack(alignment: .top, spacing: 16) {
                    CurrentModelCard(info: info)
                        .frame(width: 620, height: 300, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .frost(hot: true)

                    OtherModelsPanel(info: info, world: world)
                        .frame(width: 432, height: 300, alignment: .topLeading)
                        .frost()
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        VStack(spacing: 0) {
                            ToggleRow("Smart structure", detailText: Text(model.dictation.smart.detail), isOn: model.smartStructureBinding, accent: world.accent)
                            RowDivider()
                            SettingsRow("Model files", detailText: Text(verbatim: abbreviatedPath(ModelStore.defaultBase))) {
                                Button("Show") {
                                    let url = ModelStore.defaultBase
                                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                                    NSWorkspace.shared.open(url)
                                }
                                .buttonStyle(ChipButtonStyle())
                            }
                        }
                        .frost()

                        LanguageModelPanel(world: world)
                            .frost()
                    }
                    .frame(width: 620)

                    MemoryPanel(info: info, smartStructure: model.dictation.smart.isOn(settings.value), languageModel: rewriter.memoryPart(settings.value))
                        .frame(width: 432, height: 268, alignment: .topLeading)
                        .frost()
                }
                .padding(.top, 16)
            }
            .padding(.bottom, 20)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(showsLanguageModel ? .bottom : .top)
        // Panels fade out at the bottom edge instead of being cut.
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 20)
            }
        }
    }

    private func abbreviatedPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

// MARK: Current model

private struct CurrentModelCard: View {
    @Environment(AppModel.self) private var model
    let info: WhisperModelInfo

    var body: some View {
        let dictation = model.dictation
        let state = dictation.modelState
        ZStack(alignment: .topLeading) {
            Image("ObjectChip")
                .resizable()
                .scaledToFit()
                .frame(width: 258, height: 258)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 30, y: 40)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                StateBadge(state: state)
                Text(info.title)
                    .font(.onest(28, .bold))
                    .tracking(-0.56)
                    .padding(.top, 12)
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 8) {
                    spec("Size", String(localized: "\(info.megabytes) MB"))
                    spec("Language", language)
                    spec("Live text", String(localized: "yes"))
                    spec("Preparation", preparation(state))
                }
                .font(.onest(14))
                .padding(.top, 16)

                Spacer(minLength: 0)
                action(state: state, dictation: dictation)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }

    private func spec(_ name: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(name)
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 120, alignment: .leading)
            Text(value)
        }
    }

    private var language: String {
        switch model.settings.value.language {
        case .russian: String(localized: "Russian, English terms", comment: "Speech language of the model")
        case .english: String(localized: "English", comment: "Speech language of the model")
        case .auto: String(localized: "detected from speech", comment: "Speech language of the model")
        case let language: language.localizedName()
        }
    }

    private func preparation(_ state: DictationController.ModelState) -> String {
        switch state {
        case .ready: String(localized: "done for \(MacInfo.chip)", comment: "Model preparation; the argument is a chip name such as M3 Pro")
        case .loading: String(localized: "in progress for \(MacInfo.chip)", comment: "Model preparation; the argument is a chip name such as M3 Pro")
        case .downloading, .missing: String(localized: "after download", comment: "Model preparation")
        case .failed: String(localized: "error", comment: "Last rewrite state")
        }
    }

    @ViewBuilder
    private func action(state: DictationController.ModelState, dictation: DictationController) -> some View {
        switch state {
        case .missing:
            Button(action: dictation.downloadModel) {
                Label { Text("Download") } icon: { Icon(.download, size: 14, stroke: 2.2) }
                    .labelStyle(IconFirstLabelStyle())
            }
            .buttonStyle(WhiteButtonStyle())
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "\(Int((fraction * 100).rounded()))% · " + String(localized: "\(Int((fraction * Double(info.megabytes)).rounded())) of \(info.megabytes) MB", comment: "Download progress in megabytes"))
                    .font(.onest(13, .medium))
                ProgressTrack(fraction: fraction)
                    .frame(width: 300)
            }
        case .failed(let message):
            HStack(spacing: 12) {
                Button("Retry") {
                    if dictation.isModelDownloaded {
                        dictation.loadModelIfPresent()
                    } else {
                        dictation.downloadModel()
                    }
                }
                .buttonStyle(WhiteButtonStyle())
                Text(message)
                    .font(.onest(12.5))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(2)
                    .frame(maxWidth: 260, alignment: .leading)
            }
        case .loading, .ready:
            EmptyView()
        }
    }
}

private struct StateBadge: View {
    let state: DictationController.ModelState

    var body: some View {
        HStack(spacing: 6) {
            switch state {
            case .ready:
                Icon(.check, size: 13, stroke: 2.6)
            case .loading, .downloading:
                ProgressView().controlSize(.mini).tint(Color(hex: 0x0F6AA8))
            case .missing:
                Icon(.download, size: 13, stroke: 2.4)
            case .failed:
                Icon(.xmark, size: 13, stroke: 2.6)
            }
            Text(title).font(.onest(12.5, .semibold))
        }
        .foregroundStyle(Color(hex: 0x0F6AA8))
        .padding(.leading, 8)
        .padding(.trailing, 11)
        .frame(height: 26)
        .background(Capsule().fill(.white))
        .fixedSize()
    }

    private var title: String {
        switch state {
        case .ready: String(localized: "In use", comment: "Model state badge")
        case .loading: String(localized: "Preparing", comment: "Model state badge")
        case .downloading: String(localized: "Downloading", comment: "Model state badge")
        case .missing: String(localized: "Not downloaded", comment: "Model state badge")
        case .failed: String(localized: "Failed to load", comment: "Model state badge")
        }
    }
}

// MARK: Other models

private struct OtherModelsPanel: View {
    @Environment(AppModel.self) private var model
    let info: WhisperModelInfo
    let world: World

    var body: some View {
        @Bindable var settings = model.settings
        let other = info.other
        let busy = isBusy(model.dictation.modelState)
        let downloaded = ModelStore().isDownloaded(other.variant)
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("Other models")
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(other.title).font(.onest(17, .semibold))
                    Text("\(other.megabytes) MB · \(other.summary)", comment: "Model size, then a short summary such as faster, live text")
                        .font(.onest(13))
                        .foregroundStyle(.white.opacity(0.74))
                }
                Spacer(minLength: 0)
                Button {
                    use(other)
                } label: {
                    if downloaded {
                        Text("Use")
                    } else {
                        Label { Text("Download") } icon: { Icon(.download, size: 14, stroke: 2.2) }
                            .labelStyle(IconFirstLabelStyle())
                    }
                }
                .buttonStyle(WhiteButtonStyle())
                .disabled(busy)
                .opacity(busy ? 0.5 : 1)
            }
            .padding(.top, 14)

        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    private func isBusy(_ state: DictationController.ModelState) -> Bool {
        switch state {
        case .downloading, .loading: true
        default: false
        }
    }

    private func use(_ other: WhisperModelInfo) {
        let dictation = model.dictation
        model.settings.value.whisperModel = other.variant
        if dictation.isModelDownloaded {
            dictation.loadModelIfPresent()
        } else {
            dictation.downloadModel()
        }
    }
}

// MARK: Language model

/// Engine for mode rewrites and translations: off, the built-in Qwen3 4B, Ollama or LM Studio.
private struct LanguageModelPanel: View {
    @Environment(AppModel.self) private var model
    let world: World

    var body: some View {
        @Bindable var settings = model.settings
        let rewriter = model.dictation.rewriter
        let engine = settings.value.languageModel.engine
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                RowTitle(title: "Language model", detail: Text(summary(rewriter, settings: settings.value)))
                Spacer(minLength: 0)
                WorldSegmented(selection: $settings.value.languageModel.engine, titles: [
                    (.off, Text("Off", comment: "Language model engine: none")),
                    (.builtIn, Text(verbatim: "Qwen3 4B")),
                    (.ollama, Text(verbatim: "Ollama")),
                    (.lmStudio, Text(verbatim: "LM Studio")),
                ])
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 64)

            switch engine {
            case .off:
                EmptyView()
            case .builtIn:
                RowDivider()
                BuiltInModelRows(rewriter: rewriter)
            case .ollama, .lmStudio:
                RowDivider()
                ServerRows(engine: engine, rewriter: rewriter)
            }

            if engine != .off {
                RowDivider()
                OptionalDetailRow("Timeout", detail: lastRunText(rewriter.lastRun)) {
                    MenuChip(title: seconds(settings.value.languageModel.timeoutSeconds), items: [5.0, 10, 20, 30].map { value in
                        MenuOption(title: seconds(value), isOn: settings.value.languageModel.timeoutSeconds == value) {
                            settings.value.languageModel.timeoutSeconds = value
                        }
                    })
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: engine)
    }

    private func summary(_ rewriter: RewriteService, settings: AppSettings) -> String {
        switch rewriter.state(for: settings) {
        case .off: String(localized: "rewrite and translation", comment: "Language model panel detail when the engine is off: what modes use it for")
        case .missing: String(localized: "not set up", comment: "Language model state")
        case .downloading(let fraction): String(localized: "downloading", comment: "Smart structure model state, followed by a percentage") + " · \(Int(fraction * 100))%"
        case .ready: String(localized: "ready", comment: "Language model state")
        // The server row under it names the reason.
        case .failed(let message): settings.languageModel.engine == .builtIn ? message : String(localized: "unavailable", comment: "Language model state")
        }
    }

    /// "last rewrite 1.8 s · 41 tok/s", or nothing before the first one.
    private func lastRunText(_ run: RewriteService.LastRun?) -> String? {
        guard let run else { return nil }
        let time = String(localized: "\(Format.decimal(run.seconds)) s", comment: "Duration in seconds; the argument is a formatted decimal such as 1.8")
        let outcome: String = switch run.outcome {
        case .applied: run.tokensPerSecond > 0 ? String(localized: "\(Int(run.tokensPerSecond.rounded())) tok/s", comment: "Generation speed in tokens per second") : ""
        case .rejected: String(localized: "not applied", comment: "Last rewrite: the validator rejected the answer")
        case .timedOut: String(localized: "timed out", comment: "Last rewrite state")
        case .failed: String(localized: "error", comment: "Last rewrite state")
        }
        let parts = [String(localized: "last rewrite \(time)", comment: "Readout under Timeout; the argument is a duration such as 1.8 s"), outcome].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private func seconds(_ value: Double) -> String {
        String(localized: "\(Int(value)) s", comment: "Timeout in whole seconds")
    }
}

private struct BuiltInModelRows: View {
    let rewriter: RewriteService

    var body: some View {
        SettingsRow("Qwen3 4B Instruct", detailText: Text(detail)) {
            action
        }
        if rewriter.builtInDownloaded {
            RowDivider()
            SettingsRow("Memory", detailText: Text(memoryDetail)) {
                Text("\(Format.decimal(gigabytes)) GB", comment: "Memory in gigabytes; the argument is a formatted decimal such as 1.5")
                    .font(.onest(15, .semibold))
                    .monospacedDigit()
                    .opacity(rewriter.builtInLoaded ? 1 : 0.6)
            }
        }
    }

    private var detail: String {
        let size = String(localized: "\(Format.decimal(rewriter.downloadGigabytes)) GB", comment: "Memory in gigabytes; the argument is a formatted decimal such as 1.5")
        if let progress = rewriter.downloadProgress {
            let done = String(localized: "\(Format.decimal(progress * rewriter.downloadGigabytes)) of \(Format.decimal(rewriter.downloadGigabytes)) GB", comment: "Download progress in gigabytes")
            return "\(Int((progress * 100).rounded()))% · " + done
        }
        if let error = rewriter.builtInError { return error }
        return size + " · MLX · " + String(localized: "4-bit", comment: "Model quantization")
    }

    private var gigabytes: Double {
        rewriter.builtInLoaded && rewriter.memoryBytes > 0 ? Double(rewriter.memoryBytes) / 1e9 : rewriter.loadedGigabytes
    }

    private var memoryDetail: String {
        if rewriter.builtInLoading { return String(localized: "loading", comment: "Language model memory state") }
        return rewriter.builtInLoaded
            ? String(localized: "loaded", comment: "Language model memory state")
            : String(localized: "not loaded", comment: "Language model memory state")
    }

    @ViewBuilder
    private var action: some View {
        if let progress = rewriter.downloadProgress {
            HStack(spacing: 12) {
                ProgressTrack(fraction: progress)
                    .frame(width: 180)
                Button("Cancel", action: rewriter.cancelDownload)
                    .buttonStyle(ChipButtonStyle())
            }
        } else if rewriter.builtInDownloaded {
            Button {
                rewriter.removeBuiltIn()
            } label: {
                Label { Text("Remove", comment: "Delete the downloaded model") } icon: { Icon(.trash, size: 14, stroke: 2) }
                    .labelStyle(IconFirstLabelStyle())
            }
            .buttonStyle(ChipButtonStyle())
        } else {
            Button(action: rewriter.downloadBuiltIn) {
                Label { rewriter.builtInError == nil ? Text("Download") : Text("Retry") } icon: { Icon(.download, size: 14, stroke: 2.2) }
                    .labelStyle(IconFirstLabelStyle())
            }
            .buttonStyle(WhiteButtonStyle())
        }
    }
}

private struct ServerRows: View {
    @Environment(AppModel.self) private var model
    let engine: AppSettings.LanguageModel.Engine
    let rewriter: RewriteService

    var body: some View {
        @Bindable var settings = model.settings
        let value = settings.value
        let status = rewriter.status(for: value)
        SettingsRow("Server", detailText: statusText(status)) {
            HStack(spacing: 10) {
                AddressField(address: engine == .ollama ? $settings.value.languageModel.ollamaURL : $settings.value.languageModel.lmStudioURL)
                Button("Check") { rewriter.checkServer(settings.value, force: true) }
                    .buttonStyle(ChipButtonStyle())
                    .disabled(status.phase == .checking)
            }
        }
        RowDivider()
        OptionalDetailRow("Model", detail: modelDetail(status, selected: RewriteService.modelName(value, engine))) {
            MenuChip(title: modelTitle(status, selected: RewriteService.modelName(value, engine)), items: status.models.map { name in
                MenuOption(title: name, isOn: RewriteService.modelName(value, engine) == name) {
                    if engine == .ollama {
                        settings.value.languageModel.ollamaModel = name
                    } else {
                        settings.value.languageModel.lmStudioModel = name
                    }
                }
            })
            .disabled(status.models.isEmpty)
            .opacity(status.models.isEmpty ? 0.5 : 1)
        }
        .task(id: RewriteService.url(value, engine)) {
            // Typing an address checks it once the user pauses.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            rewriter.checkServer(settings.value)
        }
    }

    private func statusText(_ status: RewriteService.ServerStatus) -> Text {
        switch status.phase {
        case .unknown: Text(verbatim: engine == .ollama ? "Ollama" : "LM Studio")
        case .checking: Text("checking", comment: "Language model server state")
        case .connected: Text("connected · models: \(status.models.count)", comment: "Language model server state with the number of models")
        case .unreachable(let message): Text(verbatim: message)
        }
    }

    private func modelTitle(_ status: RewriteService.ServerStatus, selected: String) -> String {
        if !selected.isEmpty { return selected }
        return status.models.isEmpty ? String(localized: "No models", comment: "Model picker without models") : String(localized: "Choose", comment: "Model picker without a selection")
    }

    private func modelDetail(_ status: RewriteService.ServerStatus, selected: String) -> String? {
        guard status.phase == .connected, !selected.isEmpty, !status.models.isEmpty, !status.models.contains(selected) else { return nil }
        return String(localized: "not on the server", comment: "The selected model is missing from the server")
    }
}

/// A settings row whose detail line appears only when there is something to show.
private struct OptionalDetailRow<Accessory: View>: View {
    let title: LocalizedStringKey
    let detail: String?
    let accessory: Accessory

    init(_ title: LocalizedStringKey, detail: String?, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        if let detail {
            SettingsRow(title, detailText: Text(verbatim: detail)) { accessory }
        } else {
            SettingsRow(title) { accessory }
        }
    }
}

/// Server address in a code font; saved on Return or when the field loses focus.
private struct AddressField: View {
    @Binding var address: String
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(text: $text) { EmptyView() }
            .textFieldStyle(.plain)
            .font(.mono(13))
            .foregroundStyle(.white)
            .tint(.white)
            .focused($isFocused)
            .onSubmit { address = text.trimmingCharacters(in: .whitespaces) }
            .padding(.horizontal, 12)
            .frame(width: 230, height: 32)
            .background(Capsule().fill(.white.opacity(isFocused ? 0.2 : 0.14)))
            .overlay(Capsule().strokeBorder(.white.opacity(isFocused ? 0.4 : 0.16), lineWidth: 1))
            .onAppear { text = address }
            .onChange(of: address) { _, newValue in
                if !isFocused { text = newValue }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { address = text.trimmingCharacters(in: .whitespaces) }
            }
    }
}

extension RewriteService {
    /// The built-in model's share in the memory panel when it is the engine and on disk.
    fileprivate func memoryPart(_ settings: AppSettings) -> (name: String, gigabytes: Double)? {
        guard settings.languageModel.engine == .builtIn, builtInDownloaded else { return nil }
        let gigabytes = builtInLoaded && memoryBytes > 0 ? Double(memoryBytes) / 1e9 : loadedGigabytes
        return ("Qwen3 4B", gigabytes)
    }
}

// MARK: Memory

private struct MemoryPanel: View {
    let info: WhisperModelInfo
    let smartStructure: Bool
    /// Name and gigabytes of the built-in language model when it is the engine.
    let languageModel: (name: String, gigabytes: Double)?

    private struct Part: Identifiable {
        let name: String
        let gigabytes: Double
        let opacity: Double
        var id: String { name }
    }

    var body: some View {
        let parts = [Part(name: info.shortTitle, gigabytes: info.memoryGB, opacity: 1)]
            + (smartStructure ? [Part(name: "Qwen3 1.7B", gigabytes: 1.0, opacity: 0.62)] : [])
            + (languageModel.map { [Part(name: $0.name, gigabytes: $0.gigabytes, opacity: 0.38)] } ?? [])
        let total = parts.reduce(0) { $0 + $1.gigabytes }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                PanelLabel("Memory")
                Spacer()
                Text("\(Format.decimal(total)) GB", comment: "Memory in gigabytes; the argument is a formatted decimal such as 1.5")
                    .font(.onest(26, .bold))
                    .tracking(-0.26)
            }
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(parts) { part in
                        Rectangle()
                            .fill(.white.opacity(part.opacity))
                            .frame(width: proxy.size.width * part.gigabytes / total)
                    }
                }
            }
            .frame(height: 16)
            .background(.white.opacity(0.16))
            .clipShape(Capsule())
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(parts) { part in
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(part.opacity))
                            .frame(width: 10, height: 10)
                            .padding(.trailing, 8)
                        Text(part.name)
                        Spacer()
                        Text("\(Format.decimal(part.gigabytes)) GB", comment: "Memory in gigabytes; the argument is a formatted decimal such as 1.5")
                    }
                }
            }
            .font(.onest(14))
            .padding(.top, 18)

            Text("of \(MacInfo.memoryGB) GB on this Mac")
                .font(.onest(13))
                .foregroundStyle(.white.opacity(0.74))
                .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .animation(.smooth(duration: 0.3), value: smartStructure)
        .animation(.smooth(duration: 0.3), value: languageModel?.gigabytes)
    }
}

enum MacInfo {
    /// "M3 Pro".
    static let chip: String = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.hasPrefix("Apple ") ? String(name.dropFirst(6)) : name
    }()

    static let memoryGB = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
}
