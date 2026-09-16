import SwiftUI
import VMCore

/// Step 2: island or pill, dark or light glass.
struct LookStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        ZStack(alignment: .topLeading) {
            StepTitle("Где показывать запись", size: 36)
                .frame(width: OnboardingLayout.size.width)
                .place(x: 0, y: 64)
            StepSubtitle("Поменять можно в настройках.")
                .frame(width: OnboardingLayout.size.width)
                .place(x: 0, y: 110)

            StyleCard(style: .island, detail: "у выреза камеры", selection: $settings.value.overlayStyle) {
                IslandPreview()
            }
            .place(x: 100, y: 150)

            StyleCard(style: .pill, detail: "внизу экрана", selection: $settings.value.overlayStyle) {
                PillPreview(light: settings.value.glass == .light)
            }
            .place(x: 490, y: 150)

            WorldSegmented(options: AppSettings.Glass.allCases, selection: $settings.value.glass) { glass in
                switch glass {
                case .dark: "Тёмное стекло"
                case .light: "Светлое стекло"
                }
            }
            .frame(width: OnboardingLayout.size.width)
            .place(x: 0, y: 462)
        }
        .stepCanvas()
    }
}

private struct StyleCard<Preview: View>: View {
    let style: AppSettings.OverlayStyle
    let detail: String
    @Binding var selection: AppSettings.OverlayStyle
    @ViewBuilder let preview: Preview

    private var selected: Bool { selection == style }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { selection = style }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    DesktopWallpaper()
                    preview
                }
                .frame(width: 350, height: 212)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 10) {
                    Radio(on: selected)
                    Text(style.title).font(.onest(16, .semibold))
                    Spacer(minLength: 0)
                    Muted(detail)
                }
                .padding(.horizontal, 10)
                .padding(.top, 16)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(width: 370, height: 290)
            .frost()
            .overlay {
                RoundedRectangle(cornerRadius: 21.25, style: .continuous)
                    .stroke(.white, lineWidth: 2.5)
                    .padding(-1.25)
                    .opacity(selected ? 1 : 0)
            }
            .shadow(color: Color(hex: 0x140A32, opacity: selected ? 0.5 : 0), radius: 18, y: 16)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct Radio: View {
    let on: Bool

    var body: some View {
        Circle()
            .strokeBorder(.white.opacity(on ? 1 : 0.6), lineWidth: on ? 6 : 1.5)
            .frame(width: 20, height: 20)
    }
}

// MARK: Previews

/// A stylised desktop behind the overlay previews.
private struct DesktopWallpaper: View {
    private struct Blob {
        let color: UInt32
        let center: UnitPoint
        let radius: CGSize
    }

    private let blobs = [
        Blob(color: 0x7B5CF0, center: UnitPoint(x: 0.2, y: 0.9), radius: CGSize(width: 0.5, height: 0.6)),
        Blob(color: 0xFF9A55, center: UnitPoint(x: 0.7, y: 0.9), radius: CGSize(width: 0.55, height: 0.6)),
        Blob(color: 0xF39BD0, center: UnitPoint(x: 0.78, y: 0.22), radius: CGSize(width: 0.4, height: 0.5)),
        Blob(color: 0x6BB7FF, center: UnitPoint(x: 0.18, y: 0.28), radius: CGSize(width: 0.45, height: 0.55)),
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Color(hex: 0x4B56C8)
                ForEach(blobs.indices, id: \.self) { index in
                    let blob = blobs[index]
                    let width = blob.radius.width * size.width * 2
                    let height = blob.radius.height * size.height * 2
                    EllipticalGradient(
                        stops: [
                            .init(color: Color(hex: blob.color), location: 0),
                            .init(color: Color(hex: blob.color, opacity: 0), location: 0.7),
                        ],
                        center: .center,
                        startRadiusFraction: 0,
                        endRadiusFraction: 0.5
                    )
                    .frame(width: width, height: height)
                    .offset(x: blob.center.x * size.width - width / 2, y: blob.center.y * size.height - height / 2)
                }
            }
        }
    }
}

private struct MiniWindow: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color(hex: 0x14141E, opacity: 0.55))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }
}

private struct MiniBars: View {
    let heights: [CGFloat]
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule().fill(color).frame(width: 3, height: heights[index])
            }
        }
    }
}

private struct MiniText: View {
    let light: Bool

    var body: some View {
        let code = Text(verbatim: "useEffect").font(.mono(10.6)).foregroundStyle(Color(hex: light ? 0x1172B8 : 0x8FE3FF))
        let dim = Text(verbatim: "в Header").foregroundStyle(light ? Color(hex: 0x17151B, opacity: 0.45) : .white.opacity(0.45))
        Text("поправь \(code) \(dim)")
            .lineLimit(1)
    }
}

private struct IslandPreview: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            MiniWindow().frame(width: 180, height: 130).place(x: 30, y: 60)
            MiniWindow().frame(width: 180, height: 120).place(x: 150, y: 80)

            ZStack(alignment: .topLeading) {
                IslandShape(ear: 10, radius: 20).fill(.black)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(Color(hex: 0xFF7A45))
                            .frame(width: 6, height: 6)
                            .shadow(color: Color(hex: 0xFF7A45), radius: 4)
                        Spacer()
                        Text("0:04").font(.mono(9)).opacity(0.6)
                    }
                    .frame(height: 20)
                    HStack(spacing: 10) {
                        MiniBars(heights: [4, 9, 12, 8, 12, 5], color: Color(hex: 0xFFB37A))
                        MiniText(light: false).font(.onest(11.5))
                    }
                }
                .padding(.horizontal, 26)
            }
            .foregroundStyle(.white)
            .frame(width: 270, height: 68)
            .place(x: 40, y: 0)
        }
        .frame(width: 350, height: 212, alignment: .topLeading)
    }
}

private struct PillPreview: View {
    let light: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            MiniWindow().frame(width: 180, height: 130).place(x: 30, y: 22)
            MiniWindow().frame(width: 180, height: 120).place(x: 150, y: 40)

            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(.white.opacity(light ? 0 : 0.1))
                    Circle()
                        .fill(Color(hex: 0xFF7A45))
                        .frame(width: 9, height: 9)
                        .background(Circle().fill(Color(hex: 0xFF7A45, opacity: 0.22)).frame(width: 17, height: 17))
                        .shadow(color: Color(hex: 0xFF7A45, opacity: 0.9), radius: 6)
                }
                .frame(width: 22, height: 22)
                MiniBars(heights: [5, 6, 6, 9, 5, 5], color: light ? Color(hex: 0x17151B) : .white)
                MiniText(light: light).font(.onest(11.5))
            }
            .foregroundStyle(light ? Color(hex: 0x17151B) : .white)
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .frame(height: 32)
            .background {
                Capsule()
                    .fill(light
                        ? AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.82), .white.opacity(0.62)], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x28262C, opacity: 0.72), Color(hex: 0x121016, opacity: 0.82)], startPoint: .top, endPoint: .bottom)))
                    .overlay(Capsule().strokeBorder(.white.opacity(light ? 0.7 : 0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(light ? 0.2 : 0.45), radius: 12, y: 8)
            }
            .fixedSize()
            .frame(width: 350)
            .place(x: 0, y: 212 - 14 - 32)
            .animation(.snappy(duration: 0.2), value: light)
        }
        .frame(width: 350, height: 212, alignment: .topLeading)
    }
}
