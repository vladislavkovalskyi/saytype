import Foundation
import VMCore

/// Word-level difference between what Whisper heard and the inserted text.
///
/// Words are matched by longest common subsequence on `Words.key`, so a word
/// that only gained a capital letter or a comma still counts as the same word;
/// inside such a word the changed characters are marked as added. Runs of
/// words that were rewritten (e.g. "во первых" → "во-первых") are compared
/// character by character when they are similar enough.
enum WordDiff {
    enum Kind: Equatable {
        case same
        case added
        case removed
    }

    struct Segment: Equatable {
        var text: String
        var kind: Kind
    }

    struct Word: Equatable {
        var segments: [Segment]
        /// The word opens a new paragraph of the inserted text.
        var startsParagraph = false

        var text: String { segments.map(\.text).joined() }
        var isUnchanged: Bool { segments.allSatisfy { $0.kind == .same } }
    }

    static func compare(raw: String, text: String) -> [Word] {
        let before = tokens(raw)
        let after = tokens(text)
        let pairs = lcs(before.map { Words.key($0.word) }, after.map { Words.key($0.word) })

        var result: [Word] = []
        var i = 0
        var j = 0
        func flushGap(to endI: Int, _ endJ: Int) {
            let removed = before[i..<endI].map(\.word)
            let added = Array(after[j..<endJ])
            if !removed.isEmpty, !added.isEmpty, let merged = mergeSimilar(removed: removed, added: added) {
                result.append(contentsOf: merged)
            } else {
                result.append(contentsOf: removed.map { Word(segments: [Segment(text: $0, kind: .removed)]) })
                result.append(contentsOf: added.map { Word(segments: [Segment(text: $0.word, kind: .added)], startsParagraph: $0.startsParagraph) })
            }
            i = endI
            j = endJ
        }
        for (pi, pj) in pairs {
            flushGap(to: pi, pj)
            var word = Word(segments: characterSegments(from: before[pi].word, to: after[pj].word))
            word.startsParagraph = after[pj].startsParagraph
            result.append(word)
            i = pi + 1
            j = pj + 1
        }
        flushGap(to: before.count, after.count)
        return result
    }

    // MARK: Tokens

    struct Token {
        var word: String
        var startsParagraph: Bool
    }

    static func tokens(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var word = ""
        var sawNewline = false
        for character in text {
            if character.isWhitespace {
                if !word.isEmpty {
                    tokens.append(Token(word: word, startsParagraph: sawNewline && !tokens.isEmpty))
                    word = ""
                    sawNewline = false
                }
                if character.isNewline {
                    sawNewline = true
                }
            } else {
                word.append(character)
            }
        }
        if !word.isEmpty {
            tokens.append(Token(word: word, startsParagraph: sawNewline && !tokens.isEmpty))
        }
        return tokens
    }

    // MARK: Matching

    /// Index pairs of a longest common subsequence.
    static func lcs<T: Equatable>(_ a: [T], _ b: [T]) -> [(Int, Int)] {
        let n = a.count
        let m = b.count
        guard n > 0, m > 0 else { return [] }
        var table = [Int32](repeating: 0, count: (n + 1) * (m + 1))
        for x in stride(from: n - 1, through: 0, by: -1) {
            for y in stride(from: m - 1, through: 0, by: -1) {
                table[x * (m + 1) + y] = a[x] == b[y]
                    ? table[(x + 1) * (m + 1) + y + 1] + 1
                    : max(table[(x + 1) * (m + 1) + y], table[x * (m + 1) + y + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var x = 0
        var y = 0
        while x < n, y < m {
            if a[x] == b[y] {
                pairs.append((x, y))
                x += 1
                y += 1
            } else if table[(x + 1) * (m + 1) + y] >= table[x * (m + 1) + y + 1] {
                x += 1
            } else {
                y += 1
            }
        }
        return pairs
    }

    /// The new word with the characters that were not in the old word marked as added.
    static func characterSegments(from old: String, to new: String) -> [Segment] {
        guard old != new else { return [Segment(text: new, kind: .same)] }
        let oldCharacters = Array(old)
        let newCharacters = Array(new)
        let matched = Set(lcs(oldCharacters, newCharacters).map(\.1))
        var segments: [Segment] = []
        for (index, character) in newCharacters.enumerated() {
            let kind: Kind = matched.contains(index) ? .same : .added
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1].text.append(character)
            } else {
                segments.append(Segment(text: String(character), kind: kind))
            }
        }
        return segments
    }

    /// "во первых" → "во-первых": show the new words with only the changed characters marked.
    private static func mergeSimilar(removed: [String], added: [Token]) -> [Word]? {
        let old = removed.joined(separator: " ")
        let new = added.map(\.word).joined(separator: " ")
        guard old.count <= 200, new.count <= 200 else { return nil }
        // Similarity ignores case: "во вторых" and "Во-вторых," are the same words.
        let common = lcs(Array(old.lowercased()), Array(new.lowercased())).count
        let longest = max(old.count, new.count)
        guard longest > 0, Double(common) / Double(longest) >= 0.7 else { return nil }
        var words: [Word] = []
        var offset = 0
        // Cut the character segments back into the new words.
        let flat: [(Character, Kind)] = characterSegments(from: old, to: new).flatMap { segment in
            segment.text.map { ($0, segment.kind) }
        }
        for token in added {
            let length = token.word.count
            var word = Word(segments: [], startsParagraph: token.startsParagraph)
            for (character, kind) in flat[offset..<offset + length] {
                if let last = word.segments.last, last.kind == kind {
                    word.segments[word.segments.count - 1].text.append(character)
                } else {
                    word.segments.append(Segment(text: String(character), kind: kind))
                }
            }
            words.append(word)
            offset += length
            // Skip the space between the new words.
            if offset < flat.count {
                offset += 1
            }
        }
        return words
    }
}
