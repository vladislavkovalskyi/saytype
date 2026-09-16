import Foundation

/// Checks that a language model only restructured the text: the words stay the same and in
/// the same order. Allowed changes are punctuation, case, line breaks, list markers,
/// dropped fillers and dropped ordinal words ("во-первых") that became list numbers.
public enum StructureValidator {
    static let ordinals: Set<String> = ["во-первых", "во-вторых", "в-третьих", "в-четвертых", "в-пятых", "в-шестых", "firstly", "secondly", "thirdly"]
    static let hesitations: Set<String> = ["эээ", "ээ", "эм", "ммм", "мм", "аа", "ааа", "um", "uh"]
    static let fillers: Set<String> = ["ну", "типа", "короче", "вот", "значит", "слушай"]

    /// - Parameter allowDroppingFillers: whether "ну", "типа", "короче" may disappear too.
    public static func accepts(original: String, candidate: String, allowDroppingFillers: Bool = false) -> Bool {
        let droppable = { (key: String) in
            ordinals.contains(key) || hesitations.contains(key) || (allowDroppingFillers && fillers.contains(key))
        }
        let before = keys(original)
        let after = keys(candidate)
        guard !after.isEmpty, after.count <= before.count else { return false }

        var i = 0
        for word in after {
            while i < before.count, before[i] != word {
                guard droppable(before[i]) else { return false }
                i += 1
            }
            guard i < before.count else { return false }
            i += 1
        }
        return before[i...].allSatisfy(droppable)
    }

    /// Model output without wrappers it tends to add: code fences, quotes, markdown bold.
    public static func clean(_ output: String) -> String {
        var text = output
        if let think = text.range(of: "</think>") { text = String(text[think.upperBound...]) }
        text = text.replacingOccurrences(of: "```", with: "").replacingOccurrences(of: "**", with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("«", "»"), ("\"", "\"")] where text.hasPrefix(open) && text.hasSuffix(close) && text.count > 2 {
            let inner = text.dropFirst().dropLast()
            if !inner.contains(open) { text = String(inner) }
        }
        let lines = text.components(separatedBy: "\n").map { line in
            line.replacingOccurrences(of: #"^\s*[-•*]\s+"#, with: "— ", options: .regularExpression)
                .replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
        }
        return lines.joined(separator: "\n").replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    }

    static func keys(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"^\s*(\d{1,2}[.)]|[-•*—])\s+"#, with: "", options: .regularExpression) }
            .flatMap { Words.keys($0) }
    }
}
