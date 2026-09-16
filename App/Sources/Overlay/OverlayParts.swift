import AppKit
import SwiftUI
import VMCore

enum OverlayPalette {
    static let emberHigh = Color(hex: 0xFFB36B)
    static let ember = Color(hex: 0xFF7A45)
    static let emberLow = Color(hex: 0xE2483A)
    static let done = Color(hex: 0x8EF0B0)
    static let warning = Color(hex: 0xFFB36B)
}

extension Animation {
    /// The island's spring: quick, with a small overshoot.
    static func island(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.78)
    }

    /// Live words moving between lines: the island's pace without the overshoot, so the text
    /// and the shape around it arrive together.
    static func liveText(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.92)
    }
}

extension AnyTransition {
    /// Content swaps inside the island: fade through a light blur. A plain fade with Reduce Motion.
    static var islandContent: AnyTransition {
        .modifier(active: BlurFade(amount: 1), identity: BlurFade(amount: 0))
    }
}

private struct BlurFade: ViewModifier {
    let amount: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .blur(radius: reduceMotion ? 0 : 7 * amount)
            .opacity(1 - amount)
            .scaleEffect(reduceMotion ? 1 : 1 - 0.03 * amount, anchor: .top)
    }
}

/// A row of the hover panel that fades in after the rows above it.
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 5)
            .offset(y: shown || reduceMotion ? 0 : -8)
            .onAppear {
                let animation: Animation = reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.38, dampingFraction: 0.86).delay(0.05 + 0.05 * Double(index))
                withAnimation(animation) { shown = true }
            }
    }
}

extension View {
    func staggered(_ index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}

/// A frame whose size SwiftUI interpolates every display frame. Layout, clips and the frame
/// reported to `onGeometryChange` then follow what is on screen during a transition, instead of
/// jumping to the final size when it starts.
struct AnimatedFrame: ViewModifier, Animatable {
    var width: CGFloat
    var height: CGFloat
    var alignment: Alignment = .center

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set {
            width = newValue.first
            height = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content.frame(width: width, height: height, alignment: alignment)
    }
}

/// Glossy record button in the app's ember colours.
struct RecordOrb: View {
    var size: CGFloat = 58
    var recording = false
    var level: Float = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFA062), Color(hex: 0xF0603C), Color(hex: 0xB3303A)], center: UnitPoint(x: 0.5, y: 0.62), startRadius: 0, endRadius: size * 0.64))
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.7), .white.opacity(0)], center: UnitPoint(x: 0.34, y: 0.26), startRadius: 0, endRadius: size * 0.36))
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0), .black.opacity(0.25)], startPoint: .top, endPoint: .bottom), lineWidth: max(1, size / 40))
            if size > 36 {
                Image(systemName: recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: Color(hex: 0x7A1E28).opacity(0.5), radius: 2, y: 1)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(1 + CGFloat(level) * 0.12)
        .shadow(color: OverlayPalette.ember.opacity(0.75), radius: size / 4.5, y: size / 7)
    }
}

// MARK: Voice level

/// Eases audio levels toward the latest reading once per display frame. Levels arrive a few
/// dozen times a second; drawn as they come, bars and glows step.
@MainActor
final class LevelSmoother {
    private var values: [Float] = []
    private var time: TimeInterval?

    /// Rises in about 50 ms and falls in about 140 ms, like a level meter.
    func advance(toward target: [Float], at now: TimeInterval) -> [Float] {
        let dt = Float(min(max(now - (time ?? now), 0), 0.1))
        time = now
        guard values.count == target.count else {
            values = target
            return values
        }
        for i in values.indices {
            let tau: Float = target[i] > values[i] ? 0.05 : 0.14
            values[i] += (target[i] - values[i]) * (1 - exp(-dt / tau))
        }
        return values
    }
}

/// Recent input levels as bars, newest on the right. Flat when the microphone hears nothing.
/// The bars ease toward each new level at the display's refresh rate while they are on screen.
struct VoiceBars: View {
    let dictation: DictationController
    var count = 9
    var height: CGFloat = 16
    var barWidth: CGFloat = 3
    @State private var smoother = LevelSmoother()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func width(count: Int, barWidth: CGFloat) -> CGFloat {
        CGFloat(count) * barWidth + CGFloat(count - 1) * barWidth * 0.7
    }

    var body: some View {
        Group {
            if reduceMotion {
                bars(Array(dictation.levels.suffix(count)))
            } else {
                TimelineView(.animation) { timeline in
                    bars(smoother.advance(toward: Array(dictation.levels.suffix(count)), at: timeline.date.timeIntervalSinceReferenceDate))
                }
            }
        }
        .frame(width: Self.width(count: count, barWidth: barWidth), height: height)
    }

    private func bars(_ levels: [Float]) -> some View {
        let barWidth = barWidth
        return Canvas { context, size in
            let gradient = Gradient(colors: [Color(hex: 0xFFC794), OverlayPalette.ember])
            for (index, level) in levels.enumerated() {
                let height = max(barWidth, CGFloat(level) * size.height)
                let rect = CGRect(x: CGFloat(index) * barWidth * 1.7, y: (size.height - height) / 2, width: barWidth, height: height)
                let shading = GraphicsContext.Shading.linearGradient(gradient, startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY))
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: shading)
            }
        }
    }
}

/// The voice level eased every display frame, for glows and pulses. Inactive, the timeline is
/// paused, so it costs nothing, and the level is zero.
struct VoiceLevel<Content: View>: View {
    let dictation: DictationController
    var active = true
    @ViewBuilder let content: (Double) -> Content
    @State private var smoother = LevelSmoother()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !active || reduceMotion)) { timeline in
            content(level(at: timeline.date))
        }
    }

    private func level(at date: Date) -> Double {
        guard active else { return 0 }
        // With Reduce Motion the glow holds still instead of pulsing with the voice.
        guard !reduceMotion else { return 0.3 }
        return Double(smoother.advance(toward: [dictation.currentLevel], at: date.timeIntervalSinceReferenceDate)[0])
    }
}

struct SpinnerRing: View {
    var size: CGFloat = 14
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Color(hex: 0xFF9A5C).opacity(0.25), lineWidth: 2)
            Circle().trim(from: 0, to: 0.28).stroke(Color(hex: 0xFF9A5C), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(turning ? 360 : 0))
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { turning = true }
        }
    }
}

/// A highlight that runs across the text while it is being formatted. Inactive, the mask is
/// plain: turning it on or off keeps the text's identity and state.
struct Shimmer: ViewModifier {
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.mask {
            if active, !reduceMotion {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1
                    GeometryReader { proxy in
                        LinearGradient(stops: [
                            .init(color: .black.opacity(0.38), location: 0.36),
                            .init(color: .black, location: 0.5),
                            .init(color: .black.opacity(0.38), location: 0.64),
                        ], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 3)
                        .offset(x: -2 * proxy.size.width * t)
                    }
                }
            } else {
                Color.black.opacity(active ? 0.75 : 1)
            }
        }
    }
}

/// Live words that wrap like a paragraph; new words fade in from a blur and the
/// unconfirmed tail stays dim. Shows the last `lines` lines and reports the height it takes, so
/// the island or the bubble grows with the text as laid out rather than with an estimate.
struct LiveWords: View {
    let committed: String
    let pending: String
    var size: CGFloat = 15
    var lines = 2
    var dimPending = true
    var color: Color = .white
    var onHeightChange: ((CGFloat) -> Void)?
    @State private var naturalHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Word: Identifiable {
        let id: String
        let text: String
        let isPending: Bool
    }

    private var words: [Word] {
        let done = Words.split(committed)
        let tail = Words.split(pending)
        return (done.map { ($0, false) } + tail.map { ($0, true) }).enumerated().map { index, pair in
            Word(id: "\(index)-\(pair.0)", text: pair.0, isPending: pair.1)
        }
    }

    var body: some View {
        let lineSpacing = size * 1.42 - size * 1.2
        let limit = TextMeasure.lineHeight(size: size) * CGFloat(lines) + lineSpacing * CGFloat(lines - 1)
        let overflowing = naturalHeight > limit + 1
        BottomClamp(limit: limit) {
            FlowLayout(spacing: size * 0.27, lineSpacing: lineSpacing) {
                ForEach(words) { word in
                    Text(CodeWords.attributed(word.text, size: size))
                        .font(.onest(size))
                        .foregroundStyle(color.opacity(word.isPending && dimPending ? 0.44 : 1))
                        .fixedSize()
                        .transition(.islandContent)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                naturalHeight = height
                onHeightChange?(min(height, limit))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .mask {
            // Older lines scroll away under a fade; a text that fits keeps its first line crisp.
            LinearGradient(stops: [.init(color: overflowing ? .clear : .black, location: 0), .init(color: .black, location: 0.22)], startPoint: .top, endPoint: .bottom)
        }
        .animation(.liveText(reduceMotion: reduceMotion), value: committed + "|" + pending)
    }
}

/// Shows the bottom of its content, at most `limit` tall, so live text scrolls up a line at a
/// time. A layout rather than a frame sized from a measured height: the clamp and the words
/// move in the same pass, with no frame where they disagree.
private struct BottomClamp: Layout {
    let limit: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let natural = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? natural.width, height: min(natural.height, limit))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let natural = content.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        content.place(at: CGPoint(x: bounds.minX, y: bounds.maxY), anchor: .bottomLeading, proposal: ProposedViewSize(width: bounds.width, height: natural.height))
    }
}

struct KeyCap: View {
    let label: String
    var tint: Color = .white

    var body: some View {
        Text(label)
            .font(.onest(10.5, .semibold))
            .foregroundStyle(tint.opacity(0.85))
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint.opacity(0.12)))
    }
}

struct AppIconBadge: View {
    let icon: NSImage?
    var size: CGFloat = 18

    var body: some View {
        if let icon {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(.white.opacity(0.18))
                .frame(width: size, height: size)
        }
    }
}

struct DoneCheck: View {
    @State private var shown = false

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9.5, weight: .heavy))
            .foregroundStyle(OverlayPalette.done)
            .frame(width: 18, height: 18)
            .background(Circle().fill(OverlayPalette.done.opacity(0.18)))
            .scaleEffect(shown ? 1 : 0.3)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.12)) { shown = true }
            }
    }
}

/// Small round icon button on black.
struct IslandIconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    var filled = true
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint.opacity(0.92))
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(filled ? (configuration.isPressed ? 0.24 : 0.11) : (configuration.isPressed ? 0.16 : 0))))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

/// Capsule chip on black or on dark glass.
struct IslandChipStyle: ButtonStyle {
    var height: CGFloat = 26
    var ink: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.onest(11.5, .medium))
            .foregroundStyle(ink.opacity(0.9))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(Capsule().fill(ink.opacity(configuration.isPressed ? 0.2 : 0.1)))
            .contentShape(Capsule())
    }
}

struct CapsuleButtonStyle: ButtonStyle {
    var prominent = false
    /// On light glass the prominent button is dark.
    var light = false

    func makeBody(configuration: Configuration) -> some View {
        let ink = light ? Color(hex: 0x1A1318) : .white
        let paper = light ? Color(hex: 0x1A1318) : .white
        configuration.label
            .font(.onest(12, .semibold))
            .foregroundStyle(prominent ? (light ? .white : Color(hex: 0x1A1318)) : ink)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(prominent ? paper : ink.opacity(0.12)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .contentShape(Capsule())
    }
}

enum TextMeasure {
    /// Width of a single line in Onest, for sizing the island to its text.
    static func width(_ text: String, size: CGFloat) -> CGFloat {
        let font = NSFont(name: "Onest", size: size) ?? .systemFont(ofSize: size)
        // Medium weight runs a little wider than the regular face measured here.
        return ceil((text as NSString).size(withAttributes: [.font: font]).width * 1.05)
    }

    /// Height of one line of Onest as SwiftUI lays out a `Text`.
    static func lineHeight(size: CGFloat) -> CGFloat {
        let font = NSFont(name: "Onest", size: size) ?? .systemFont(ofSize: size)
        return ceil(font.ascender - font.descender + font.leading)
    }

    /// Height of wrapped text in Onest.
    static func height(_ text: String, width: CGFloat, size: CGFloat, lineHeight: CGFloat) -> CGFloat {
        let font = NSFont(name: "Onest", size: size) ?? .systemFont(ofSize: size)
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        let rect = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: style])
        return ceil(rect.height)
    }
}

extension DictationRecord {
    /// "Terminal · 2 min ago"
    var overlayMeta: String {
        let ago = date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return [appName, ago].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Card button label with the key that does the same from any app.
struct CardAction: View {
    let title: LocalizedStringKey
    let key: String?
    let ink: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let key {
                Text(key)
                    .font(.onest(10.5, .semibold))
                    .foregroundStyle(ink.opacity(0.7))
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 17)
                    .background(RoundedRectangle(cornerRadius: 4.5, style: .continuous).fill(ink.opacity(0.12)))
            }
        }
    }
}

// MARK: Modes and the rewrite stage

/// Takes its content's ideal width up to `limit`; past it, the content gets the limit and a text
/// truncates. A `frame(maxWidth:)` would stretch short text to the limit instead.
struct CappedWidth: Layout {
    let limit: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let ideal = content.sizeThatFits(.unspecified)
        let width = max(min(ideal.width, limit, proposal.width ?? .infinity), 0)
        return CGSize(width: width, height: content.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// Name of the dictation mode while recording: a quiet tag, shown only outside the standard mode.
struct ModeTag: View {
    let title: String
    var ink: Color = .white
    /// Room left in the island's ear; a long name is cut short to fit.
    var maxWidth: CGFloat = 110

    var body: some View {
        CappedWidth(limit: maxWidth - 14) {
            Text(title)
                .font(.onest(10.5, .medium))
                .foregroundStyle(ink.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(Capsule().fill(ink.opacity(0.1)))
    }

    /// Estimate for sizing the island. SwiftUI sets Onest a few points wider than AppKit measures.
    static func width(_ title: String) -> CGFloat {
        min(TextMeasure.width(title, size: 10.5) + 4 + 14, 110)
    }
}

/// Left side of the rewrite stage: a highlight runs across the label while the model works.
struct RewritingLabel: View {
    var ink: Color = .white

    var body: some View {
        HStack(spacing: 6) {
            // A text run rather than an Image: in the island a separate symbol image next to
            // this label was drawn white instead of ember.
            Text(Image(systemName: "sparkles"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(OverlayPalette.emberHigh)
            Text("Rewriting")
                .font(.onest(12, .medium))
                .foregroundStyle(ink.opacity(0.9))
                .fixedSize()
                .modifier(Shimmer())
        }
    }

    static var width: CGFloat {
        18 + TextMeasure.width(String(localized: "Rewriting"), size: 12) + 4
    }
}

/// Inserts the text without waiting for the language model; esc does the same from any app.
struct SkipRewriteButton: View {
    let dictation: DictationController
    var ink: Color = .white

    var body: some View {
        Button {
            dictation.skipRewrite()
        } label: {
            CardAction(title: "Skip", key: "esc", ink: ink).fixedSize()
        }
        .buttonStyle(IslandChipStyle(height: 24, ink: ink))
    }

    static var width: CGFloat {
        TextMeasure.width(String(localized: "Skip"), size: 11.5) + 4 + 6 + 29 + 20
    }
}

/// Menu of dictation modes: selection by app, each mode by hand, and the Modes section.
enum ModeMenu {
    @MainActor
    static func items(_ model: OverlayModel) -> [OverlayMenuItem] {
        let settings = model.settings
        let current = settings.value.fixedModeID
        var items = [
            OverlayMenuItem(title: DictationMode.automaticTitle, isOn: current == nil) { settings.value.fixedModeID = nil },
            .separator,
        ]
        for mode in settings.value.modes {
            items.append(OverlayMenuItem(title: mode.title, isOn: current == mode.id) { settings.value.fixedModeID = mode.id })
        }
        items.append(.separator)
        items.append(OverlayMenuItem(title: String(localized: "Edit Modes…"), isOn: false) {
            model.collapse()
            model.openMain(.modes)
        })
        return items
    }
}

/// The mode the next dictation will use, as a chip that opens the mode menu.
struct ModeChip: View {
    let model: OverlayModel
    var ink: Color = .white
    @State private var anchor = OverlayMenuAnchor()

    private static let titleLimit: CGFloat = 84

    var body: some View {
        let title = model.dictation.currentMode().title
        Button {
            model.withMenu { anchor.pop(ModeMenu.items(model)) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 9.5, weight: .semibold))
                CappedWidth(limit: Self.titleLimit) {
                    Text(title).truncationMode(.tail)
                }
            }
        }
        .buttonStyle(IslandChipStyle(ink: ink))
        .background(OverlayMenuAnchorView(anchor: anchor))
        .help(Text("Mode"))
    }

    static func width(_ title: String) -> CGFloat {
        35 + min(TextMeasure.width(title, size: 11.5) + 4, titleLimit)
    }
}
