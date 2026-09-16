import Foundation
import Testing
@testable import VMCore

@Suite struct TimeSavedTests {
    func record(_ words: Int, duration: Double, date: Date) -> DictationRecord {
        DictationRecord(text: Array(repeating: "слово", count: words).joined(separator: " "), raw: "", appName: nil, bundleID: nil, duration: duration, date: date)
    }

    @Test func typingTimeMinusSpeakingTime() {
        // 40 words at 40 wpm take a minute to type; saying them took 15 s.
        #expect(HistoryStats.secondsSaved(words: 40, duration: 15, typingWordsPerMinute: 40) == 45)
        #expect(HistoryStats.secondsSaved(words: 80, duration: 20, typingWordsPerMinute: 60) == 60)
        // A slow dictation saves nothing rather than costing time.
        #expect(HistoryStats.secondsSaved(words: 2, duration: 10, typingWordsPerMinute: 40) == 0)
        #expect(HistoryStats.secondsSaved(words: 10, duration: 1, typingWordsPerMinute: 0) == 0)
    }

    @Test func todayAndThisWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 15))!
        let records = [
            record(40, duration: 15, date: now.addingTimeInterval(-600)),
            record(20, duration: 40, date: now.addingTimeInterval(-3_600)),
            record(80, duration: 30, date: now.addingTimeInterval(-3 * 86_400)),
            record(400, duration: 60, date: now.addingTimeInterval(-10 * 86_400)),
        ]
        let stats = HistoryStats(records: records, typingWordsPerMinute: 40, now: now, calendar: calendar)
        #expect(stats.secondsSavedToday == 45)
        #expect(stats.secondsSavedThisWeek == 45 + 90)
        #expect(stats.wordsToday == 60)
        #expect(stats.wordsThisWeek == 140)
        #expect(stats.wordsPerMinute == 65)

        let faster = HistoryStats(records: records, typingWordsPerMinute: 80, now: now, calendar: calendar)
        #expect(faster.secondsSavedToday == 15)
    }

    @Test func noRecordsSaveNothing() {
        let stats = HistoryStats(records: [])
        #expect(stats.secondsSavedToday == 0)
        #expect(stats.secondsSavedThisWeek == 0)
    }
}

@Suite struct HistoryCorrectionTests {
    let raw = "эээ поправь юз эффект в хедер и задеплой на версель"
    let text = "Поправь useEffect в Header и задеплой на Vercel."

    @Test func replacedWordsMapBackToWhatWasHeard() {
        #expect(HistoryCorrection.heard(raw: raw, text: text, words: 1...1) == "юз эффект")
        #expect(HistoryCorrection.heard(raw: raw, text: text, words: 3...3) == "хедер")
        #expect(HistoryCorrection.heard(raw: raw, text: text, words: 7...7) == "версель")
        #expect(HistoryCorrection.heard(raw: raw, text: text, words: 0...1) == "поправь юз эффект")
    }

    @Test func unchangedWordsAreHeardAsWritten() {
        #expect(HistoryCorrection.heard(raw: raw, text: text, words: 4...5) == "и задеплой")
    }

    @Test func fillersAtTheEdgesAreLeftOut() {
        #expect(HistoryCorrection.heard(raw: "ну юз эффект сломался", text: "useEffect сломался.", words: 0...0) == "юз эффект")
    }

    @Test func unclearAlignmentFallsBackToThePickedWords() {
        // A rewrite shares no words with what was said.
        let rewritten = HistoryCorrection.heard(raw: "сделай так чтобы кнопка не прыгала", text: "Fix the button layout shift.", words: 1...2)
        #expect(rewritten == "the button")
        // Part of a replaced run is a guess, so the picked word itself is used.
        #expect(HistoryCorrection.heard(raw: "юз эффект хук", text: "useEffect-hook готов", words: 0...0) == "useeffect-hook")
        #expect(HistoryCorrection.heard(raw: raw, text: text, words: 10...12) == "")
    }

    @Test func entryKeepsOnlyTheSpellingWhenCaseDiffers() {
        #expect(HistoryCorrection.entry(heard: "github", written: " GitHub ")?.heard == "")
        let entry = HistoryCorrection.entry(heard: "хедер", written: "Header")
        #expect(entry?.heard == "хедер")
        #expect(entry?.written == "Header")
        #expect(entry?.source == .history)
        #expect(HistoryCorrection.entry(heard: "хедер", written: "  ") == nil)
    }

    @Test func addingUpdatesTheSameHeardWords() throws {
        var dictionary = [DictionaryEntry(heard: "версель", written: "Vercel")]
        #expect(dictionary.addCorrection(try #require(HistoryCorrection.entry(heard: "хедер", written: "Header"))))
        #expect(dictionary.map(\.written) == ["Header", "Vercel"])
        #expect(dictionary.addCorrection(try #require(HistoryCorrection.entry(heard: "Хедер", written: "header.tsx"))))
        #expect(dictionary.map(\.written) == ["header.tsx", "Vercel"])
        #expect(!dictionary.addCorrection(try #require(HistoryCorrection.entry(heard: "версель", written: "Vercel"))))
        #expect(dictionary.count == 2)
    }
}
