import Foundation
import Testing
@testable import VMCore

@Suite struct HistoryDecodingTests {
    /// A history file as 0.3.0 wrote it, before recordings were kept.
    let legacy = """
    [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"Поправь useEffect.","raw":"поправь юз эффект","appName":"Terminal","bundleID":"com.apple.Terminal","duration":2.5,"date":"2026-09-20T10:15:00Z"},
     {"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","text":"Ок","raw":"ок","duration":0.8,"date":"2026-09-19T08:00:00Z"}]
    """

    @Test func oldHistoryDecodesUnchanged() throws {
        let records = try JSONDecoder.history.decode([DictationRecord].self, from: Data(legacy.utf8))
        #expect(records.count == 2)
        #expect(records[0].text == "Поправь useEffect.")
        #expect(records[0].appName == "Terminal")
        #expect(records[0].audio == nil)
        #expect(records[0].modeID == nil)
        #expect(records[0].failure == nil)
        #expect(records[0].previous == nil)
        #expect(records[0].action == nil)
        #expect(records[0].isTranscribed)
        #expect(records[1].appName == nil)
    }

    @Test func aVoiceActionAndARecordingRoundTripSideBySide() throws {
        var record = DictationRecord(text: "Hola", raw: "переведи выделенное на испанский", appName: "Notes", bundleID: nil, duration: 2, date: Date(timeIntervalSince1970: 1_790_000_000), audio: "A.caf", modeID: "standard", action: DictationRecord.Action(source: .selection, target: "es"))
        record.previous = DictationRecord.Version(text: "было", raw: "было")
        let decoded = try JSONDecoder.history.decode([DictationRecord].self, from: JSONEncoder.history.encode([record]))
        #expect(decoded == [record])
        #expect(decoded[0].action?.target == "es")
        #expect(decoded[0].spokenWordCount == 4)
    }

    @Test func a009HistoryWithAnActionDecodes() throws {
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"Hola","raw":"переведи выделенное на испанский","duration":2,"date":"2026-09-20T10:15:00Z","action":{"source":"selection","target":"es"}}]
        """
        let records = try JSONDecoder.history.decode([DictationRecord].self, from: Data(json.utf8))
        #expect(records[0].action == DictationRecord.Action(source: .selection, target: "es"))
        #expect(records[0].audio == nil)
        #expect(records[0].isTranscribed)
    }

    @Test func oldHistoryFileLoadsThroughTheStore() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "saytype-legacy-\(UUID().uuidString).json")
        try Data(legacy.utf8).write(to: url)
        let records = await HistoryStore(url: url).all()
        #expect(records.map(\.text) == ["Поправь useEffect.", "Ок"])
    }

    @Test func newFieldsRoundTrip() throws {
        var record = DictationRecord(text: "", raw: "", appName: "Notes", bundleID: nil, duration: 3, date: Date(timeIntervalSince1970: 1_790_000_000), audio: "A.caf", modeID: "message", failure: .interrupted)
        record.previous = DictationRecord.Version(text: "было", raw: "было")
        let data = try JSONEncoder.history.encode([record])
        let decoded = try JSONDecoder.history.decode([DictationRecord].self, from: data)
        #expect(decoded == [record])
    }

    @Test func unknownFailureFromANewerBuildDoesNotLoseTheHistory() throws {
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"","raw":"","duration":1,"date":"2026-09-20T10:15:00Z","audio":"x.caf","failure":"somethingNew"}]
        """
        let records = try JSONDecoder.history.decode([DictationRecord].self, from: Data(json.utf8))
        #expect(records.count == 1)
        #expect(records[0].audio == "x.caf")
        #expect(records[0].failure == nil)
    }
}

@Suite struct AudioKeepingTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func record(ago hours: Double, audio: Bool = true, failure: DictationRecord.Failure? = nil) -> DictationRecord {
        let id = UUID()
        return DictationRecord(id: id, text: failure == nil ? "текст" : "", raw: "", appName: nil, bundleID: nil, duration: 1, date: now.addingTimeInterval(-hours * 3600), audio: audio ? "\(id.uuidString).caf" : nil, failure: failure)
    }

    @Test func aDayKeepsYoungRecordingsOnly() {
        let young = record(ago: 2)
        let old = record(ago: 25)
        let expired = AudioKeeping.expired([young, old], retention: .day, limit: 20, now: now)
        #expect(expired == [old.id])
    }

    @Test func aWeekKeepsSixDaysOld() {
        let old = record(ago: 6 * 24)
        #expect(AudioKeeping.expired([old], retention: .week, limit: 20, now: now).isEmpty)
        #expect(AudioKeeping.expired([old], retention: .day, limit: 20, now: now) == [old.id])
    }

    @Test func theCountKeepsTheNewest() {
        let records = (0..<25).map { record(ago: Double($0) * 0.1) }
        let expired = AudioKeeping.expired(records, retention: .day, limit: 20, now: now)
        #expect(expired == Set(records.suffix(5).map(\.id)))
    }

    @Test func recordsWithoutAudioDoNotCountAgainstTheLimit() {
        let records = [record(ago: 0.1), record(ago: 0.2, audio: false), record(ago: 0.3)]
        #expect(AudioKeeping.expired(records, retention: .day, limit: 2, now: now).isEmpty)
    }

    @Test func offDropsEverything() {
        let records = [record(ago: 0.1), record(ago: 0.2, audio: false)]
        #expect(AudioKeeping.expired(records, retention: .off, limit: 20, now: now) == [records[0].id])
    }

    @Test func straysAreUnlinkedAndNotBeingRecorded() {
        let linked = record(ago: 1)
        let unlinked = record(ago: 1, audio: false)
        let orphan = UUID()
        let active = UUID()
        let files = [linked.audio!, "\(unlinked.id.uuidString).caf", "\(orphan.uuidString).caf", "\(active.uuidString).caf", ".DS_Store", "notes.txt"]
        let strays = AudioKeeping.strays(files: files, records: [linked, unlinked], active: [active])
        #expect(strays == [unlinked.id, orphan])
    }

    @Test func recordingIDFromFileName() {
        let id = UUID()
        #expect(AudioKeeping.recordingID("\(id.uuidString).caf") == id)
        #expect(AudioKeeping.recordingID("history.json") == nil)
    }
}

@Suite struct HistoryAudioTests {
    func tempStore() -> HistoryStore {
        HistoryStore(url: FileManager.default.temporaryDirectory.appending(path: "saytype-history-\(UUID().uuidString).json"))
    }

    @Test func droppingAudioUnlinksDictationsAndRemovesBareRecordings() async {
        let store = tempStore()
        let now = Date()
        let dictation = DictationRecord(text: "текст", raw: "текст", appName: nil, bundleID: nil, duration: 1, date: now, audio: "a.caf")
        let bare = DictationRecord(text: "", raw: "", appName: nil, bundleID: nil, duration: 1, date: now.addingTimeInterval(-1), audio: "b.caf", failure: .nothingHeard)
        _ = await store.add(bare, retentionDays: 30, now: now)
        _ = await store.add(dictation, retentionDays: 30, now: now)
        let records = await store.dropAudio([dictation.id, bare.id])
        #expect(records.map(\.id) == [dictation.id])
        #expect(records[0].audio == nil)
    }

    @Test func foundRecordingsGoInByDate() async {
        let store = tempStore()
        let now = Date()
        let newest = DictationRecord(text: "новая", raw: "", appName: nil, bundleID: nil, duration: 1, date: now)
        let oldest = DictationRecord(text: "старая", raw: "", appName: nil, bundleID: nil, duration: 1, date: now.addingTimeInterval(-600))
        _ = await store.add(oldest, retentionDays: 30, now: now)
        _ = await store.add(newest, retentionDays: 30, now: now)
        let found = DictationRecord(text: "", raw: "", appName: nil, bundleID: nil, duration: 5, date: now.addingTimeInterval(-300), audio: "c.caf", failure: .interrupted)
        let records = await store.insert([found, found])
        #expect(records.map(\.id) == [newest.id, found.id, oldest.id])
    }

    @Test func modifyChangesOneRecord() async {
        let store = tempStore()
        let record = DictationRecord(text: "было", raw: "было", appName: nil, bundleID: nil, duration: 1, date: Date())
        _ = await store.add(record, retentionDays: 30)
        let records = await store.modify(record.id) { $0.text = "стало"; $0.previous = .init(text: "было", raw: "было") }
        #expect(records[0].text == "стало")
        #expect(records[0].previous?.text == "было")
    }

    @Test func statsSkipRecordingsWithoutText() {
        let now = Date()
        let records = [
            DictationRecord(text: "раз два", raw: "", appName: nil, bundleID: nil, duration: 1, date: now),
            DictationRecord(text: "", raw: "", appName: nil, bundleID: nil, duration: 30, date: now, audio: "x.caf", failure: .interrupted),
        ]
        let stats = HistoryStats(records: records, now: now)
        #expect(stats.wordsToday == 2)
        #expect(stats.wordsPerMinute == 120)
    }
}

@Suite struct AudioSettingsTests {
    @Test func olderSettingsKeepADayAndTwenty() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{\"historyRetentionDays\":7}".utf8))
        #expect(settings.audioRetention == .day)
        #expect(settings.audioLimit == 20)
        #expect(settings.historyRetentionDays == 7)
    }

    @Test func unknownRetentionFallsBackToTheDefault() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{\"audioRetention\":\"month\"}".utf8))
        #expect(settings.audioRetention == .day)
    }

    @Test func retentionRoundTrips() throws {
        var settings = AppSettings()
        settings.audioRetention = .off
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.audioRetention == .off)
    }
}
