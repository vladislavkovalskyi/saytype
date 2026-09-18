import SwiftUI
import VMCore

/// The pill above the Dock: a thin bar at rest, a glowing capsule while recording, and a
/// bubble above it for live text and the card.
///
/// Like the island, the capsule and the bubble are single shapes that change size frame by frame
/// (`AnimatedFrame`); only the items inside them cross-fade. The hidden bubble is a zero-height
/// strip on top of the capsule, so it grows out of it.
struct PillView: View {
    let model: OverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Height of the bubble's content as laid out: live text or the card, with its margins.
    @State private var bubbleHeight: CGFloat = 0

    enum Mode: Equatable {
        case idle
        case peek
        case listening
        case finishing(rewriting: Bool)
        case inserted
        case notice(DictationController.Notice)
        case card(String)
    }

    private var mode: Mode {
        let dictation = model.dictation
        switch dictation.phase {
        case .listening: return .listening
        case .finishing: return .finishing(rewriting: dictation.finishingStage == .rewriting)
        case .card(let text): return .card(text)
        case .inserted: return model.hover == .none ? .inserted : .peek
        case .notice(let notice): return model.hover == .none ? .notice(notice) : .peek
        case .idle: return model.hover == .none ? .idle : .peek
        }
    }

    private var light: Bool { model.settings.value.glass == .light }
    private var ink: Color { light ? Color(hex: 0x17151B) : .white }

    private var showsText: Bool {
        !(model.dictation.committedText.isEmpty && model.dictation.pendingText.isEmpty)
    }

    private func size(_ mode: Mode) -> CGSize {
        let dictation = model.dictation
        switch mode {
        case .idle, .card:
            return CGSize(width: 56, height: 8)
        case .peek:
            let record = TextMeasure.width(String(localized: "Record"), size: 12.5)
            let chip = ModeChip.width(dictation.currentMode().title)
            return CGSize(width: 6 + 28 + 9 + 22 + 9 + record + 18 + chip + 7, height: 40)
        case .listening, .finishing(rewriting: false):
            // Both keep the recording width, so the spinner takes the orb's place without a jump.
            let tag = dictation.recordingTag.map { ModeTag.width($0) + 9 } ?? 0
            let stop: CGFloat = dictation.handsFree ? 33 : 0
            return CGSize(width: max(250, 8 + Self.voiceWidth + tag + 9 + 9 + 34 + stop + 12), height: 44)
        case .finishing(rewriting: true):
            return CGSize(width: max(250, 16 + RewritingLabel.width + 18 + SkipRewriteButton.width + 10), height: 44)
        case .inserted:
            return CGSize(width: min(64 + TextMeasure.width(targetName, size: 12.5) + 40, 260), height: 40)
        case .notice(let notice):
            return CGSize(width: TextMeasure.width(notice.measuredTitle, size: 12.5) + 58, height: 40)
        }
    }

    /// The orb and the bars; the spinner keeps this slot while finishing.
    private static let voiceWidth = 28 + 9 + VoiceBars.width(count: 16, barWidth: 3)

    /// Size of the bubble above the capsule, or `nil` while it is folded away. The height is the
    /// content's own; before its first layout pass reports it, an estimate.
    private func bubbleSize(_ mode: Mode) -> CGSize? {
        switch mode {
        case .listening, .finishing:
            guard showsText else { return nil }
            return CGSize(width: textWidth + 32, height: bubbleHeight > 0 ? bubbleHeight : TextMeasure.lineHeight(size: 15) + 24)
        case .card(let text):
            let lineHeight: CGFloat = 20.5
            let body = model.dictation.cardEditing ? model.dictation.cardDraft : text
            let estimate = min(TextMeasure.height(body, width: 420, size: 14, lineHeight: lineHeight), lineHeight * 8) + 12 + 28 + 24
            return CGSize(width: 452, height: bubbleHeight > 0 ? bubbleHeight : estimate)
        default:
            return nil
        }
    }

    /// Grows with the text up to two lines' worth of a comfortable width.
    private var textWidth: CGFloat {
        let text = [model.dictation.committedText, model.dictation.pendingText].joined(separator: " ")
        return min(max(TextMeasure.width(text, size: 15) + 4, 120), 460)
    }

    private var targetName: String {
        if case .inserted(let target) = model.dictation.phase { return target?.name ?? "" }
        return ""
    }

    var body: some View {
        let mode = mode
        let size = size(mode)
        let bubble = bubbleSize(mode)
        VStack(spacing: 0) {
            PillBubble(model: model, mode: mode, light: light, showsText: showsText, textWidth: textWidth) { bubbleHeight = $0 }
                .modifier(AnimatedFrame(width: bubble?.width ?? size.width, height: bubble?.height ?? 0, alignment: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .background { BubbleGlass(light: light) }
                .opacity(bubble == nil ? 0 : 1)
            Color.clear
                .modifier(AnimatedFrame(width: 1, height: bubble == nil ? 0 : 10))
            content(mode)
                .modifier(AnimatedFrame(width: size.width, height: size.height))
                .clipShape(Capsule())
                .background { PillBackground(light: light, dictation: model.dictation, recording: mode == .listening) }
        }
        .foregroundStyle(ink)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.hitFrame = $0 }
        .animation(.island(reduceMotion: reduceMotion), value: size)
        .animation(.island(reduceMotion: reduceMotion), value: bubble)
        .animation(.island(reduceMotion: reduceMotion), value: mode)
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
                KeyCap(label: model.settings.value.recordKey.capLabel, tint: ink)
                Text("Record").font(.onest(12.5, .medium)).opacity(0.8).fixedSize()
                Spacer(minLength: 0)
                ModeChip(model: model, ink: ink)
            }
            .padding(.leading, 6)
            .padding(.trailing, 7)
            .transition(.islandContent)
        case .listening, .finishing(rewriting: false):
            // One row for both: the spinner takes the orb's slot and the mode tag stays put.
            let listening = mode == .listening
            HStack(spacing: 9) {
                ZStack(alignment: .leading) {
                    if listening {
                        HStack(spacing: 9) {
                            VoiceLevel(dictation: dictation) { level in
                                RecordOrb(size: 28, level: Float(level))
                            }
                            .frame(width: 28, height: 28)
                            VoiceBars(dictation: dictation, count: 16, height: 20)
                        }
                        .transition(.islandContent)
                    } else {
                        SpinnerRing(size: 16).padding(.leading, 6).transition(.islandContent)
                    }
                }
                .frame(width: Self.voiceWidth, alignment: .leading)
                if let tag = dictation.recordingTag {
                    ModeTag(title: tag, ink: ink).transition(.islandContent)
                }
                Spacer(minLength: 0)
                if listening, let startedAt = dictation.startedAt {
                    Text(startedAt, style: .timer)
                        .font(.mono(11, .medium))
                        .opacity(0.6)
                        .monospacedDigit()
                        .fixedSize()
                        .transition(.islandContent)
                }
                if listening, dictation.handsFree {
                    Button {
                        dictation.toggleRecordingFromOverlay()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(IslandIconButtonStyle(size: 24, tint: ink))
                    .help(Text("Stop"))
                    .transition(.islandContent)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .transition(.islandContent)
        case .finishing(rewriting: true):
            HStack(spacing: 9) {
                RewritingLabel(ink: ink)
                Spacer(minLength: 0)
                SkipRewriteButton(dictation: dictation, ink: ink)
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
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
                    .foregroundStyle(notice.tint(ink: ink))
                notice.label.font(.onest(12.5, .medium)).fixedSize()
            }
            .id(notice.measuredTitle)
            .transition(.islandContent)
        }
    }
}

/// The capsule's glass. While recording, the ember ring and glow follow the voice every frame;
/// otherwise the timeline is paused.
private struct PillBackground: View {
    let light: Bool
    let dictation: DictationController
    let recording: Bool

    var body: some View {
        VoiceLevel(dictation: dictation, active: recording) { level in
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
                        .opacity(recording ? 0.35 + level * 0.65 : 0)
                }
                .shadow(color: .black.opacity(light ? 0.18 : 0.45), radius: 16, y: 10)
                .shadow(color: OverlayPalette.ember.opacity(level * 0.75), radius: 22, y: 8)
        }
    }
}

private struct BubbleGlass: View {
    let light: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(light
                ? AnyShapeStyle(Color.white.opacity(0.76))
                : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x26232A, opacity: 0.82), Color(hex: 0x121016, opacity: 0.9)], startPoint: .top, endPoint: .bottom)))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(light ? 0.75 : 0.13), lineWidth: 1))
            .shadow(color: .black.opacity(light ? 0.16 : 0.4), radius: 18, y: 12)
            .environment(\.colorScheme, light ? .light : .dark)
    }
}

/// What the bubble holds: live text while dictating, the text and its actions for the card.
private struct PillBubble: View {
    let model: OverlayModel
    let mode: PillView.Mode
    let light: Bool
    let showsText: Bool
    let textWidth: CGFloat
    /// The content's height as laid out, for the bubble around it.
    let onHeightChange: (CGFloat) -> Void

    private var ink: Color { light ? Color(hex: 0x17151B) : .white }

    var body: some View {
        let dictation = model.dictation
        ZStack(alignment: .bottom) {
            switch mode {
            case .card(let text):
                OverlayCard(model: model, text: text, style: .pill, light: light)
                    .frame(width: 420)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .transition(.islandContent)
            case .listening, .finishing:
                if showsText {
                    let finishing = mode != .listening
                    let rewriting = mode == .finishing(rewriting: true)
                    LiveWords(
                        committed: finishing ? [dictation.committedText, dictation.pendingText].joined(separator: " ") : dictation.committedText,
                        pending: finishing ? "" : dictation.pendingText,
                        dimPending: !finishing,
                        color: ink
                    )
                    .modifier(Shimmer(active: finishing && !rewriting))
                    .opacity(rewriting ? 0.5 : 1)
                    .frame(width: textWidth)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .transition(.islandContent)
                }
            default:
                EmptyView()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        .environment(\.colorScheme, light ? .light : .dark)
    }
}
