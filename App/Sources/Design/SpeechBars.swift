import SwiftUI

/// Static waveform that looks like a short phrase: louder in the middle, uneven syllables.
/// Same seed, same bars, matching the `bars` macro of the design mockups.
struct SpeechBars: View {
    let count: Int
    let seed: Int
    var minHeight: CGFloat = 2
    var maxHeight: CGFloat = 10
    var barWidth: CGFloat = 2
    var spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(Self.heights(count: count, seed: seed, min: minHeight, max: maxHeight).enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .frame(width: barWidth, height: height)
            }
        }
        .frame(height: maxHeight)
    }

    static func heights(count: Int, seed: Int, min lo: CGFloat, max hi: CGFloat) -> [CGFloat] {
        var state = seed * 7919 + 17
        func random() -> Double {
            state = (state * 9301 + 49297) % 233_280
            return Double(state) / 233_280
        }
        return (0..<count).map { i in
            let t = count == 1 ? 0.5 : Double(i) / Double(count - 1)
            let envelope = pow(sin(Double.pi * (0.08 + 0.84 * t)), 0.7)
            let syllable = 0.5 + 0.5 * abs(sin(Double(i) * 1.37 + Double(seed)))
            let height = Double(lo) + Double(hi - lo) * envelope * syllable * (0.45 + 0.55 * random())
            return Swift.max(lo, CGFloat(height.rounded()))
        }
    }
}
