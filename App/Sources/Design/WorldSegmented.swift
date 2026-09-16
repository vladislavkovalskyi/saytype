import SwiftUI

/// Segmented control on a colour world: translucent track, white pill on the selected segment.
struct WorldSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @Namespace private var pill

    init(selection: Binding<Value>, options: [(Value, String)]) {
        _selection = selection
        self.options = options.map { (value: $0.0, title: $0.1) }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                segment(options[index])
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.14)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .fixedSize()
    }

    private func segment(_ option: (value: Value, title: String)) -> some View {
        let isOn = option.value == selection
        return Button {
            withAnimation(.snappy(duration: 0.22)) { selection = option.value }
        } label: {
            Text(option.title)
                .font(.onest(13, isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? Color.ink : .white.opacity(0.86))
                .padding(.horizontal, 13)
                .frame(height: 28)
                .background {
                    if isOn {
                        Capsule()
                            .fill(.white)
                            .shadow(color: Color(hex: 0x140A1E, opacity: 0.18), radius: 4, y: 2)
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
