import SwiftUI

/// A section's colour world: one saturated gradient across the whole window.
struct World: Sendable {
    let top: Color
    let upperMid: Color
    let lowerMid: Color
    let bottom: Color
    let highlight: Color
    let shade: Color
    /// Filled controls on white: toggle knobs, selected segments.
    let accent: Color

    static let ember = World(hex: 0xF29543, 0xE0602F, 0xC13A38, 0x761E3D, highlight: 0xFFD6A0, shade: 0x500E32, accent: 0xE0592E)
    static let violet = World(hex: 0xC07CF2, 0x9451E3, 0x6A32C4, 0x34186F, highlight: 0xECBEFF, shade: 0x1E0A46, accent: 0x7B3FE0)
    static let blue = World(hex: 0x6FB4FF, 0x3B82F0, 0x2C55D0, 0x1A2677, highlight: 0xBEE1FF, shade: 0x0A1046, accent: 0x2F6EE8)
    static let coral = World(hex: 0xFF9A8E, 0xF2596F, 0xCC3160, 0x6C1740, highlight: 0xFFCDCD, shade: 0x460A28, accent: 0xE8456A)
    static let green = World(hex: 0x8FE08F, 0x3FBF6E, 0x1E9259, 0x0E4A38, highlight: 0xCDFFCD, shade: 0x06281E, accent: 0x1F9D5C)
    static let cyan = World(hex: 0x7FDCFF, 0x2FB0EA, 0x1C7CC6, 0x0F3570, highlight: 0xC8F5FF, shade: 0x061A46, accent: 0x1A8FD6)
    static let teal = World(hex: 0x7EEACB, 0x2CC4A4, 0x179487, 0x0B4A4E, highlight: 0xC8FFF0, shade: 0x04282C, accent: 0x14A38A)
    static let pink = World(hex: 0xFF9FD4, 0xF35FAD, 0xC93488, 0x5E1449, highlight: 0xFFD2F0, shade: 0x3C0832, accent: 0xD83C94)

    private init(hex top: UInt32, _ upperMid: UInt32, _ lowerMid: UInt32, _ bottom: UInt32, highlight: UInt32, shade: UInt32, accent: UInt32) {
        self.top = Color(hex: top)
        self.upperMid = Color(hex: upperMid)
        self.lowerMid = Color(hex: lowerMid)
        self.bottom = Color(hex: bottom)
        self.highlight = Color(hex: highlight)
        self.shade = Color(hex: shade)
        self.accent = Color(hex: accent)
    }
}

struct WorldBackground: View {
    let world: World

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: world.top, location: 0),
                    .init(color: world.upperMid, location: 0.34),
                    .init(color: world.lowerMid, location: 0.64),
                    .init(color: world.bottom, location: 1),
                ],
                startPoint: UnitPoint(x: 0.1, y: 0),
                endPoint: UnitPoint(x: 0.9, y: 1)
            )
            RadialGradient(colors: [world.highlight.opacity(0.5), .clear], center: UnitPoint(x: 0.25, y: 0.2), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [world.shade.opacity(0.85), .clear], center: UnitPoint(x: 1, y: 1), startRadius: 0, endRadius: 640)
        }
        .ignoresSafeArea()
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
