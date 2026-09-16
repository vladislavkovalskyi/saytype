import SwiftUI
import VMCore

struct OverlayRoot: View {
    let dictation: DictationController
    let settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch settings.value.overlayStyle {
            case .island:
                VStack(spacing: 10) {
                    IslandView(dictation: dictation)
                    if case .card(let text) = dictation.phase {
                        CardView(text: text, dictation: dictation, light: false)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                }
            case .pill:
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if case .card(let text) = dictation.phase {
                        CardView(text: text, dictation: dictation, light: settings.value.glass == .light)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        PillView(dictation: dictation, light: settings.value.glass == .light)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .bouncy(duration: 0.4), value: dictation.phase)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: dictation.committedText + dictation.pendingText)
    }
}

// MARK: Pill

struct PillView: View {
    let dictation: DictationController
    let light: Bool

    var body: some View {
        if let content = PillContent(dictation: dictation) {
            HStack(spacing: 10) {
                content.leading
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.white.opacity(light ? 0 : 0.1)))
                if dictation.phase == .listening {
                    Waveform(levels: Array(dictation.levels.suffix(10)), color: light ? .black.opacity(0.8) : .white)
                        .frame(width: 44, height: 20)
                }
                content.text
                    .font(.onest(14.5))
                    .lineLimit(2)
                    .frame(maxWidth: 520, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 7)
            .padding(.trailing, 16)
            .frame(minHeight: 44)
            .foregroundStyle(light ? Color(hex: 0x17151B) : .white)
            .background(PillBackground(light: light))
            .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
        }
    }
}

private struct PillBackground: View {
    let light: Bool

    var body: some View {
        Capsule()
            .fill(light ? AnyShapeStyle(.white.opacity(0.72)) : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x28262C, opacity: 0.78), Color(hex: 0x121016, opacity: 0.88)], startPoint: .top, endPoint: .bottom)))
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(light ? 0.7 : 0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }
}

/// What the pill shows for a phase: an icon on the left and a line of text.
private struct PillContent {
    let leading: AnyView
    let text: Text

    @MainActor
    init?(dictation: DictationController) {
        switch dictation.phase {
        case .idle, .card:
            return nil
        case .listening:
            leading = AnyView(RecDot())
            text = LiveText.make(committed: dictation.committedText, pending: dictation.pendingText, handsFree: dictation.handsFree, size: 14.5)
        case .finishing:
            leading = AnyView(SpinnerRing(color: Color(hex: 0xFF9A5C)).frame(width: 15, height: 15))
            text = Text(dictation.committedText.isEmpty ? "оформление" : dictation.committedText + " " + dictation.pendingText)
        case .inserted(let appName):
            leading = AnyView(Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0x8EF0B0)))
            text = Text(appName.map { "Вставлено в \($0)" } ?? "Вставлено")
        case .notice(let message):
            leading = AnyView(Image(systemName: message == "Поле пароля" ? "lock.fill" : "exclamationmark").font(.system(size: 12, weight: .bold)))
            text = Text(message)
        }
    }
}

enum LiveText {
    /// Committed words bright, pending words dimmed, identifiers in the code font.
    static func make(committed: String, pending: String, handsFree: Bool, size: CGFloat) -> Text {
        if committed.isEmpty && pending.isEmpty {
            return Text(handsFree ? "без рук" : "").foregroundStyle(.secondary)
        }
        var result = Text(AttributedString.dictated(committed, size: size, chip: .clear))
        if !pending.isEmpty {
            result = result + Text(AttributedString.dictated(committed.isEmpty ? pending : " " + pending, size: size, chip: .clear)).foregroundStyle(.secondary)
        }
        return result
    }
}

struct RecDot: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(Color(hex: 0xFF7A45))
            .frame(width: 9, height: 9)
            .shadow(color: Color(hex: 0xFF7A45).opacity(0.9), radius: 6)
            .background(Circle().fill(Color(hex: 0xFF7A45).opacity(0.22)).frame(width: 17, height: 17).scaleEffect(pulse ? 1.15 : 0.9))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true }
            }
    }
}

/// A small rotating arc: the text is being finalised.
struct SpinnerRing: View {
    let color: Color
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .rotationEffect(.degrees(turning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { turning = true }
            }
    }
}

struct Waveform: View {
    let levels: [Float]
    let color: Color

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: max(3, CGFloat(level) * 20))
            }
        }
        .animation(.easeOut(duration: 0.12), value: levels)
    }
}

// MARK: Island

struct IslandView: View {
    let dictation: DictationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var notch: NotchMetrics { .shared }

    private var expanded: Bool {
        switch dictation.phase {
        case .listening: !(dictation.committedText.isEmpty && dictation.pendingText.isEmpty)
        case .finishing, .notice: true
        default: false
        }
    }

    private var visible: Bool {
        switch dictation.phase {
        case .idle, .card: false
        default: true
        }
    }

    var body: some View {
        let notchWidth = max(notch.width, 160)
        let ear: CGFloat = expanded ? 16 : 8
        let width: CGFloat = (expanded ? 540 : notchWidth + 130) + ear * 2
        let height: CGFloat = expanded ? notch.height + 74 : notch.height
        ZStack(alignment: .top) {
            IslandShape(ear: ear, radius: expanded ? 30 : 14)
                .fill(.black)
            VStack(spacing: 0) {
                HStack {
                    leadingIndicator
                    Spacer()
                    trailingIndicator
                }
                .frame(height: notch.height)
                .padding(.horizontal, (expanded ? 30 : 18) + ear)
                if expanded {
                    HStack(alignment: .center, spacing: 14) {
                        if dictation.phase == .listening {
                            Waveform(levels: Array(dictation.levels.suffix(10)), color: Color(hex: 0xFFAE78))
                                .frame(width: 44, height: 28)
                        }
                        islandText
                            .font(.onest(15))
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 30 + ear)
                    .padding(.top, 10)
                    .transition(.opacity)
                }
            }
            .foregroundStyle(.white)
        }
        .frame(width: width, height: height)
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.9, anchor: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .bouncy(duration: 0.45), value: expanded)
    }

    @ViewBuilder private var leadingIndicator: some View {
        switch dictation.phase {
        case .listening:
            if expanded {
                Circle().fill(Color(hex: 0xFF7A45)).frame(width: 8, height: 8).shadow(color: Color(hex: 0xFF7A45), radius: 5)
            } else {
                Waveform(levels: Array(dictation.levels.suffix(7)), color: Color(hex: 0xFFAE78)).frame(height: 16)
            }
        case .finishing:
            SpinnerRing(color: Color(hex: 0xFF9A5C)).frame(width: 13, height: 13)
        case .inserted:
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: 0x8EF0B0))
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var trailingIndicator: some View {
        switch dictation.phase {
        case .listening:
            if let startedAt = dictation.startedAt {
                Text(startedAt, style: .timer).font(.mono(11)).foregroundStyle(.white.opacity(0.6))
            }
        case .inserted:
            Text("вставлено").font(.onest(11)).foregroundStyle(.white.opacity(0.7))
        default:
            EmptyView()
        }
    }

    private var islandText: Text {
        switch dictation.phase {
        case .listening:
            LiveText.make(committed: dictation.committedText, pending: dictation.pendingText, handsFree: dictation.handsFree, size: 15)
        case .finishing:
            Text(dictation.committedText + " " + dictation.pendingText).foregroundStyle(.white.opacity(0.75))
        case .notice(let message):
            Text(message)
        default:
            Text("")
        }
    }
}

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

// MARK: Card

struct CardView: View {
    let text: String
    let dictation: DictationController
    let light: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal").font(.system(size: 11, weight: .semibold)).opacity(0.6)
                Spacer()
                Button {
                    dictation.dismissCard()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .opacity(0.7)
            }
            Text(text)
                .font(.onest(14))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("Копировать") { dictation.copyCard() }
                    .buttonStyle(.plain)
                    .font(.onest(12, .semibold))
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(Capsule().fill(light ? .black.opacity(0.08) : .white))
                    .foregroundStyle(light ? Color(hex: 0x17151B) : Color(hex: 0x17151B))
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 400)
        .foregroundStyle(light ? Color(hex: 0x17151B) : .white)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(light ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(Color(hex: 0x1C1A20, opacity: 0.86)))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(light ? 0.7 : 0.14)))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
        }
        .onDrag {
            NSItemProvider(object: text as NSString)
        }
    }
}
