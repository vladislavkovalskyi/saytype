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
}

extension AnyTransition {
    /// Content swaps inside the island: fade through a light blur.
    static var islandContent: AnyTransition {
        .modifier(active: BlurFade(amount: 1), identity: BlurFade(amount: 0))
    }
}

private struct BlurFade: ViewModifier {
    let amount: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: 7 * amount)
            .opacity(1 - amount)
            .scaleEffect(1 - 0.03 * amount, anchor: .top)
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

/// Recent input levels as bars, newest on the right. Flat when the microphone hears nothing.
struct VoiceBars: View {
    let levels: [Float]
    var height: CGFloat = 16
    var barWidth: CGFloat = 3

    var body: some View {
        HStack(alignment: .center, spacing: barWidth * 0.7) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xFFC794), OverlayPalette.ember], startPoint: .top, endPoint: .bottom))
                    .frame(width: barWidth, height: max(barWidth, CGFloat(level) * height))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.12), value: levels)
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

/// A highlight that runs across the text while it is being formatted.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(0.75)
        } else {
            content.mask {
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
            }
        }
    }
}

/// Live words that wrap like a paragraph; new words fade in from a blur and the
/// unconfirmed tail stays dim. Shows the last `lines` lines.
struct LiveWords: View {
    let committed: String
    let pending: String
    var size: CGFloat = 15
    var lines = 2
    var dimPending = true
    var color: Color = .white

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
        let lineHeight = size * 1.42
        FlowLayout(spacing: size * 0.27, lineSpacing: lineHeight - size * 1.2) {
            ForEach(words) { word in
                Text(CodeWords.attributed(word.text, size: size))
                    .font(.onest(size))
                    .foregroundStyle(color.opacity(word.isPending && dimPending ? 0.44 : 1))
                    .fixedSize()
                    .transition(.islandContent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: lineHeight * CGFloat(lines), alignment: .bottomLeading)
        .clipped()
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22)], startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeOut(duration: 0.3), value: committed + "|" + pending)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.onest(11.5, .medium))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.2 : 0.1)))
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
