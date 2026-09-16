import CoreText
import SwiftUI

enum Fonts {
    /// Registers the bundled Onest and JetBrains Mono for this process.
    static func register() {
        for name in ["Onest", "JetBrainsMono"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Interface text.
    static func onest(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Onest", size: size).weight(weight)
    }

    /// Code identifiers inside dictated text.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
}
