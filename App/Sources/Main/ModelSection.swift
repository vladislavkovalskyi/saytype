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

    var body: some View {
        @Bindable var settings = model.settings
        let info = WhisperModelInfo(variant: settings.value.whisperModel)
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
                .frame(width: 620)
                .frost()

                MemoryPanel(info: info, smartStructure: model.dictation.smart.isOn(settings.value))
                    .frame(width: 432, height: 268, alignment: .topLeading)
                    .frost()
            }
            .padding(.top, 16)
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
        case .failed: String(localized: "failed", comment: "Model preparation")
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

// MARK: Memory

private struct MemoryPanel: View {
    let info: WhisperModelInfo
    let smartStructure: Bool

    private struct Part: Identifiable {
        let name: String
        let gigabytes: Double
        let opacity: Double
        var id: String { name }
    }

    var body: some View {
        let parts = [Part(name: info.shortTitle, gigabytes: info.memoryGB, opacity: 1)]
            + (smartStructure ? [Part(name: "Qwen3 1.7B", gigabytes: 1.0, opacity: 0.62)] : [])
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
