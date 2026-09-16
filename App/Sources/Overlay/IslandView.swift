import AppKit
import SwiftUI
import VMAudio
import VMCore
import VMSystem

/// The island: a black shape that grows out of the camera notch.
struct IslandView: View {
    let model: OverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var notch: NotchMetrics { .shared }

    enum Mode: Equatable {
        case idle
        case peek
        case panel
        case listening(expanded: Bool)
        case finishing
        case inserted
        case notice(DictationController.Notice)
        case card(String)
    }

    private var mode: Mode {
        let dictation = model.dictation
        switch dictation.phase {
        case .listening:
            return .listening(expanded: !(dictation.committedText.isEmpty && dictation.pendingText.isEmpty))
        case .finishing:
            return .finishing
        case .card(let text):
            return .card(text)
        case .inserted:
            return model.hover == .open ? .panel : .inserted
        case .notice(let notice):
            return model.hover == .open ? .panel : .notice(notice)
        case .idle:
            switch model.hover {
            case .none: return .idle
            case .peek: return .peek
            case .open: return .panel
            }
        }
    }

    private struct Geometry: Equatable {
        var size: CGSize
        var ear: CGFloat
        var radius: CGFloat
    }

    private func geometry(_ mode: Mode) -> Geometry {
        let base = max(notch.width, 150)
        let h = notch.height
        switch mode {
        case .idle:
            return Geometry(size: CGSize(width: base, height: h), ear: 0, radius: 10)
        case .peek:
            return Geometry(size: CGSize(width: base + 72, height: h + 6), ear: 8, radius: 15)
        case .panel:
            return Geometry(size: CGSize(width: 444, height: h + 150), ear: 14, radius: 28)
        case .listening(let expanded):
            return expanded
                ? Geometry(size: CGSize(width: 464, height: h + textRowHeight), ear: 14, radius: 26)
                : Geometry(size: CGSize(width: base + 144, height: h), ear: 8, radius: 12)
        case .finishing:
            return Geometry(size: CGSize(width: 464, height: h + textRowHeight), ear: 14, radius: 26)
        case .inserted:
            return Geometry(size: CGSize(width: base + 96, height: h), ear: 8, radius: 12)
        case .notice(let notice):
            let side = max(TextMeasure.width(notice.measuredTitle, size: 12) + 40, 60)
            return Geometry(size: CGSize(width: base + side * 2, height: h), ear: 8, radius: 12)
        case .card(let text):
            let lineHeight: CGFloat = 20.5
            let textHeight = min(TextMeasure.height(text, width: 416, size: 14, lineHeight: lineHeight), lineHeight * 8)
            return Geometry(size: CGSize(width: 464, height: h + textHeight + 62), ear: 14, radius: 28)
        }
    }

    /// One line of live text needs less room than two; the island grows when it wraps.
    private var textRowHeight: CGFloat {
        let text = [model.dictation.committedText, model.dictation.pendingText].joined(separator: " ")
        return TextMeasure.width(text, size: 15) > 410 ? 76 : 55
    }

    var body: some View {
        let mode = mode
        let shape = geometry(mode)
        ZStack(alignment: .top) {
            IslandShape(ear: shape.ear, radius: shape.radius)
                .fill(.black)
                .frame(width: shape.size.width + shape.ear * 2, height: shape.size.height)
                .shadow(color: OverlayPalette.ember.opacity(glow(mode)), radius: 24, y: 12)
            content(mode)
                .frame(width: shape.size.width, height: shape.size.height, alignment: .top)
                .clipped()
        }
        .frame(width: shape.size.width + shape.ear * 2, height: shape.size.height, alignment: .top)
        .foregroundStyle(.white)
        // A screen without a notch has nothing to hide behind: the resting island disappears.
        .opacity(mode == .idle && !notch.hasNotch ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.hitFrame = $0 }
        .animation(.island(reduceMotion: reduceMotion), value: shape)
        .animation(.island(reduceMotion: reduceMotion), value: mode)
    }

    private func glow(_ mode: Mode) -> Double {
        guard case .listening = mode else { return 0 }
        return Double(model.dictation.currentLevel) * 0.85
    }

    @ViewBuilder private func content(_ mode: Mode) -> some View {
        switch mode {
        case .idle:
            Color.clear
        case .peek:
            IslandTopRow(inset: 12) {
                Image(systemName: "waveform").font(.system(size: 11, weight: .bold)).foregroundStyle(OverlayPalette.ember)
            } trailing: {
                KeyCap(label: model.settings.value.recordKey.capLabel)
            }
            .frame(height: notch.height + 6)
            .transition(.islandContent)
        case .panel:
            IslandPanel(model: model).transition(.islandContent)
        case .listening(let expanded):
            IslandListening(model: model, expanded: expanded, finishing: false).transition(.islandContent)
        case .finishing:
            IslandListening(model: model, expanded: true, finishing: true).transition(.islandContent)
        case .inserted:
            IslandTopRow {
                if case .inserted(let target) = model.dictation.phase {
                    AppIconBadge(icon: target?.icon)
                }
            } trailing: {
                DoneCheck()
            }
            .transition(.islandContent)
        case .notice(let notice):
            IslandTopRow {
                Image(systemName: notice.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(notice == .copied ? OverlayPalette.done : OverlayPalette.warning)
            } trailing: {
                Text(notice.title).font(.onest(12, .medium)).foregroundStyle(.white.opacity(0.88)).fixedSize()
            }
            .transition(.islandContent)
        case .card(let text):
            IslandCard(model: model, text: text).transition(.islandContent)
        }
    }
}

/// The row level with the notch: content sits in the "ears" left and right of the camera.
struct IslandTopRow<Leading: View, Trailing: View>: View {
    var inset: CGFloat = 18
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: NotchMetrics.shared.width + 8)
            trailing
        }
        .padding(.horizontal, inset)
        .frame(height: NotchMetrics.shared.height)
    }
}

// MARK: Listening

private struct IslandListening: View {
    let model: OverlayModel
    let expanded: Bool
    let finishing: Bool

    var body: some View {
        let dictation = model.dictation
        VStack(alignment: .leading, spacing: 0) {
            IslandTopRow {
                if finishing {
                    SpinnerRing()
                } else {
                    VoiceBars(levels: Array(dictation.levels.suffix(9)))
                }
            } trailing: {
                HStack(spacing: 8) {
                    if let startedAt = dictation.startedAt, !finishing {
                        Text(startedAt, style: .timer)
                            .font(.mono(11, .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .monospacedDigit()
                            .fixedSize()
                    }
                    if dictation.handsFree, !finishing {
                        Button {
                            dictation.toggleRecordingFromOverlay()
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(IslandIconButtonStyle(size: 22))
                        .help(Text("Stop"))
                    }
                }
            }
            if expanded {
                Group {
                    if finishing {
                        LiveWords(committed: [dictation.committedText, dictation.pendingText].joined(separator: " "), pending: "", dimPending: false)
                            .modifier(Shimmer())
                    } else {
                        LiveWords(committed: dictation.committedText, pending: dictation.pendingText)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .transition(.islandContent)
            }
        }
    }
}

// MARK: Panel

private struct IslandPanel: View {
    let model: OverlayModel
    @State private var copied = false

    var body: some View {
        let dictation = model.dictation
        VStack(spacing: 0) {
            IslandTopRow {
                ModelStatus(model: model)
            } trailing: {
                Button {
                    model.collapse()
                    model.openMain(.home)
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(IslandIconButtonStyle(size: 22, filled: false))
                .help(Text("Settings"))
            }

            HStack(spacing: 14) {
                Button {
                    model.collapse()
                    dictation.toggleRecordingFromOverlay()
                } label: {
                    RecordOrb()
                }
                .buttonStyle(.plain)
                .help(Text("Record"))

                LastDictation(record: dictation.lastRecord, keyLabel: model.settings.value.recordKey.capLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let record = dictation.lastRecord {
                    VStack(spacing: 6) {
                        Button {
                            Paster.copy(record.text)
                            copied = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.2))
                                copied = false
                            }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(IslandIconButtonStyle())
                        .help(Text("Copy"))
                        Button {
                            model.collapse()
                            dictation.insertAgain(record)
                        } label: {
                            Image(systemName: "arrow.uturn.left")
                        }
                        .buttonStyle(IslandIconButtonStyle())
                        .help(Text("Paste again"))
                    }
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .padding(.top, 10)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                LanguageSwitch(settings: model.settings)
                SmartChip(isOn: model.smartStructure)
                MicrophoneChip(model: model)
                Spacer(minLength: 0)
                Button {
                    model.collapse()
                    model.openMain(.history)
                } label: {
                    Text("History")
                }
                .buttonStyle(IslandChipStyle())
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 13)
        }
    }
}

/// Left ear of the panel: silent when the model is ready, a readout otherwise.
private struct ModelStatus: View {
    let model: OverlayModel

    var body: some View {
        HStack(spacing: 6) {
            switch model.dictation.modelState {
            case .ready:
                EmptyView()
            case .loading:
                SpinnerRing(size: 10)
                Text("Preparing model")
            case .downloading(let fraction):
                SpinnerRing(size: 10)
                Text("Model \(Int(fraction * 100))%")
            case .missing:
                Button {
                    model.collapse()
                    model.openMain(.model)
                } label: {
                    Text("Download model")
                }
                .buttonStyle(.plain)
                .foregroundStyle(OverlayPalette.emberHigh)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(OverlayPalette.warning)
                Text("Model error")
            }
        }
        .font(.onest(11.5, .medium))
        .foregroundStyle(.white.opacity(0.72))
        .lineLimit(1)
    }
}

private struct LastDictation: View {
    let record: DictationRecord?
    let keyLabel: String

    var body: some View {
        if let record {
            VStack(alignment: .leading, spacing: 4) {
                Text(CodeWords.attributed(record.text.replacingOccurrences(of: "\n", with: " "), size: 13.5))
                    .font(.onest(13.5))
                    .lineSpacing(1.5)
                    .lineLimit(2)
                Text(record.overlayMeta)
                    .font(.onest(11.5))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onDrag { NSItemProvider(object: record.text as NSString) }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("No dictations yet").font(.onest(13.5, .medium))
                HStack(spacing: 6) {
                    KeyCap(label: keyLabel)
                    Text("hold to record").font(.onest(11.5)).foregroundStyle(.white.opacity(0.46))
                }
            }
        }
    }
}

private struct LanguageSwitch: View {
    let settings: SettingsStore

    var body: some View {
        HStack(spacing: 0) {
            option(.russian, "RU")
            option(.english, "EN")
            option(.auto, "Auto")
        }
        .padding(2)
        .frame(height: 26)
        .background(Capsule().fill(.white.opacity(0.1)))
    }

    private func option(_ language: AppSettings.SpeechLanguage, _ title: LocalizedStringKey) -> some View {
        let selected = settings.value.language == language
        return Button {
            settings.value.language = language
        } label: {
            Text(title)
                .font(.onest(11, .semibold))
                .foregroundStyle(selected ? Color(hex: 0x111111) : .white.opacity(0.62))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(selected ? .white : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: selected)
    }
}

private struct SmartChip: View {
    let isOn: Binding<Bool>

    var body: some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                    Capsule().fill(isOn.wrappedValue ? OverlayPalette.ember : .white.opacity(0.22))
                    Circle().fill(.white).padding(2)
                }
                .frame(width: 20, height: 12)
                Text("Structure")
            }
            .animation(.snappy(duration: 0.2), value: isOn.wrappedValue)
        }
        .buttonStyle(IslandChipStyle())
        .help(Text("Lists and paragraphs in long dictations"))
    }
}

private struct MicrophoneChip: View {
    let model: OverlayModel
    @State private var anchor = OverlayMenuAnchor()

    var body: some View {
        let device = AudioDevices.resolve(uid: model.settings.value.microphoneUID)
        Button {
            showMenu()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "mic.fill").font(.system(size: 9.5, weight: .semibold))
                Text(device?.name ?? String(localized: "No microphone"))
                    .frame(maxWidth: 92, alignment: .leading)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(IslandChipStyle())
        .background(OverlayMenuAnchorView(anchor: anchor))
    }

    private func showMenu() {
        let settings = model.settings
        let current = settings.value.microphoneUID
        var items = [OverlayMenuItem(title: String(localized: "System default"), isOn: current == nil) { settings.value.microphoneUID = nil }]
        for device in AudioDevices.inputs() {
            items.append(OverlayMenuItem(title: device.name, isOn: device.uid == current) { settings.value.microphoneUID = device.uid })
        }
        model.withMenu { anchor.pop(items) }
    }
}

// MARK: Card

private struct IslandCard: View {
    let model: OverlayModel
    let text: String

    var body: some View {
        let dictation = model.dictation
        VStack(alignment: .leading, spacing: 0) {
            IslandTopRow {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            } trailing: {
                Button {
                    dictation.dismissCard()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IslandIconButtonStyle(size: 22, filled: false))
                .help(Text("Close"))
            }
            Text(CodeWords.attributed(text, size: 14))
                .font(.onest(14))
                .lineSpacing(3.5)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .contentShape(Rectangle())
                .onDrag { NSItemProvider(object: text as NSString) }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button("Copy") { dictation.copyCard() }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                Button("Paste") { dictation.insertCard() }
                    .buttonStyle(CapsuleButtonStyle())
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
    }
}

// MARK: Shape

/// Black shape that continues the camera notch: concave top corners, round bottom.
struct IslandShape: Shape {
    var ear: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, radius) }
        set { ear = newValue.first; radius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        // The ears sit inside the frame: the body spans [minX + ear, maxX - ear].
        var p = Path()
        let left = rect.minX + ear
        let right = rect.maxX - ear
        let r = min(radius, rect.height / 2, (right - left) / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: left, y: rect.minY + ear), control: CGPoint(x: left, y: rect.minY))
        p.addLine(to: CGPoint(x: left, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: left + r, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        p.addLine(to: CGPoint(x: right - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - r), control: CGPoint(x: right, y: rect.maxY))
        p.addLine(to: CGPoint(x: right, y: rect.minY + ear))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: Menus from the overlay

struct OverlayMenuItem {
    let title: String
    let isOn: Bool
    let action: @MainActor () -> Void
}

/// Pops a native menu under a view inside the non-activating overlay panel.
@MainActor
final class OverlayMenuAnchor {
    weak var view: NSView?

    /// Blocks until the menu closes, like `NSMenu.popUp`.
    func pop(_ items: [OverlayMenuItem]) {
        guard let view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            menu.addItem(ClosureMenuItem(title: item.title, isOn: item.isOn, action: item.action))
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }
}

struct OverlayMenuAnchorView: NSViewRepresentable {
    let anchor: OverlayMenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = FlippedAnchorView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

private final class FlippedAnchorView: NSView {
    override var isFlipped: Bool { true }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, isOn: Bool = false, keyEquivalent: String = "", action: @escaping @MainActor () -> Void) {
        handler = action
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
        state = isOn ? .on : .off
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func fire() {
        let handler = handler
        MainActor.assumeIsolated { handler() }
    }
}

extension AppSettings.RecordKey {
    /// Text on the small key cap in overlays.
    var capLabel: String {
        switch self {
        case .fn: "fn"
        case .rightOption: "⌥"
        case .rightCommand: "⌘"
        }
    }
}
