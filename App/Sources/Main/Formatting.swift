import Foundation
import SwiftUI
import VMCore

/// Number, date and duration strings for the main window, in the user's locale.
/// Plural words live in the string catalog.
enum Format {
    /// 8930 → "8,930" or "8 930".
    static func grouped(_ n: Int) -> String {
        n.formatted()
    }

    /// 1.0 → "1.0" or "1,0".
    static func decimal(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    /// "11:42 AM" or "11:42".
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// "11:42" today, "yesterday, 11:42", otherwise "Sep 12 at 11:42".
    static func moment(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return time(date) }
        if calendar.isDateInYesterday(date) { return "\(relativeDay(-1, context: .middleOfSentence)), \(time(date))" }
        return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    /// Group title for a list of records: "Today", "Yesterday", "September 12".
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return relativeDay(0, context: .beginningOfSentence) }
        if calendar.isDateInYesterday(date) { return relativeDay(-1, context: .beginningOfSentence) }
        let sameYear = calendar.isDate(date, equalTo: Date(), toGranularity: .year)
        return date.formatted(sameYear ? .dateTime.day().month(.wide) : .dateTime.day().month(.wide).year())
    }

    /// "Today", "yesterday": the named day `days` from today.
    private static func relativeDay(_ days: Int, context: Formatter.Context) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.formattingContext = context
        return formatter.localizedString(from: DateComponents(day: days))
    }

    /// 5.2 → "5 sec", 72 → "1 min, 12 sec".
    static func duration(_ seconds: Double) -> String {
        Duration.seconds(max(1, Int(seconds.rounded()))).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }
}

/// Spots identifiers in dictated text so they can be set in the code font.
enum CodeWords {
    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:!?…«»\"'()[]")

    static func isCode(_ word: String) -> Bool {
        Words.isCodeLike(word)
    }

    /// The word without the punctuation around it, and that punctuation.
    static func split(_ word: String) -> (leading: String, core: String, trailing: String) {
        let leading = String(word.prefix { $0.unicodeScalars.allSatisfy(edgePunctuation.contains) })
        let rest = word.dropFirst(leading.count)
        let trailing = String(String(rest.reversed()).prefix { $0.unicodeScalars.allSatisfy(edgePunctuation.contains) }.reversed())
        let core = String(rest.dropLast(trailing.count))
        return (leading, core, trailing)
    }

    /// The text with identifiers in JetBrains Mono, sized to sit on the Onest line.
    /// `chip` puts a soft background behind each identifier.
    static func attributed(_ text: String, size: CGFloat, chip: Color? = nil) -> AttributedString {
        var result = AttributedString()
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            let parts = split(word)
            if isCode(parts.core) {
                var code = AttributedString(parts.core)
                code.font = .mono(size * 0.88)
                if let chip { code.backgroundColor = chip }
                result += AttributedString(parts.leading) + code + AttributedString(parts.trailing)
            } else {
                result += AttributedString(word)
            }
            word = ""
        }
        for character in text {
            if character.isWhitespace {
                flush()
                result += AttributedString(String(character))
            } else {
                word.append(character)
            }
        }
        flush()
        return result
    }
}
