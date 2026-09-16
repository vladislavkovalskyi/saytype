import SwiftUI
import VMCore

struct HomeSection: View {
    @Binding var section: MainSection

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 16) {
                ReadyTile()
                    .frame(width: 660, height: 360)
                HistoryTile { section = .history }
                    .frame(width: 660, height: 292)
            }
            VStack(spacing: 16) {
                ModelTile { section = .model }
                    .frame(width: 392, height: 172)
                DictionaryTile { section = .dictionary }
                    .frame(width: 392, height: 172)
                TextTile { section = .text }
                    .frame(width: 392, height: 292)
            }
        }
    }
}

// MARK: Tile

/// Object art placement in a tile, measured like the mockup: offsets beyond the tile's bottom right corner.
private struct TileArt {
    let name: String
    let width: CGFloat
    let right: CGFloat
    let bottom: CGFloat
}

private struct Tile<Content: View>: View {
    let title: LocalizedStringKey
    var art: TileArt?
    var action: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(title)
                .font(.onest(15, .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .padding(.leading, 22)
                .padding(.top, 18)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .bottomTrailing) {
            if let art {
                Image(art.name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: art.width * 0.92, height: art.width * 0.92)
                    .frame(width: art.width, height: art.width)
                    .offset(x: -art.right, y: -art.bottom)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frost(cornerRadius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { action?() }
    }
}

private struct TileValue: View {
    let value: Text
    let detail: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            value
                .font(.onest(21, .semibold))
                .tracking(-0.2)
            detail
                .font(.onest(13))
                .foregroundStyle(.white.opacity(0.74))
        }
        .padding(.leading, 22)
        .padding(.top, 70)
    }
}

// MARK: Ready

private struct ReadyTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let dictation = model.dictation
        let info = WhisperModelInfo(variant: model.settings.value.whisperModel)
        ZStack(alignment: .topLeading) {
            Text(state.title)
                .font(.onest(15, .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .padding(.leading, 22)
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: 0) {
                Text(headline(info: info))
                    .font(.onest(46, .bold))
                    .tracking(-1.15)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 400, alignment: .leading)
                Text(detail(info: info))
                    .font(.onest(14))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(3)
                    .frame(width: 230, alignment: .leading)
                    .padding(.top, 4)
                action(dictation: dictation, info: info)
                    .padding(.top, 18)
            }
            .padding(.leading, 22)
            .padding(.top, 66)

            HStack(alignment: .top, spacing: 34) {
                Stat(value: dictation.stats.wordsToday, caption: String(localized: "\(dictation.stats.wordsToday) words today", comment: "Caption under the number; the plural forms leave the number out"))
                Stat(value: dictation.stats.wordsPerMinute, caption: String(localized: "\(dictation.stats.wordsPerMinute) words per minute", comment: "Caption under the number; the plural forms leave the number out"))
            }
            .padding(.leading, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .topLeading) {
            Image("ObjectCapsule")
                .resizable()
                .scaledToFit()
                .frame(width: 650)
                .offset(x: 270, y: 76)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frost(cornerRadius: 20, hot: true)
    }

    private var state: DictationController.ModelState {
        model.dictation.modelState
    }

    private func headline(info: WhisperModelInfo) -> String {
        switch state {
        case .ready: String(localized: "Hold \(model.settings.value.recordKey.inlineName)", comment: "The argument is the record key, e.g. fn or right ⌥")
        case .downloading(let fraction): "\(Int((fraction * 100).rounded()))%"
        case .missing, .loading, .failed: info.shortTitle
        }
    }

    private func detail(info: WhisperModelInfo) -> String {
        switch state {
        case .ready:
            model.settings.value.overlayStyle == .island
                ? String(localized: "Overlay appears at the camera notch")
                : String(localized: "Overlay appears at the bottom of the screen")
        case .downloading(let fraction):
            String(localized: "\(Int((fraction * Double(info.megabytes)).rounded())) of \(info.megabytes) MB", comment: "Download progress in megabytes")
        case .missing, .loading:
            String(localized: "\(info.megabytes) MB · offline")
        case .failed(let message):
            message
        }
    }

    @ViewBuilder
    private func action(dictation: DictationController, info: WhisperModelInfo) -> some View {
        switch state {
        case .missing:
            Button {
                dictation.downloadModel()
            } label: {
                Label { Text("Download") } icon: { Icon(.download, size: 14, stroke: 2.2) }
            }
            .buttonStyle(WhiteButtonStyle())
        case .failed:
            Button("Retry") {
                if dictation.isModelDownloaded {
                    dictation.loadModelIfPresent()
                } else {
                    dictation.downloadModel()
                }
            }
            .buttonStyle(WhiteButtonStyle())
        case .downloading(let fraction):
            ProgressTrack(fraction: fraction)
                .frame(width: 280)
        case .loading:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(.white)
        case .ready:
            EmptyView()
        }
    }
}

private extension DictationController.ModelState {
    var title: String {
        switch self {
        case .ready: String(localized: "Ready to dictate")
        case .missing: String(localized: "Model not downloaded")
        case .downloading: String(localized: "Downloading model")
        case .loading: String(localized: "Preparing for \(MacInfo.chip)", comment: "Model setup stage; the argument is a chip name such as M3 Pro")
        case .failed: String(localized: "Model failed to load")
        }
    }
}

/// White bar on a translucent track.
struct ProgressTrack: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule()
                    .fill(.white)
                    .shadow(color: .white.opacity(0.8), radius: 7)
                    .frame(width: max(10, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 10)
        .animation(.smooth(duration: 0.3), value: fraction)
    }
}

private struct Stat: View {
    let value: Int
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(Format.grouped(value))
                .font(.onest(30, .bold))
                .tracking(-0.6)
            Text(caption)
                .font(.onest(13))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: Tiles

private struct ModelTile: View {
    @Environment(AppModel.self) private var model
    let action: () -> Void

    var body: some View {
        let info = WhisperModelInfo(variant: model.settings.value.whisperModel)
        Tile(title: "Model", art: TileArt(name: "ObjectChip", width: 190, right: -26, bottom: -34), action: action) {
            TileValue(value: Text(verbatim: info.shortTitle), detail: Text("offline · \(info.megabytes) MB"))
        }
    }
}

private struct DictionaryTile: View {
    @Environment(AppModel.self) private var model
    let action: () -> Void

    var body: some View {
        let settings = model.settings.value
        let entries = settings.dictionary
        let builtIn = settings.builtInDictionary ? BuiltInDictionary.terms : []
        let count = entries.count + builtIn.count
        Tile(title: "Dictionary", art: TileArt(name: "ObjectAa", width: 180, right: -18, bottom: -30), action: action) {
            if count > 0 {
                TileValue(value: Text("\(count) terms"), detail: example(entries: entries, builtIn: builtIn))
            } else {
                TileValue(value: Text("No terms"), detail: Text(verbatim: ""))
            }
        }
    }

    /// The user's newest term, otherwise a built-in one: "клод код → Claude Code".
    private func example(entries: [DictionaryEntry], builtIn: [BuiltInDictionary.Term]) -> Text {
        if let first = entries.first {
            return example(heard: first.heard, written: first.written)
        }
        let term = builtIn.first { $0.written == "Claude Code" && !$0.heard.isEmpty } ?? builtIn.first { !$0.heard.isEmpty }
        guard let term else { return Text(verbatim: "") }
        return example(heard: term.heard[0], written: term.written)
    }

    private func example(heard: String, written: String) -> Text {
        var code = AttributedString(written)
        code.font = .mono(13 * 0.88)
        guard !heard.isEmpty else { return Text(code) }
        return Text(AttributedString("\(heard) → ") + code)
    }
}

private struct HistoryTile: View {
    @Environment(AppModel.self) private var model
    let action: () -> Void

    var body: some View {
        let records = Array(model.dictation.history.prefix(4))
        Tile(title: "History", art: TileArt(name: "ObjectStack", width: 230, right: -30, bottom: -40), action: action) {
            if records.isEmpty {
                TileValue(value: Text("Nothing yet"), detail: Text(verbatim: ""))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(CodeWords.attributed(record.text.replacingOccurrences(of: "\n", with: " "), size: 14.5))
                                .font(.onest(14.5))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text([record.appName, Format.moment(record.date)].compactMap { $0 }.joined(separator: " · "))
                                .font(.onest(12.5))
                                .foregroundStyle(.white.opacity(0.68))
                        }
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if index < records.count - 1 {
                            RowDivider()
                        }
                    }
                }
                .padding(.leading, 22)
                .padding(.trailing, 200)
                .padding(.top, 56)
            }
        }
    }
}

private struct TextTile: View {
    @Environment(AppModel.self) private var model
    let action: () -> Void

    var body: some View {
        @Bindable var settings = model.settings
        Tile(title: "Text", art: TileArt(name: "ObjectTextcard", width: 230, right: -30, bottom: -44), action: action) {
            TileValue(value: Text("Smart structure"), detail: Text(model.dictation.smart.detail))
            Toggle(isOn: model.smartStructureBinding) { EmptyView() }
                .toggleStyle(WorldToggleStyle(accent: MainSection.home.world.accent))
                .frame(width: 42)
                .padding(.top, 16)
                .padding(.trailing, 20)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
        }
    }
}
