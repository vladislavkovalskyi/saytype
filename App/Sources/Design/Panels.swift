import SwiftUI

/// Frosted glass panel used for every content block on a colour world.
struct Frost: ViewModifier {
    var cornerRadius: CGFloat = 20
    var hot = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(hot ? 0.26 : 0.1))
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(hot ? 0.34 : 0.2), lineWidth: 1)
            }
    }
}

extension View {
    func frost(cornerRadius: CGFloat = 20, hot: Bool = false) -> some View {
        modifier(Frost(cornerRadius: cornerRadius, hot: hot))
    }
}

/// White pill toggle with a knob tinted by the world accent, as in the design.
struct WorldToggleStyle: ToggleStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 0)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? .white : .white.opacity(0.26))
                    Circle()
                        .fill(configuration.isOn ? accent : .white)
                        .padding(3)
                        .shadow(color: .black.opacity(configuration.isOn ? 0 : 0.25), radius: 1.5, y: 1)
                }
                .frame(width: 42, height: 25)
                .animation(.snappy(duration: 0.2), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Round glowing call-to-action at the bottom of onboarding steps.
struct RoundActionButton: View {
    let title: String
    let world: World
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.onest(15, .semibold))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.75), .white.opacity(0.25), .clear], center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: 50))
                        .background(Circle().fill(world.accent))
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                .background(Circle().fill(.white.opacity(0.16)).padding(-7))
                .shadow(color: .black.opacity(0.35), radius: 20, y: 16)
        }
        .buttonStyle(.plain)
    }
}
