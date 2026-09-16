import SwiftUI

/// Two or more options on a translucent track; the selected one is a white pill.
struct WorldSegmented<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.onest(13, on ? .semibold : .medium))
                        .foregroundStyle(on ? Color(hex: 0x1D1A20) : .white.opacity(0.86))
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background {
                            if on {
                                Capsule()
                                    .fill(.white)
                                    .shadow(color: Color(hex: 0x140A1E, opacity: 0.18), radius: 4, y: 2)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.14)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

/// Small white capsule button used inside frosted rows.
struct WhiteButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.onest(13, .semibold))
                .foregroundStyle(Color(hex: 0x1D1A20))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(.white))
                .shadow(color: Color(hex: 0x140A1E, opacity: 0.18), radius: 7, y: 4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// White status capsule with a green check: a permission is granted.
struct GrantedPill: View {
    var title = "Разрешено"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.onest(13, .semibold))
        }
        .foregroundStyle(Color(hex: 0x13804A))
        .padding(.leading, 9)
        .padding(.trailing, 12)
        .frame(height: 30)
        .background(Capsule().fill(.white.opacity(0.9)))
        .fixedSize()
    }
}

/// A key name set in monospace on a translucent keycap.
struct Kbd: View {
    let text: String
    var height: CGFloat = 26

    var body: some View {
        Text(text)
            .font(.mono(12.5, .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(minWidth: height, minHeight: height, maxHeight: height)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.2)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .fixedSize()
    }
}

/// Soft white glow behind a 3D object.
struct Halo: View {
    var body: some View {
        EllipticalGradient(
            colors: [.white.opacity(0.42), .white.opacity(0)],
            center: .center,
            startRadiusFraction: 0,
            endRadiusFraction: 0.5
        )
        .allowsHitTesting(false)
    }
}
