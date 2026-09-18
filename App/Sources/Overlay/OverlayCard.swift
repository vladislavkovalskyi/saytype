import AppKit
import SwiftUI
import VMCore

/// The card the overlay keeps after a dictation in the Card output mode: the text, what to do
/// with it, and its editor. One view in two skins — the island and the pill show the same card,
/// only their margins and colours differ.
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
        let dictation = model.dictation
        VStack(alignment: .leading, spacing: style == .island ? 0 : 12) {
            if dictation.cardEditing {
                CardEditor(model: model, ink: ink)
                    .padding(.horizontal, textInset)
                    .padding(.top, style == .island ? 8 : 0)
                    .frame(maxHeight: style == .island ? .infinity : nil)
            } else {
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
                if !dictation.cardLearned.isEmpty {
                    LearnedRow(model: model, entries: dictation.cardLearned, ink: ink)
                        .padding(.horizontal, textInset)
                        .padding(.bottom, style == .island ? 8 : 0)
                        .transition(.opacity)
                }
            }
            actions(editing: dictation.cardEditing)
        }
        .animation(.snappy(duration: 0.2), value: dictation.cardLearned)
    }

    @ViewBuilder private func actions(editing: Bool) -> some View {
        let dictation = model.dictation
        HStack(spacing: 6) {
            if editing {
                Button {
                    dictation.commitCardEdit()
                } label: {
                    CardAction(title: "Save", key: "⌘↩", ink: light ? .white : Color(hex: 0x1A1318))
                }
                .buttonStyle(CapsuleButtonStyle(prominent: true, light: light))
                .keyboardShortcut(.return, modifiers: .command)
                Button {
                    dictation.cancelCardEdit()
                } label: {
                    CardAction(title: "Cancel", key: "esc", ink: ink)
                }
                .buttonStyle(CapsuleButtonStyle(light: light))
                .keyboardShortcut(.cancelAction)
            } else {
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
                Button {
                    dictation.beginCardEdit()
                } label: {
                    CardAction(title: "Edit", key: dictation.cardShortcutsActive ? "E" : nil, ink: light ? Color(hex: 0x1A1318) : .white)
                }
                .buttonStyle(CapsuleButtonStyle(light: light))
            }
            Spacer(minLength: 0)
            if style == .pill, !editing {
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

/// The card's text field. The panel is the key window only while this is on screen.
private struct CardEditor: View {
    let model: OverlayModel
    let ink: Color
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var dictation = model.dictation
        TextEditor(text: $dictation.cardDraft)
            .font(.onest(14))
            .foregroundStyle(ink)
            .tint(ink)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(minHeight: 62)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ink.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ink.opacity(focused ? 0.45 : 0.22), lineWidth: 1))
            }
            .task {
                // The panel becomes the key window a moment after the editor appears.
                try? await Task.sleep(for: .milliseconds(60))
                focused = true
            }
    }
}

/// "Added to dictionary · хедер → Header", with the ✕ that takes it back.
private struct LearnedRow: View {
    let model: OverlayModel
    let entries: [DictionaryEntry]
    let ink: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(OverlayPalette.done)
            Text("Added to dictionary")
                .font(.onest(11.5, .semibold))
            Text(verbatim: entries.map(\.readout).joined(separator: ", "))
                .font(.onest(11.5))
                .foregroundStyle(ink.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button {
                model.dictation.undoLearned()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(IslandIconButtonStyle(size: 20, filled: false, tint: ink))
            .help(Text("Undo"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 28)
        .background(Capsule().fill(ink.opacity(0.1)))
    }
}

extension DictionaryEntry {
    /// "хедер → Header", or the spelling alone when only the case was fixed.
    var readout: String {
        heard.isEmpty ? written : "\(heard) → \(written)"
    }
}
