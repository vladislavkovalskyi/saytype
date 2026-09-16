import Foundation
import SwiftUI
import VMCore

/// Russian number, date and duration strings for the main window.
enum Format {
    private static let locale = Locale(identifier: "ru_RU")

    /// Picks the Russian plural form: 1 термин, 2 термина, 5 терминов.
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = abs(n) % 10
        let n100 = abs(n) % 100
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }

    static func count(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(grouped(n)) \(plural(n, one, few, many))"
    }

    /// 8930 → "8 930" with a no-break space.
    static func grouped(_ n: Int) -> String {
        let digits = String(abs(n))
        var groups: [Substring] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.insert(digits[start..<end], at: 0)
            end = start
        }
        return (n < 0 ? "−" : "") + groups.joined(separator: "\u{00A0}")
    }

    /// 1.0 → "1,0".
    static func decimal(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    /// "11:42" today, "вчера, 11:42", otherwise "12 сент., 11:42".
    static func moment(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return time(date) }
        if calendar.isDateInYesterday(date) { return "вчера, \(time(date))" }
        return "\(date.formatted(.dateTime.day().month(.abbreviated).locale(locale))), \(time(date))"
    }

    /// Group title for a list of records: "Сегодня", "Вчера", "12 сентября".
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInYesterday(date) { return "Вчера" }
        let formatter = calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? dayFormatter : dayYearFormatter
        return formatter.string(from: date)
    }

    private static let dayFormatter = dateFormatter(template: "d MMMM")
    private static let dayYearFormatter = dateFormatter(template: "d MMMM y")

    private static func dateFormatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    /// 5.2 → "5 с", 72 → "1 мин 12 с".
    static func duration(_ seconds: Double) -> String {
        let total = max(1, Int(seconds.rounded()))
        guard total >= 60 else { return "\(total) с" }
        let rest = total % 60
        return rest == 0 ? "\(total / 60) мин" : "\(total / 60) мин \(rest) с"
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
