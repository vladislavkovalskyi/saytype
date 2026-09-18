import Foundation

/// One finished dictation.
public struct DictationRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// What was inserted.
    public var text: String
    /// What Whisper heard before formatting.
    public var raw: String
    public var appName: String?
    public var bundleID: String?
    /// Seconds of speech.
    public var duration: Double
    public var date: Date

    public init(id: UUID = UUID(), text: String, raw: String, appName: String?, bundleID: String?, duration: Double, date: Date) {
        self.id = id
        self.text = text
        self.raw = raw
        self.appName = appName
        self.bundleID = bundleID
        self.duration = duration
        self.date = date
    }

    public var wordCount: Int { Words.split(text).count }
}

/// Dictation history kept as a JSON file on this Mac.
public actor HistoryStore {
    private let url: URL
    private var records: [DictationRecord] = []
    private var loaded = false

    public init(url: URL = HistoryStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "dev.kovalskyi.saytype/history.json")
    }

    /// Newest first.
    public func all() -> [DictationRecord] {
        loadIfNeeded()
        return records
    }

    public func add(_ record: DictationRecord, retentionDays: Int, now: Date = Date()) -> [DictationRecord] {
        loadIfNeeded()
        records.insert(record, at: 0)
        prune(retentionDays: retentionDays, now: now)
        save()
        return records
    }

    /// Replaces the text of a record the user edited. `raw` stays as Whisper heard it, so the
    /// history keeps showing what changed on the way from speech to text.
    public func update(_ id: UUID, text: String) -> [DictationRecord] {
        loadIfNeeded()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return records }
        records[index].text = text
        save()
        return records
    }

    public func remove(_ id: UUID) -> [DictationRecord] {
        loadIfNeeded()
        records.removeAll { $0.id == id }
        save()
        return records
    }

    public func clear() {
        records = []
        loaded = true
        save()
    }

    private func prune(retentionDays: Int, now: Date) {
        guard retentionDays > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        records.removeAll { $0.date < cutoff }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: url) else { return }
        records = (try? JSONDecoder.history.decode([DictationRecord].self, from: data)) ?? []
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.history.encode(records).write(to: url, options: .atomic)
        } catch {
            // History is a convenience; a failed write must not break dictation.
        }
    }
}

public struct HistoryStats: Equatable, Sendable {
    public var wordsToday: Int
    public var wordsThisWeek: Int
    /// Average speaking pace over today's dictations, 0 when there are none.
    public var wordsPerMinute: Int
    /// Seconds saved against typing the same words, see `secondsSaved(words:duration:typingWordsPerMinute:)`.
    public var secondsSavedToday: Double
    public var secondsSavedThisWeek: Double

    public init(records: [DictationRecord], typingWordsPerMinute: Int = 40, now: Date = Date(), calendar: Calendar = .current) {
        let weekStart = now.addingTimeInterval(-7 * 86_400)
        var wordsToday = 0
        var wordsThisWeek = 0
        var secondsToday = 0.0
        var savedToday = 0.0
        var savedThisWeek = 0.0
        for record in records {
            let isToday = calendar.isDate(record.date, inSameDayAs: now)
            guard isToday || record.date >= weekStart else { continue }
            let words = record.wordCount
            let saved = Self.secondsSaved(words: words, duration: record.duration, typingWordsPerMinute: typingWordsPerMinute)
            if record.date >= weekStart {
                wordsThisWeek += words
                savedThisWeek += saved
            }
            if isToday {
                wordsToday += words
                secondsToday += record.duration
                savedToday += saved
            }
        }
        self.wordsToday = wordsToday
        self.wordsThisWeek = wordsThisWeek
        wordsPerMinute = secondsToday > 0 ? Int((Double(wordsToday) / secondsToday * 60).rounded()) : 0
        secondsSavedToday = savedToday
        secondsSavedThisWeek = savedThisWeek
    }

    /// Typing time for the words minus the time spent speaking them; never negative.
    public static func secondsSaved(words: Int, duration: Double, typingWordsPerMinute: Int) -> Double {
        guard typingWordsPerMinute > 0 else { return 0 }
        return max(0, Double(words) / Double(typingWordsPerMinute) * 60 - duration)
    }
}

// MARK: Spelling fixes

/// A word picked in a past dictation and how it should be written, for the dictionary.
public enum HistoryCorrection {
    /// What Whisper heard for the final text's words in `range` (indices of whitespace-separated
    /// words): the raw words they came from when the alignment leaves no doubt, e.g. "Header" →
    /// "хедер", "useEffect" → "юз эффект"; otherwise the picked words themselves. Lowercase.
    public static func heard(raw: String, text: String, words range: ClosedRange<Int>) -> String {
        let textWords = Words.split(text)
        guard range.lowerBound >= 0, range.upperBound < textWords.count else { return "" }
        let picked = phrase(textWords[range])
        let rawWords = Words.split(raw)
        guard !rawWords.isEmpty else { return picked }

        let pairs = Words.alignment(rawWords.map(Words.key), textWords.map(Words.key))
        // Runs between matched words: raw words replaced by text words.
        var gaps: [(raw: Range<Int>, text: Range<Int>)] = []
        var rawStart = 0
        var textStart = 0
        var matchedRaw = [Int?](repeating: nil, count: textWords.count)
        for (r, t) in pairs + [(rawWords.count, textWords.count)] {
            if t > textStart { gaps.append((rawStart..<r, textStart..<t)) }
            if t < textWords.count { matchedRaw[t] = r }
            rawStart = r + 1
            textStart = t + 1
        }

        var lower = Int.max
        var upper = Int.min
        var covered = 0
        var seenGaps = Set<Int>()
        for index in range {
            if let r = matchedRaw[index] {
                lower = min(lower, r)
                upper = max(upper, r)
                covered += 1
                continue
            }
            guard let g = gaps.firstIndex(where: { $0.text.contains(index) }) else { return picked }
            guard !seenGaps.contains(g) else { continue }
            // Only a whole replaced run maps back: "use" alone out of "useEffect hook" is a guess.
            let gap = gaps[g]
            guard range.contains(gap.text.lowerBound), range.contains(gap.text.upperBound - 1) else { return picked }
            seenGaps.insert(g)
            var raw = gap.raw
            while let first = raw.first, isFiller(rawWords[first]) { raw = raw.dropFirst() }
            while let last = raw.last, isFiller(rawWords[last]) { raw = raw.dropLast() }
            guard !raw.isEmpty else { continue }
            lower = min(lower, raw.lowerBound)
            upper = max(upper, raw.upperBound - 1)
            covered += raw.count
        }
        // The raw words must be one run with nothing left out in between.
        guard covered > 0, upper - lower + 1 == covered else { return picked }
        return phrase(rawWords[lower...upper])
    }

    /// The dictionary entry for a fix; `nil` without a spelling. When the heard words only differ
    /// in case from the spelling, the entry keeps just the spelling, like "GitHub".
    public static func entry(heard: String, written: String) -> DictionaryEntry? {
        let written = written.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !written.isEmpty else { return nil }
        var heard = heard.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if heard.lowercased() == written.lowercased() { heard = "" }
        return DictionaryEntry(heard: heard, written: written, source: .history)
    }

    private static func phrase(_ words: ArraySlice<String>) -> String {
        words.map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)).lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func isFiller(_ word: String) -> Bool {
        let key = Words.key(word)
        return Cleanup.hesitations.contains(key) || Cleanup.fillerWords.contains(key)
    }
}

extension Array where Element == DictionaryEntry {
    /// Adds a fix from the history at the top, or updates the entry for the same heard words.
    /// Returns false when the dictionary already had it.
    @discardableResult
    public mutating func addCorrection(_ entry: DictionaryEntry) -> Bool {
        let heard = entry.heard.lowercased()
        let existing = firstIndex { current in
            heard.isEmpty
                ? current.heard.isEmpty && current.written.lowercased() == entry.written.lowercased()
                : current.heard.lowercased() == heard
        }
        guard let index = existing else {
            insert(entry, at: 0)
            return true
        }
        guard self[index].written != entry.written else { return false }
        self[index].written = entry.written
        return true
    }
}

extension JSONEncoder {
    static var history: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var history: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
