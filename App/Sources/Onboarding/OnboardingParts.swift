import AppKit
import SwiftUI

/// Every step is laid out on the full 960×640 window, like the mockups.
enum OnboardingLayout {
    static let size = CGSize(width: 960, height: 640)
    /// Left edge, top and width of the text column on the right.
    static let column = CGRect(x: 560, y: 142, width: 360, height: 0)
}

extension View {
    /// Positions a view by its top-left corner inside a top-leading step canvas.
    func place(x: CGFloat, y: CGFloat) -> some View {
        offset(x: x, y: y)
    }

    func stepCanvas() -> some View {
        frame(width: OnboardingLayout.size.width, height: OnboardingLayout.size.height, alignment: .topLeading)
    }
}

struct StepTitle: View {
    let text: String
    var size: CGFloat = 40

    init(_ text: String, size: CGFloat = 40) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.onest(size, .bold))
            .tracking(-0.022 * size)
            // Onest's natural line is about 1.3 em; the design sets titles at 1.05 em.
            .padding(.vertical, -0.125 * size)
    }
}

struct StepSubtitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.onest(15))
            .lineSpacing(3)
            .foregroundStyle(.white.opacity(0.84))
            .fixedSize(horizontal: false, vertical: true)
            // Half of the 1.5 em line height the design uses, above and below.
            .padding(.vertical, 1.75)
    }
}

/// A 3D object with its halo. `object` is the rect the object itself occupies in
/// the mockup; the cropped asset is fitted into it.
struct HeroObject: View {
    let name: String
    let halo: CGRect
    let object: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Halo()
                .frame(width: halo.width, height: halo.height)
                .place(x: halo.minX, y: halo.minY)
            Image(name)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: object.width, height: object.height)
                .place(x: object.minX, y: object.minY)
        }
        .stepCanvas()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Muted secondary line: 13 pt at 74 % white.
struct Muted: View {
    let text: String
    var size: CGFloat = 13

    init(_ text: String, size: CGFloat = 13) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.onest(size))
            .foregroundStyle(.white.opacity(0.74))
    }
}

/// Hairline between rows of a frosted list.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.14))
            .frame(height: 1)
    }
}
