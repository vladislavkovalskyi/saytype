import AppKit
import SwiftUI
import VMCore

/// The card the overlay keeps after a dictation in the Card output mode: the text and what to do
/// with it. One view in two skins — the island and the pill show the same card, only their
/// margins and colours differ.
struct OverlayCard: View {
    enum Style {
        /// Fills the height the island gives it: text at the top, actions at the bottom.
        case island
        /// Takes the height of its content; the pill's bubble grows around it.
        case pill
    }

    let model: OverlayModel
    let text: String
    var style = Style.island
    var light = false

    private var ink: Color { light ? Color(hex: 0x17151B) : .white }
    private var textInset: CGFloat { style == .island ? 24 : 0 }
    private var actionInset: CGFloat { style == .island ? 18 : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .island ? 0 : 12) {
            Text(CodeWords.attributed(text, size: 14))
                .font(.onest(14))
                .lineSpacing(3.5)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, textInset)
                .padding(.top, style == .island ? 8 : 0)
                .contentShape(Rectangle())
                .onDrag { NSItemProvider(object: text as NSString) }
            if style == .island {
                Spacer(minLength: 0)
            }
            actions
        }
    }

    private var actions: some View {
        let dictation = model.dictation
        return HStack(spacing: 6) {
            Button {
                dictation.copyCard()
            } label: {
                CardAction(title: "Copy", key: dictation.cardShortcutsActive ? "⌘C" : nil, ink: light ? .white : Color(hex: 0x1A1318))
            }
            .buttonStyle(CapsuleButtonStyle(prominent: true, light: light))
            Button {
                dictation.insertCard()
            } label: {
                CardAction(title: "Paste", key: dictation.cardShortcutsActive ? "V" : nil, ink: light ? Color(hex: 0x1A1318) : .white)
            }
            .buttonStyle(CapsuleButtonStyle(light: light))
            Spacer(minLength: 0)
            if style == .pill {
                // The island closes the card from its ear, where the ✕ sits in every state.
                Button {
                    dictation.dismissCard()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IslandIconButtonStyle(size: 26, tint: ink))
                .help(Text("Close"))
            }
        }
        .padding(.horizontal, actionInset)
        .padding(.bottom, style == .island ? 14 : 0)
    }
}
