import SwiftUI
import VMCore

/// The pill above the Dock: a thin bar at rest, a glowing capsule while recording, and a
/// bubble above it for live text and the card.
struct PillView: View {
    let model: OverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Mode: Equatable {
        case idle
        case peek
        case listening
        case finishing
        case inserted
        case notice(DictationController.Notice)
        case card(String)
    }

    private var mode: Mode {
        switch model.dictation.phase {
        case .listening: .listening
        case .finishing: .finishing
        case .card(let text): .card(text)
        case .inserted: model.hover == .none ? .inserted : .peek
        case .notice(let notice): model.hover == .none ? .notice(notice) : .peek
        case .idle: model.hover == .none ? .idle : .peek
        }
    }

    private var light: Bool { model.settings.value.glass == .light }

    private func size(_ mode: Mode) -> CGSize {
        switch mode {
        case .idle: CGSize(width: 56, height: 8)
        case .peek: CGSize(width: 158, height: 40)
        case .listening, .finishing: CGSize(width: 250, height: 44)
        case .inserted:
            CGSize(width: min(64 + TextMeasure.width(targetName, size: 12.5) + 40, 260), height: 40)
        case .notice(let notice):
            CGSize(width: TextMeasure.width(notice.measuredTitle, size: 12.5) + 58, height: 40)
        case .card: CGSize(width: 56, height: 8)
        }
    }

    private var targetName: String {
        if case .inserted(let target) = model.dictation.phase { return target?.name ?? "" }
        return ""
    }

    private var showsBubble: Bool {
        switch mode {
        case .listening: !(model.dictation.committedText.isEmpty && model.dictation.pendingText.isEmpty)
        case .finishing, .card: true
        default: false
        }
    }

    var body: some View {
        let mode = mode
        let size = size(mode)
        VStack(spacing: 10) {
            if showsBubble {
                PillBubble(model: model, mode: mode, light: light)
                    .transition(.asymmetric(insertion: .islandContent.combined(with: .offset(y: 12)), removal: .opacity.combined(with: .scale(scale: 0.6, anchor: .bottom)).combined(with: .offset(y: 24))))
            }
            ZStack {
                PillBackground(light: light, level: mode == .listening ? model.dictation.currentLevel : 0, recording: mode == .listening)
                content(mode)
                    .frame(width: size.width, height: size.height)
                    .clipShape(Capsule())
            }
            .frame(width: size.width, height: size.height)
        }
        .foregroundStyle(light ? Color(hex: 0x17151B) : .white)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.hitFrame = $0 }
        .animation(.island(reduceMotion: reduceMotion), value: mode)
        .animation(.island(reduceMotion: reduceMotion), value: showsBubble)
    }

    @ViewBuilder private func content(_ mode: Mode) -> some View {
        let dictation = model.dictation
        switch mode {
        case .idle, .card:
            Color.clear
        case .peek:
            HStack(spacing: 9) {
                Button {
                    model.collapse()
                    dictation.toggleRecordingFromOverlay()
                } label: {
                    RecordOrb(size: 28)
                }
                .buttonStyle(.plain)
                .help(Text("Record"))
                KeyCap(label: model.settings.value.recordKey.capLabel, tint: light ? Color(hex: 0x17151B) : .white)
                Text("Record").font(.onest(12.5, .medium)).opacity(0.8)
                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
            .transition(.islandContent)
        case .listening, .finishing:
            HStack(spacing: 9) {
                if mode == .finishing {
                    SpinnerRing(size: 16).padding(.leading, 6)
                } else {
                    RecordOrb(size: 28, level: dictation.currentLevel)
                    VoiceBars(levels: Array(dictation.levels.suffix(16)), height: 20)
                }
                Spacer(minLength: 0)
                if let startedAt = dictation.startedAt, mode == .listening {
                    Text(startedAt, style: .timer)
                        .font(.mono(11, .medium))
                        .opacity(0.6)
                        .monospacedDigit()
                        .fixedSize()
                }
                if dictation.handsFree, mode == .listening {
                    Button {
                        dictation.toggleRecordingFromOverlay()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(IslandIconButtonStyle(size: 24, tint: light ? Color(hex: 0x17151B) : .white))
                    .help(Text("Stop"))
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .transition(.islandContent)
        case .inserted:
            HStack(spacing: 8) {
                if case .inserted(let target) = dictation.phase {
                    AppIconBadge(icon: target?.icon, size: 20)
                    Text(target?.name ?? "").font(.onest(12.5, .medium)).lineLimit(1)
                }
                Spacer(minLength: 0)
                DoneCheck()
            }
            .padding(.leading, 10)
            .padding(.trailing, 11)
            .transition(.islandContent)
        case .notice(let notice):
            HStack(spacing: 8) {
                Image(systemName: notice.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(notice == .copied ? OverlayPalette.done : OverlayPalette.warning)
                Text(notice.title).font(.onest(12.5, .medium)).fixedSize()
            }
            .transition(.islandContent)
        }
    }
}

private struct PillBackground: View {
    let light: Bool
    let level: Float
    let recording: Bool

    var body: some View {
        Capsule()
            .fill(light
                ? AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.78), .white.opacity(0.66)], startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x26232A, opacity: 0.8), Color(hex: 0x121016, opacity: 0.88)], startPoint: .top, endPoint: .bottom)))
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(light ? 0.75 : 0.14), lineWidth: 1)
            }
            .overlay {
                Capsule()
                    .strokeBorder(AngularGradient(colors: [OverlayPalette.emberHigh, OverlayPalette.ember, OverlayPalette.emberLow, OverlayPalette.emberHigh], center: .center), lineWidth: 1.2)
                    .opacity(recording ? 0.35 + Double(level) * 0.65 : 0)
            }
            .shadow(color: .black.opacity(light ? 0.18 : 0.45), radius: 16, y: 10)
            .shadow(color: OverlayPalette.ember.opacity(Double(level) * 0.75), radius: 22, y: 8)
    }
}

private struct PillBubble: View {
    let model: OverlayModel
    let mode: PillView.Mode
    let light: Bool

    var body: some View {
        let dictation = model.dictation
        Group {
            switch mode {
            case .card(let text):
                VStack(alignment: .leading, spacing: 12) {
                    Text(CodeWords.attributed(text, size: 14))
                        .font(.onest(14))
                        .lineSpacing(3.5)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onDrag { NSItemProvider(object: text as NSString) }
                    HStack(spacing: 6) {
                        Button("Copy") { dictation.copyCard() }
                            .buttonStyle(CapsuleButtonStyle(prominent: true, light: light))
                        Button("Paste") { dictation.insertCard() }
                            .buttonStyle(CapsuleButtonStyle(light: light))
                        Spacer()
                        Button {
                            dictation.dismissCard()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(IslandIconButtonStyle(size: 26, tint: light ? Color(hex: 0x17151B) : .white))
                        .help(Text("Close"))
                    }
                }
                .frame(width: 420)
            case .finishing:
                LiveWords(committed: [dictation.committedText, dictation.pendingText].joined(separator: " "), pending: "", dimPending: false, color: ink)
                    .modifier(Shimmer())
                    .frame(width: bubbleWidth)
            default:
                LiveWords(committed: dictation.committedText, pending: dictation.pendingText, color: ink)
                    .frame(width: bubbleWidth)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(light
                    ? AnyShapeStyle(Color.white.opacity(0.76))
                    : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x26232A, opacity: 0.82), Color(hex: 0x121016, opacity: 0.9)], startPoint: .top, endPoint: .bottom)))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(light ? 0.75 : 0.13), lineWidth: 1))
                .shadow(color: .black.opacity(light ? 0.16 : 0.4), radius: 18, y: 12)
        }
        .environment(\.colorScheme, light ? .light : .dark)
    }

    private var ink: Color { light ? Color(hex: 0x17151B) : .white }

    /// Grows with the text up to two lines' worth of a comfortable width.
    private var bubbleWidth: CGFloat {
        let text = [model.dictation.committedText, model.dictation.pendingText].joined(separator: " ")
        return min(max(TextMeasure.width(text, size: 15) + 4, 120), 460)
    }
}
