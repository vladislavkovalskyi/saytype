import SwiftUI
import VMCore

extension AttributedString {
    /// Dictated text with identifiers like `useEffect` set in the code font on a soft chip.
    /// Prose keeps the font of the surrounding view; `size` is that font's size.
    static func dictated(_ text: String, size: CGFloat, chip: Color = .white.opacity(0.22)) -> AttributedString {
        var result = AttributedString()
        var token = ""

        func flush() {
            guard !token.isEmpty else { return }
            var run = AttributedString(token)
            if Words.isCodeLike(token) {
                run.font = .mono(size - 1, .medium)
                run.backgroundColor = chip
            }
            result += run
            token = ""
        }

        for character in text {
            if character.isWhitespace {
                flush()
                result += AttributedString(String(character))
            } else {
                token.append(character)
            }
        }
        flush()
        return result
    }
}
