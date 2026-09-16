// Builds the built-in dictionary from design/dictionary/terms.txt.
//
//   swift scripts/build-dictionary.swift
//
// Writes Packages/SaytypeKit/Sources/VMCore/BuiltInDictionaryData.swift. For every heard form
// it adds Russian case endings of the last word and drops single-word forms that the macOS
// Russian spell checker knows as ordinary words ("расту" from "раст", "крон"). "!" keeps such
// a form without endings, "!!" keeps a loanword with its endings ("докер", "докере").

import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appending(path: "design/dictionary/terms.txt")
let output = root.appending(path: "Packages/SaytypeKit/Sources/VMCore/BuiltInDictionaryData.swift")

struct Term {
    var written: String
    var category: String
    /// forced: 1 keeps a Russian-word form, 2 also keeps its case endings.
    var heard: [(text: String, forced: Int)]
}

func normalize(_ text: String) -> String {
    text.lowercased()
        .replacingOccurrences(of: "ё", with: "е")
        .replacingOccurrences(of: "-", with: " ")
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
}

let checker = NSSpellChecker.shared
var spellCache: [String: Bool] = [:]
func isRussianWord(_ word: String) -> Bool {
    if let cached = spellCache[word] { return cached }
    let miss = checker.checkSpelling(of: word, startingAt: 0, language: "ru", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
    let known = miss.location == NSNotFound
    spellCache[word] = known
    return known
}

/// Case forms of a Russian loanword: "реакт" → "реакта", "реакте", "реактом"…
func inflections(of word: String) -> [String] {
    guard word.count >= 4, let last = word.last, word.allSatisfy({ ("а"..."я").contains(String($0)) || $0 == "й" }) else { return [] }
    let consonants = "бвгджзклмнпрстфхцчшщ"
    if consonants.contains(last) {
        return ["а", "у", "е", "ом", "ы", "ов", "ам", "ами", "ах", "и"].map { word + $0 }
    }
    let stem = String(word.dropLast())
    switch last {
    case "а": return ["ы", "е", "у", "ой", "и"].map { stem + $0 }
    case "я": return ["и", "е", "ю", "ей"].map { stem + $0 }
    case "ь": return ["я", "ю", "е", "ем", "и", "ей"].map { stem + $0 }
    case "й": return ["я", "ю", "е", "ем", "и", "ев"].map { stem + $0 }
    default: return []
    }
}

// MARK: Parse

var terms: [Term] = []
var index: [String: Int] = [:]
var categories: [(key: String, title: String)] = []
var category = "other"

for rawLine in try String(contentsOf: source, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false) {
    let line = rawLine.trimmingCharacters(in: .whitespaces)
    if line.hasPrefix("## ") {
        let parts = line.dropFirst(3).split(separator: ":", maxSplits: 1)
        category = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let title = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : category
        categories.append((category, title))
        continue
    }
    guard !line.isEmpty, !line.hasPrefix("#") else { continue }
    // "C++: си плюс плюс" — split on the first ": ", so written terms may contain ":".
    let written: String
    var heard: [(String, Int)] = []
    if let range = line.range(of: ": ") {
        written = String(line[..<range.lowerBound])
        heard = line[range.upperBound...].split(separator: ",").map { item in
            let text = item.trimmingCharacters(in: .whitespaces)
            let marks = text.prefix { $0 == "!" }.count
            return (String(text.dropFirst(marks)), min(marks, 2))
        }.filter { !$0.0.isEmpty }
    } else {
        written = line
    }
    if let existing = index[written] {
        terms[existing].heard += heard
    } else {
        index[written] = terms.count
        terms.append(Term(written: written, category: category, heard: heard))
    }
}

// MARK: Lookup table

var lookup: [String: String] = [:]
var dropped: [String] = []
var conflicts: [String] = []

func add(_ key: String, _ written: String) {
    if let existing = lookup[key] {
        if existing != written { conflicts.append("\(key): \(existing) / \(written)") }
        return
    }
    lookup[key] = written
}

// Base forms first, so they win over generated case forms of another term.
for term in terms {
    for (text, forced) in term.heard {
        let key = normalize(text)
        let single = !key.contains(" ")
        if single, forced == 0, isRussianWord(key) {
            dropped.append("\(key) (\(term.written))")
            continue
        }
        add(key, term.written)
    }
}
for term in terms {
    for (text, forced) in term.heard {
        let key = normalize(text)
        // A dropped base form gets no case endings either, and "!" words keep only the base:
        // "кафка" is Kafka, "Кафку" is the writer.
        guard lookup[key] == term.written, forced != 1 else { continue }
        var words = key.split(separator: " ").map(String.init)
        guard let last = words.popLast() else { continue }
        for form in inflections(of: last) {
            if words.isEmpty, forced < 2, isRussianWord(form) { continue }
            add((words + [form]).joined(separator: " "), term.written)
        }
    }
}

// MARK: Write

let catalog = terms.map { term in
    [term.category, term.written, term.heard.map(\.text).joined(separator: "|")].joined(separator: "\t")
}.joined(separator: "\n")
let table = lookup.sorted { $0.key < $1.key }.map { "\($0.key)\t\($0.value)" }.joined(separator: "\n")
let categoryList = categories.map { "\($0.key)\t\($0.title)" }.joined(separator: "\n")

let swift = """
// Generated by scripts/build-dictionary.swift from design/dictionary/terms.txt. Do not edit.
// \(terms.count) terms, \(lookup.count) heard forms.

extension BuiltInDictionary {
    /// category \\t title
    static let categoryData = #\"\"\"
\(categoryList)
\"\"\"#

    /// category \\t written \\t heard|heard
    static let catalogData = #\"\"\"
\(catalog)
\"\"\"#

    /// normalized heard form \\t written
    static let lookupData = #\"\"\"
\(table)
\"\"\"#
}

"""
try swift.write(to: output, atomically: true, encoding: .utf8)

print("terms: \(terms.count), heard forms with case endings: \(lookup.count)")
print("dropped as Russian words (\(dropped.count)): \(dropped.sorted().joined(separator: ", "))")
if !conflicts.isEmpty { print("conflicts (\(conflicts.count)): \(conflicts.joined(separator: "; "))") }
