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

    public init(records: [DictationRecord], now: Date = Date(), calendar: Calendar = .current) {
        let today = records.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let weekStart = now.addingTimeInterval(-7 * 86_400)
        wordsToday = today.reduce(0) { $0 + $1.wordCount }
        wordsThisWeek = records.filter { $0.date >= weekStart }.reduce(0) { $0 + $1.wordCount }
        let seconds = today.reduce(0) { $0 + $1.duration }
        wordsPerMinute = seconds > 0 ? Int((Double(wordsToday) / seconds * 60).rounded()) : 0
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
