import AppKit
import SwiftUI

extension Color {
    /// Dark text on white controls.
    static let ink = Color(hex: 0x1D1A20)
}

// MARK: Buttons and chips

/// White capsule call-to-action inside panels.
struct WhiteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.onest(13, .semibold))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(.white).shadow(color: Color(hex: 0x140A1E, opacity: 0.18), radius: 7, y: 4))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
            .fixedSize()
    }
}

/// Translucent capsule for secondary actions.
struct ChipButtonStyle: ButtonStyle {
    var height: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.onest(13, .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: height)
            .background(ChipFill())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
            .fixedSize()
    }
}

/// Glassy capsule background used by chips that sit on a panel.
struct ChipFill: View {
    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom))
            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
    }
}

/// Keyboard key label.
struct Keycap: View {
    let label: String
    var height: CGFloat = 26
    var fontSize: CGFloat = 12.5

    init(_ label: String, height: CGFloat = 26, fontSize: CGFloat = 12.5) {
        self.label = label
        self.height = height
        self.fontSize = fontSize
    }

    var body: some View {
        Text(label)
            .font(.mono(fontSize, .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(minWidth: height, minHeight: height, maxHeight: height)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.2)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .fixedSize()
    }
}

/// Inline code identifier, e.g. `useEffect`.
struct CodeSpan: View {
    let text: String
    var size: CGFloat = 13
    var opacity: Double = 0.2

    var body: some View {
        Text(text)
            .font(.mono(size))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(opacity)))
            .fixedSize()
    }
}

// MARK: Section layout

/// Section title and one line under it.
struct SectionHeader<Subtitle: View>: View {
    let title: String
    let subtitle: Subtitle

    init(_ title: String, @ViewBuilder subtitle: () -> Subtitle) {
        self.title = title
        self.subtitle = subtitle()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.onest(30, .bold))
                .tracking(-0.6)
            subtitle
                .font(.onest(14))
                .foregroundStyle(.white.opacity(0.74))
        }
        .padding(.leading, 6)
        .padding(.top, 2)
    }
}

extension SectionHeader where Subtitle == Text {
    init(_ title: String, subtitle: String) {
        self.init(title) { Text(subtitle) }
    }
}

/// Big 3D object in the header corner, behind the panels.
///
/// `right` and `top` are the mockup's offsets from the window's right and top edges.
struct HeaderArt: View {
    let name: String
    let width: CGFloat
    let right: CGFloat
    let top: CGFloat

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: width * 0.92, height: width * 0.92)
            .frame(width: width, height: width)
            // The content area ends 16 pt before the window's right edge and starts 56 pt below its top.
            .offset(x: 16 - right, y: top - 56)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .allowsHitTesting(false)
    }
}

/// Small grey caption above a group of controls.
struct PanelLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.onest(12.5, .semibold))
            .foregroundStyle(.white.opacity(0.7))
    }
}

// MARK: Rows

/// One line of a settings panel: title, optional detail and a control on the right.
struct SettingsRow<Accessory: View>: View {
    let title: String
    let detail: Text?
    let accessory: Accessory

    init(_ title: String, detail: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail.map { Text($0) }
        self.accessory = accessory()
    }

    init(_ title: String, detailText: Text, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detailText
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 14) {
            RowTitle(title: title, detail: detail)
            Spacer(minLength: 0)
            accessory
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
    }
}

struct RowTitle: View {
    let title: String
    let detail: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.onest(14.5, .medium))
            if let detail {
                detail
                    .font(.onest(12.5))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

/// A settings row whose control is a world toggle; the whole row toggles.
struct ToggleRow: View {
    let title: String
    let detail: Text?
    @Binding var isOn: Bool
    let accent: Color

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>, accent: Color) {
        self.title = title
        self.detail = detail.map { Text($0) }
        _isOn = isOn
        self.accent = accent
    }

    init(_ title: String, detailText: Text, isOn: Binding<Bool>, accent: Color) {
        self.title = title
        self.detail = detailText
        _isOn = isOn
        self.accent = accent
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            RowTitle(title: title, detail: detail)
        }
        .toggleStyle(WorldToggleStyle(accent: accent))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
    }
}

/// Hairline between rows.
struct RowDivider: View {
    var opacity: Double = 0.14

    var body: some View {
        Rectangle().fill(.white.opacity(opacity)).frame(height: 1)
    }
}

// MARK: Menus

/// One entry of a popup menu; `isOn` shows a check mark.
struct MenuOption {
    let title: String
    let isOn: Bool
    let action: @MainActor () -> Void
}

/// A control that opens a native menu under itself.
struct PopupMenu<Label: View>: View {
    let items: [MenuOption]
    let label: Label
    @State private var anchor = MenuAnchor()

    init(items: [MenuOption], @ViewBuilder label: () -> Label) {
        self.items = items
        self.label = label()
    }

    var body: some View {
        Button {
            anchor.pop(items: items)
        } label: {
            label.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MenuAnchorView(anchor: anchor))
    }
}

/// Frost chip with a value and a chevron that opens a menu, e.g. "40 слов ⌄".
struct MenuChip: View {
    let title: String
    let items: [MenuOption]

    var body: some View {
        PopupMenu(items: items) {
            HStack(spacing: 6) {
                Text(title).font(.onest(13, .medium))
                Icon(.chevronDown, size: 14).opacity(0.85)
            }
            .padding(.leading, 13)
            .padding(.trailing, 10)
            .frame(height: 32)
            .background(ChipFill())
            .fixedSize()
        }
    }
}

@MainActor
final class MenuAnchor {
    weak var view: NSView?

    func pop(items: [MenuOption]) {
        guard let view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            menu.addItem(ActionMenuItem(title: item.title, isOn: item.isOn, action: item.action))
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 6), in: view)
    }
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = FlippedView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, isOn: Bool, action: @escaping @MainActor () -> Void) {
        handler = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = isOn ? .on : .off
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func fire() {
        // Menu actions arrive on the main thread.
        let handler = handler
        MainActor.assumeIsolated { handler() }
    }
}

// MARK: Search

/// Frosted search capsule.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var width: CGFloat? = 300
    var height: CGFloat = 38
    var frosted = true

    var body: some View {
        HStack(spacing: 8) {
            Icon(.search, size: 16).opacity(0.8)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(prompt).foregroundStyle(.white.opacity(0.75)).allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
            }
            .font(.onest(14))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Icon(.xmark, size: 14, stroke: 2).opacity(0.7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background {
            if !frosted {
                Capsule().fill(.white.opacity(0.14)).overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
            }
        }
        .modifier(OptionalFrost(enabled: frosted, cornerRadius: height / 2))
        .tint(.white)
    }
}

private struct OptionalFrost: ViewModifier {
    let enabled: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content.frost(cornerRadius: cornerRadius)
        } else {
            content
        }
    }
}
