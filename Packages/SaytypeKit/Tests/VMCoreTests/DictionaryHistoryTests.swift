import Foundation
import Testing
@testable import VMCore

@Suite struct DictionaryRewriterTests {
    let rewriter = DictionaryRewriter(entries: [
        DictionaryEntry(heard: "юз эффект", written: "useEffect"),
        DictionaryEntry(heard: "версель", written: "Vercel"),
    ], builtInTerms: ["Docker Compose"])

    @Test func replacesHeardPhrasesAndCanonicalSpellings() {
        #expect(rewriter.apply(to: "Поправь юз эффект и задеплой на версель.") == "Поправь useEffect и задеплой на Vercel.")
        #expect(rewriter.apply(to: "подними Docker compose") == "подними Docker Compose")
    }

    @Test func doesNotReplaceInsideOtherWords() {
        #expect(rewriter.apply(to: "верселька") == "верселька")
    }

    @Test func promptTermsPutUserEntriesFirstWithoutDuplicates() {
        let terms = DictionaryRewriter.promptTerms(entries: [DictionaryEntry(heard: "", written: "Next.js")], builtInTerms: ["React", "next.js"])
        #expect(terms == ["Next.js", "React"])
    }
}

@Suite struct HistoryTests {
    func tempStore() -> HistoryStore {
        HistoryStore(url: FileManager.default.temporaryDirectory.appending(path: "saytype-history-\(UUID().uuidString).json"))
    }

    @Test func persistsNewestFirstAndPrunesOldRecords() async {
        let store = tempStore()
        let now = Date()
        _ = await store.add(DictationRecord(text: "старая", raw: "", appName: nil, bundleID: nil, duration: 1, date: now.addingTimeInterval(-40 * 86_400)), retentionDays: 0, now: now)
        let records = await store.add(DictationRecord(text: "новая", raw: "", appName: "Терминал", bundleID: nil, duration: 1, date: now), retentionDays: 30, now: now)
        #expect(records.map(\.text) == ["новая"])
    }

    @Test func statsCountTodayWordsAndPace() {
        let now = Date()
        let records = [
            DictationRecord(text: "раз два три четыре", raw: "", appName: nil, bundleID: nil, duration: 2, date: now),
            DictationRecord(text: "пять шесть", raw: "", appName: nil, bundleID: nil, duration: 1, date: now),
            DictationRecord(text: "вчера было", raw: "", appName: nil, bundleID: nil, duration: 1, date: now.addingTimeInterval(-86_400 * 2)),
        ]
        let stats = HistoryStats(records: records, now: now)
        #expect(stats.wordsToday == 6)
        #expect(stats.wordsThisWeek == 8)
        #expect(stats.wordsPerMinute == 120)
    }
}
