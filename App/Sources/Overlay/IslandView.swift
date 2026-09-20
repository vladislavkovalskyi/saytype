import AppKit
import SwiftUI
import VMAudio
import VMCore
import VMSystem

/// The island: a black shape that grows out of the camera notch.
///
/// One shape morphs between states. The row level with the notch stays in place and swaps only
/// the small items in its ears; live text, the panel and the card sit under it and are revealed as
/// the shape grows. `IslandSurface` interpolates the size every display frame, so the clip and the
/// hit frame follow the shape on screen.
struct IslandView: View {
    let model: OverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Height of the live text as laid out, reported by `LiveWords`.
    @State private var textHeight: CGFloat = 0
    private var notch: NotchMetrics { .shared }

    enum Mode: Equatable {
        case idle
        case peek
        case panel
        case listening
        case finishing(rewriting: Bool)
        case inserted
        case notice(DictationController.Notice)
        case card(String)
    }

    // Room for the chip row: language, mode, structure, translation, microphone.
    static let panelWidth: CGFloat = 560
    static let panelBodyHeight: CGFloat = 150
    /// The widest the island may grow inside its panel, ears included.
    private static let maxWidth = OverlayController.islandPanelSize.width - 28
    /// Space between the notch row and the live text, and under the text.
    static let textTop: CGFloat = 7
    private static let textBottom: CGFloat = 15
    /// Room for the timer in the right ear.
    private static let timerWidth: CGFloat = 34

    private var mode: Mode {
        let dictation = model.dictation
        switch dictation.phase {
        case .listening:
            return .listening
        case .finishing:
            return .finishing(rewriting: dictation.finishingStage == .rewriting)
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

    private var showsText: Bool {
        !(model.dictation.committedText.isEmpty && model.dictation.pendingText.isEmpty)
    }

    private func geometry(_ mode: Mode) -> IslandGeometry {
        let base = max(notch.width, 150)
        let h = notch.height
        switch mode {
        case .idle:
            return IslandGeometry(width: base, height: h, ear: 0, radius: 10)
        case .peek:
            return IslandGeometry(width: base + 72, height: h + 6, ear: 8, radius: 15)
        case .panel:
            return IslandGeometry(width: Self.panelWidth, height: h + Self.panelBodyHeight, ear: 14, radius: 28)
        case .listening, .finishing:
            let row = rowWidth(fitting: dictationEars)
            guard showsText else {
                return IslandGeometry(width: row, height: h, ear: 8, radius: 12)
            }
            // Before the first layout pass reports a height, assume one line.
            let text = textHeight > 0 ? textHeight : TextMeasure.lineHeight(size: 15)
            return IslandGeometry(width: textWidth + 48, height: h + Self.textTop + text + Self.textBottom, ear: 14, radius: 26)
        case .inserted:
            return IslandGeometry(width: base + 96, height: h, ear: 8, radius: 12)
        case .notice(let notice):
            let side = max(TextMeasure.width(notice.measuredTitle, size: 12) + 40, 60)
            return IslandGeometry(width: base + side * 2, height: h, ear: 8, radius: 12)
        case .card(let text):
            return IslandGeometry(width: 464, height: h + cardBodyHeight(text), ear: 14, radius: 28)
        }
    }

    /// The narrowest row that fits `content` points in each ear, and no narrower than the
    /// resting recording row.
    private func rowWidth(fitting content: CGFloat) -> CGFloat {
        let base = max(notch.width, 150)
        return min(max(base + 144, notch.width + 60 + 2 * max(content, 46)), Self.maxWidth)
    }

    /// Room for content in each ear of a row this wide: the row less the notch, the insets and
    /// the gaps around the notch.
    private func earRoom(_ width: CGFloat) -> CGFloat {
        (width - notch.width - 60) / 2
    }

    /// Width of the bars, and of the spinner's slot, so a mode tag beside them stays put.
    private static let barsWidth = VoiceBars.width(count: 9, barWidth: 3)

    /// The widest ear of any dictation stage: bars and the mode tag on the left, the timer and the
    /// stop button on the right, the rewrite label and its skip button. One width for all stages
    /// keeps the island and the wrapping of its text still from recording to insertion.
    private var dictationEars: CGFloat {
        let dictation = model.dictation
        let tag = dictation.recordingTag.map { ModeTag.width($0) + 8 } ?? 0
        let rewrite = dictation.expectsRewrite
        return max(
            Self.barsWidth + tag,
            Self.timerWidth + (dictation.handsFree ? 30 : 0),
            rewrite ? max(RewritingLabel.width, SkipRewriteButton.width) : 0
        )
    }

    /// Width of the live text: the island's width less its side margins, at least 416 points.
    private var textWidth: CGFloat {
        max(464, rowWidth(fitting: dictationEars)) - 48
    }

    private func cardBodyHeight(_ text: String) -> CGFloat {
        let lineHeight: CGFloat = 20.5
        let dictation = model.dictation
        let editing = dictation.cardEditing
        let body = editing ? dictation.cardDraft : text
        var height = min(TextMeasure.height(body, width: 416, size: 14, lineHeight: lineHeight), lineHeight * 8)
        // The editor keeps room for three lines, so the card does not shrink under the caret.
        if editing { height = max(height, lineHeight * 3) + 20 }
        if !dictation.cardLearned.isEmpty { height += 36 }
        return height + 62
    }

    var body: some View {
        let mode = mode
        let geometry = geometry(mode)
        VStack(spacing: 0) {
            IslandTopRow(inset: mode == .peek ? 12 : 18, height: notch.height + (mode == .peek ? 6 : 0)) {
                ZStack(alignment: .leading) { leadingEar(mode, width: geometry.width) }
            } trailing: {
                ZStack(alignment: .trailing) { trailingEar(mode) }
            }
            below(mode)
        }
        .modifier(IslandSurface(geometry: geometry, glows: mode == .listening, dictation: model.dictation) { model.hitFrame = $0 })
        .foregroundStyle(.white)
        // A screen without a notch has nothing to hide behind: the resting island disappears.
        .opacity(mode == .idle && !notch.hasNotch ? 0 : 1)
        .animation(.island(reduceMotion: reduceMotion), value: geometry)
        .animation(.island(reduceMotion: reduceMotion), value: mode)
    }

    // MARK: Ears

    @ViewBuilder private func leadingEar(_ mode: Mode, width: CGFloat) -> some View {
        let dictation = model.dictation
        switch mode {
        case .idle:
            EmptyView()
        case .peek:
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(OverlayPalette.ember)
                .transition(.islandContent)
        case .panel:
            ModelStatus(model: model).transition(.islandContent)
        case .listening, .finishing(rewriting: false):
            // One row for both: the spinner takes the bars' slot and the mode tag stays put.
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    if mode == .listening {
                        VoiceBars(dictation: dictation).transition(.islandContent)
                    } else {
                        SpinnerRing().transition(.islandContent)
                    }
                }
                .frame(width: Self.barsWidth, alignment: .leading)
                if let tag = dictation.recordingTag {
                    ModeTag(title: tag, maxWidth: earRoom(width) - Self.barsWidth - 8)
                        .transition(.islandContent)
                }
            }
            .transition(.islandContent)
        case .finishing(rewriting: true):
            RewritingLabel().transition(.islandContent)
        case .inserted:
            if case .inserted(let target) = dictation.phase {
                AppIconBadge(icon: target?.icon).transition(.islandContent)
            }
        case .notice(let notice):
            Image(systemName: notice.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(notice.tint(ink: .white))
                .id(notice.symbol)
                .transition(.islandContent)
        case .card:
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .transition(.islandContent)
        }
    }

    @ViewBuilder private func trailingEar(_ mode: Mode) -> some View {
        let dictation = model.dictation
        switch mode {
        case .idle:
            EmptyView()
        case .peek:
            KeyCap(label: model.settings.value.recordKey.capLabel).transition(.islandContent)
        case .panel:
            HStack(spacing: 2) {
                Button {
                    model.collapse()
                    model.openMain(.history)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(IslandIconButtonStyle(size: 22, filled: false))
                .help(Text("History"))
                Button {
                    model.collapse()
                    model.openMain(.home)
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(IslandIconButtonStyle(size: 22, filled: false))
                .help(Text("Settings"))
            }
            .transition(.islandContent)
        case .listening:
            HStack(spacing: 8) {
                if let startedAt = dictation.startedAt {
                    Text(startedAt, style: .timer)
                        .font(.mono(11, .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .monospacedDigit()
                        .fixedSize()
                }
                if dictation.handsFree {
                    Button {
                        dictation.toggleRecordingFromOverlay()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(IslandIconButtonStyle(size: 22))
                    .help(Text("Stop"))
                    .transition(.islandContent)
                }
            }
            .transition(.islandContent)
        case .finishing(rewriting: false):
            EmptyView()
        case .finishing(rewriting: true):
            SkipRewriteButton(dictation: dictation).transition(.islandContent)
        case .inserted:
            DoneCheck().transition(.islandContent)
        case .notice(let notice):
            notice.label
                .font(.onest(12, .medium))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize()
                .id(notice.measuredTitle)
                .transition(.islandContent)
        case .card:
            Button {
                dictation.dismissCard()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(IslandIconButtonStyle(size: 22, filled: false))
            .help(Text("Close"))
            .transition(.islandContent)
        }
    }

    // MARK: Below the notch

    @ViewBuilder private func below(_ mode: Mode) -> some View {
        switch mode {
        case .listening, .finishing:
            if showsText {
                IslandLiveText(model: model, width: textWidth, finishing: mode != .listening, rewriting: mode == .finishing(rewriting: true)) { textHeight = $0 }
                    .transition(.islandContent)
            }
        case .panel:
            // The rows fade in one after another on their own; leaving, the panel fades as one.
            IslandPanel(model: model)
                .transition(.asymmetric(insertion: .identity, removal: .islandContent))
        case .card(let text):
            OverlayCard(model: model, text: text)
                .frame(width: 464, height: cardBodyHeight(text), alignment: .top)
                .transition(.islandContent)
        default:
            EmptyView()
        }
    }
}

/// Size and corners of the island shape.
struct IslandGeometry: Equatable {
    var width: CGFloat
    var height: CGFloat
    var ear: CGFloat
    var radius: CGFloat
}

/// Draws the black shape behind the island's content and clips the content to it. SwiftUI
/// interpolates the geometry every display frame, so layout, the clip and the frame reported for
/// hit testing match the shape on screen for the whole transition.
private struct IslandSurface: ViewModifier, Animatable {
    var geometry: IslandGeometry
    let glows: Bool
    let dictation: DictationController
    let onFrame: (CGRect) -> Void

    nonisolated var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(geometry.width, geometry.height), AnimatablePair(geometry.ear, geometry.radius)) }
        set { geometry = IslandGeometry(width: newValue.first.first, height: newValue.first.second, ear: newValue.second.first, radius: newValue.second.second) }
    }

    func body(content: Content) -> some View {
        let shape = geometry
        let corner = min(shape.radius, shape.height / 2)
        content
            .frame(width: shape.width, height: shape.height, alignment: .top)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: corner, bottomTrailingRadius: corner))
            .frame(width: shape.width + shape.ear * 2, height: shape.height, alignment: .top)
            .background {
                // The glow follows the voice every frame while recording; otherwise its timeline is paused.
                VoiceLevel(dictation: dictation, active: glows) { level in
                    IslandShape(ear: shape.ear, radius: shape.radius)
                        .fill(.black)
                        .shadow(color: OverlayPalette.ember.opacity(level * 0.85), radius: 24, y: 12)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrame($0) }
    }
}

/// The row level with the notch: content sits in the "ears" left and right of the camera.
struct IslandTopRow<Leading: View, Trailing: View>: View {
    var inset: CGFloat = 18
    var height = NotchMetrics.shared.height
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: NotchMetrics.shared.width + 8)
            trailing
        }
        .padding(.horizontal, inset)
        .frame(height: height)
    }
}

// MARK: Live text

private struct IslandLiveText: View {
    let model: OverlayModel
    let width: CGFloat
    let finishing: Bool
    let rewriting: Bool
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        let dictation = model.dictation
        // While finishing every word counts as heard; the ids stay the same, so nothing re-enters.
        LiveWords(
            committed: finishing ? [dictation.committedText, dictation.pendingText].joined(separator: " ") : dictation.committedText,
            pending: finishing ? "" : dictation.pendingText,
            dimPending: !finishing,
            onHeightChange: onHeightChange
        )
        .modifier(Shimmer(active: finishing && !rewriting))
        // The model is rewriting this text; the label in the ear shimmers instead.
        .opacity(rewriting ? 0.5 : 1)
        .frame(width: width, alignment: .leading)
        .padding(.top, IslandView.textTop)
        .onDisappear { onHeightChange(0) }
    }
}

// MARK: Panel

private struct IslandPanel: View {
    let model: OverlayModel
    @State private var copied = false

    var body: some View {
        let dictation = model.dictation
        VStack(spacing: 0) {
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
            .staggered(0)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                // The row is tight with five chips: the language switch keeps its size and the
                // chips with long names — the mode and the microphone — truncate instead.
                LanguageSwitch(settings: model.settings).fixedSize()
                ModeChip(model: model)
                SmartChip(isOn: model.smartStructure)
                TranslateChip(model: model)
                MicrophoneChip(model: model)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 13)
            .staggered(1)
        }
        .frame(width: IslandView.panelWidth, height: IslandView.panelBodyHeight)
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
            // A language picked in settings, e.g. PL, sits next to the two tuned ones.
            let current = settings.value.language
            if current != .russian, current != .english, current != .auto {
                option(current, current.rawValue.uppercased())
            }
            option(.auto, "Auto")
        }
        .padding(2)
        .frame(height: 26)
        .background(Capsule().fill(.white.opacity(0.1)))
    }

    private func option(_ language: AppSettings.SpeechLanguage, _ title: LocalizedStringKey) -> some View {
        option(language, Text(title))
    }

    /// A language code such as PL, shown as is.
    private func option(_ language: AppSettings.SpeechLanguage, _ code: String) -> some View {
        option(language, Text(verbatim: code))
    }

    private func option(_ language: AppSettings.SpeechLanguage, _ title: Text) -> some View {
        let selected = settings.value.language == language
        return Button {
            settings.value.language = language
        } label: {
            title
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
        let name = AppModel.isPreviewLaunch ? "MacBook Pro Microphone" : device?.name
        Button {
            showMenu()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "mic.fill").font(.system(size: 9.5, weight: .semibold))
                CappedWidth(limit: 64) {
                    Text(name ?? String(localized: "No microphone")).truncationMode(.tail)
                }
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
    var isSeparator = false
    let action: @MainActor () -> Void

    static var separator: OverlayMenuItem {
        OverlayMenuItem(title: "", isOn: false, isSeparator: true) {}
    }
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
            menu.addItem(item.isSeparator ? .separator() : ClosureMenuItem(title: item.title, isOn: item.isOn, action: item.action))
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
