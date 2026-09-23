import Foundation

/// A rough transcription of a word as a Russian speaker says it, the same for an English
/// spelling and its Cyrillic rendering: `DictationController` and "диктишн контроллер" both
/// become `daktaSnkantralar`.
///
/// One ASCII letter per sound class. Vowels are all `a`, and a run of them is one `a`: English
/// vowels and their Russian renderings disagree too often to tell apart. `g` holds г, g, j and
/// дж; `s` holds с, з, s, z and a soft c; `S` holds ш, щ, ж, sh and the "tion" of English; `C` is
/// ч, ch and tch; `h` is х and h; `T` is the English th, near т, с, з and ф. A doubled sound is
/// one sound. `e` is an English final e after a
/// consonant, silent in "case" and sounded in "readme": it costs next to nothing either way.
public enum SoundKey {
    public static let vowel = UInt8(ascii: "a")
    /// English final e: silent in "case", sounded in "readme".
    public static let optionalVowel = UInt8(ascii: "e")

    /// The key of a word, or of an identifier taken part by part so each part's silent final
    /// "e" is dropped (`useAuthSession` → use, auth, session). Punctuation and marks between
    /// parts add nothing.
    public static func key(_ word: String) -> [UInt8] {
        var output: [UInt8] = []
        for part in parts(of: word) {
            append(part.latin ? latinKey(part.text) : cyrillicKey(part.text), to: &output)
        }
        return output
    }

    /// Joins keys the way the spoken words run together: a sound doubled at the join is one.
    public static func append(_ key: [UInt8], to output: inout [UInt8]) {
        for sound in key {
            switch (output.last, sound) {
            case (optionalVowel, vowel): output[output.count - 1] = vowel
            case (vowel, optionalVowel), (optionalVowel, optionalVowel): continue
            case let (last, sound) where last == sound: continue
            default: output.append(sound)
            }
        }
    }

    public static func string(_ key: [UInt8]) -> String {
        String(decoding: key, as: UTF8.self)
    }

    // MARK: Distance

    /// A weighted edit distance: adding or dropping a vowel, or swapping sounds that differ only in
    /// voicing (т/д, к/г, с/ш), costs half; anything else costs one.
    public static func distance(_ a: [UInt8], _ b: [UInt8], limit: Double = .infinity) -> Double {
        if a.isEmpty { return b.reduce(0) { $0 + indelCost($1) } }
        if b.isEmpty { return a.reduce(0) { $0 + indelCost($1) } }
        var previous = [Double](repeating: 0, count: b.count + 1)
        var current = [Double](repeating: 0, count: b.count + 1)
        for j in 0..<b.count { previous[j + 1] = previous[j] + indelCost(b[j]) }
        for i in 0..<a.count {
            current[0] = previous[0] + indelCost(a[i])
            var rowMinimum = current[0]
            for j in 0..<b.count {
                let replace = previous[j] + substitutionCost(a[i], b[j])
                let delete = previous[j + 1] + indelCost(a[i])
                let insert = current[j] + indelCost(b[j])
                current[j + 1] = min(replace, delete, insert)
                rowMinimum = min(rowMinimum, current[j + 1])
            }
            // Every later row is at least this far; nothing under the limit is left.
            if rowMinimum > limit { return rowMinimum }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    static func indelCost(_ sound: UInt8) -> Double {
        switch sound {
        case optionalVowel: 0.1
        case vowel: 0.5
        default: 1
        }
    }

    static func substitutionCost(_ a: UInt8, _ b: UInt8) -> Double {
        if a == b { return 0 }
        if (a == optionalVowel && b == vowel) || (a == vowel && b == optionalVowel) { return 0.1 }
        if a == optionalVowel || b == optionalVowel { return 1 }
        return isNear(a, b) ? 0.5 : 1
    }

    /// Voiced and voiceless pairs, and sounds Russian speech swaps in English words.
    static func isNear(_ a: UInt8, _ b: UInt8) -> Bool {
        nearPairs.contains(UInt16(min(a, b)) << 8 | UInt16(max(a, b)))
    }

    private static let nearPairs: Set<UInt16> = {
        let pairs = ["pb", "td", "kg", "fv", "sS", "SC", "hg", "hk", "tC", "Tt", "Ts", "Tf", "Td"]
        return Set(pairs.map { pair in
            let bytes = Array(pair.utf8)
            return UInt16(min(bytes[0], bytes[1])) << 8 | UInt16(max(bytes[0], bytes[1]))
        })
    }()

    // MARK: Parts

    struct Part {
        let text: String
        let latin: Bool
    }

    /// Latin runs split at camelCase humps, digits kept with their run; Cyrillic runs as they are.
    /// "useAufSession" → use, auf, session; "фич-юзер" → фич, юзер.
    static func parts(of word: String) -> [Part] {
        var result: [Part] = []
        var current = ""
        var currentLatin = false
        func flush() {
            if !current.isEmpty { result.append(Part(text: current.lowercased(), latin: currentLatin)) }
            current = ""
        }
        let characters = Array(word)
        for (i, c) in characters.enumerated() {
            let latin = DeveloperText.isASCIILetter(c) || DeveloperText.isASCIIDigit(c)
            let cyrillic = !latin && c.isLetter && c.unicodeScalars.first.map { (0x400...0x4FF).contains($0.value) } == true
            guard latin || cyrillic else {
                flush()
                continue
            }
            if !current.isEmpty, latin != currentLatin { flush() }
            if latin, !current.isEmpty, c.isUppercase {
                // useAuth → use | Auth; HTTPServer → HTTP | Server.
                let previous = characters[i - 1]
                let nextIsLower = i + 1 < characters.count && characters[i + 1].isLowercase
                if previous.isLowercase || previous.isNumber || (previous.isUppercase && nextIsLower) { flush() }
            }
            currentLatin = latin
            current.append(c)
        }
        flush()
        return result
    }

    // MARK: English spelling

    private static let a = UInt8(ascii: "a")

    static func latinKey(_ text: String) -> [UInt8] {
        var letters = Array(text.utf8)
        // A final e after a consonant is silent in case, use, service, but not in readme, so it
        // becomes a vowel that costs next to nothing to add, drop or swap: `e`.
        var silentEnd = false
        if letters.count > 2, letters.last == UInt8(ascii: "e"), !isVowelLetter(letters[letters.count - 2]) {
            letters.removeLast()
            silentEnd = true
        }
        var out: [UInt8] = []
        func emit(_ sounds: String) {
            for sound in sounds.utf8 where out.last != sound { out.append(sound) }
        }
        func at(_ i: Int) -> UInt8 { i < letters.count ? letters[i] : 0 }
        func matches(_ i: Int, _ pattern: String) -> Bool {
            let bytes = Array(pattern.utf8)
            guard i + bytes.count <= letters.count else { return false }
            return Array(letters[i..<i + bytes.count]) == bytes
        }
        var i = 0
        while i < letters.count {
            let c = letters[i]
            switch c {
            case UInt8(ascii: "t"):
                if matches(i, "tion") { emit("Sn"); i += 4; continue }
                if matches(i, "tch") { emit("C"); i += 3; continue }
                // "feature" has lost its final e by now.
                if matches(i, "ture") { emit("Car"); i += 4; continue }
                if matches(i, "tur"), i + 3 == letters.count { emit("Car"); i += 3; continue }
                // Russian speech says th as т, с, з or ф: "аус", "ауф" for auth.
                if matches(i, "th") { emit("T"); i += 2; continue }
                emit("t")
            case UInt8(ascii: "s"):
                if matches(i, "ssion") { emit("Sn"); i += 5; continue }
                if matches(i, "sion") { emit("Sn"); i += 4; continue }
                if matches(i, "sh") { emit("S"); i += 2; continue }
                emit("s")
            case UInt8(ascii: "c"):
                if matches(i, "ch") { emit("C"); i += 2; continue }
                if matches(i, "ck") { emit("k"); i += 2; continue }
                // The final e is gone by now, but it still softens the c: juice, service.
                let next = i + 1 == letters.count && silentEnd ? UInt8(ascii: "e") : at(i + 1)
                emit(next == UInt8(ascii: "e") || next == UInt8(ascii: "i") || next == UInt8(ascii: "y") ? "s" : "k")
            case UInt8(ascii: "p"):
                if matches(i, "ph") { emit("f"); i += 2; continue }
                emit("p")
            case UInt8(ascii: "w"):
                if matches(i, "wh") { emit("v"); i += 2; continue }
                // "window" starts with в; "new", "flow" end in a vowel.
                emit(i > 0 && isVowelLetter(at(i - 1)) ? "a" : "v")
            case UInt8(ascii: "g"):
                if matches(i, "gh") {
                    if i == 0 { emit("g") }
                    i += 2
                    continue
                }
                emit("g")
            case UInt8(ascii: "k"):
                if i == 0, at(1) == UInt8(ascii: "n") { i += 1; continue }
                emit("k")
            case UInt8(ascii: "q"):
                if at(i + 1) == UInt8(ascii: "u") { emit("kv"); i += 2; continue }
                emit("k")
            case UInt8(ascii: "x"): emit("ks")
            case UInt8(ascii: "j"): emit("g")
            case UInt8(ascii: "z"): emit("s")
            case UInt8(ascii: "h"): emit("h")
            case UInt8(ascii: "a"), UInt8(ascii: "e"), UInt8(ascii: "i"), UInt8(ascii: "o"), UInt8(ascii: "u"), UInt8(ascii: "y"):
                emit("a")
            default:
                // b d f l m n r v and digits sound as written.
                if (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) { emit(String(UnicodeScalar(c))) }
            }
            i += 1
        }
        if silentEnd, out.last != vowel { out.append(optionalVowel) }
        return out
    }

    private static func isVowelLetter(_ c: UInt8) -> Bool {
        c == UInt8(ascii: "a") || c == UInt8(ascii: "e") || c == UInt8(ascii: "i") || c == UInt8(ascii: "o") || c == UInt8(ascii: "u") || c == UInt8(ascii: "y")
    }

    // MARK: Cyrillic

    static func cyrillicKey(_ text: String) -> [UInt8] {
        let letters = Array(text.replacingOccurrences(of: "ё", with: "е"))
        var out: [UInt8] = []
        func emit(_ sounds: String) {
            for sound in sounds.utf8 where out.last != sound { out.append(sound) }
        }
        var i = 0
        while i < letters.count {
            let c = letters[i]
            let next: Character? = i + 1 < letters.count ? letters[i + 1] : nil
            if c == "д", next == "ж" { emit("g"); i += 2; continue }
            if c == "т", next == "ч" { emit("C"); i += 2; continue }
            if let sounds = cyrillic[c] { emit(sounds) }
            i += 1
        }
        return out
    }

    private static let cyrillic: [Character: String] = [
        "а": "a", "е": "a", "и": "a", "о": "a", "у": "a", "ы": "a", "э": "a", "ю": "a", "я": "a", "й": "a",
        "б": "b", "в": "v", "г": "g", "д": "d", "ж": "S", "з": "s", "к": "k", "л": "l", "м": "m", "н": "n",
        "п": "p", "р": "r", "с": "s", "т": "t", "ф": "f", "х": "h", "ц": "ts", "ч": "C", "ш": "S", "щ": "S",
        "ь": "", "ъ": "",
    ]
}
