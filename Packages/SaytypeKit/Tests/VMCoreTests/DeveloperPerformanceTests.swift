import Foundation
import Testing
@testable import VMCore

/// Timings of the per-dictation work. Printed so a release run (`swift test -c release
/// -Xswiftc -enable-testing --filter Performance`) gives real numbers; the bounds are loose
/// enough for debug builds.
@Suite struct DeveloperPerformanceTests {
    /// About 200 words of dictation to a coding agent.
    static let dictation = Array(repeating: """
    Поправь кэмел кейс юзер дата в src слэш components слэш хедер точка tsx, потом проверь что x не равно null \
    и вызови useEffect после fetchUserProfile. Ещё обнови package.json, добавь OPENAI_API_KEY в точка env и \
    запусти тесты на localhost:3000. Если count больше или равно 10, покажи три точки props в UserProfileCard, \
    а ошибку положи в снейк кейс эррор месседж. Проверь React, Supabase и GitHub Actions, там всё должно работать.
    """, count: 3).joined(separator: " ")

    static func median(_ runs: Int = 60, _ body: () -> Void) -> Double {
        var times: [Double] = []
        for _ in 0..<runs {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        return times.sorted()[times.count / 2]
    }

    static let projectTerms: [String] = (0..<400).map { "project\(["User", "Order", "Cart", "Profile"][$0 % 4])Item\($0)Handler" }

    @Test func formatterAndBackticksStayFast() {
        let words = Words.split(Self.dictation).count
        _ = DeveloperFormatter.apply(Self.dictation)
        _ = Backticks.wrap(Self.dictation, terms: Self.projectTerms)
        let developer = Self.median { _ = DeveloperFormatter.apply(Self.dictation) }
        let formatted = DeveloperFormatter.apply(Self.dictation)
        let backticks = Self.median { _ = Backticks.wrap(formatted, terms: Self.projectTerms) }
        let plain = Self.median { _ = DeveloperFormatter.apply("Сборка упала, посмотри логи и перезапусти деплой. " + String(repeating: "Всё остальное в порядке. ", count: 40)) }
        print(String(format: "perf %d words: DeveloperFormatter %.3f ms, Backticks %.3f ms, no spoken code %.3f ms", words, developer, backticks, plain))
        #expect(developer + backticks < 20)
    }

    @Test func rewriterIsBuiltOncePerSettings() {
        let entries = DictionaryEntry.starter
        _ = BuiltInDictionary.canonicalTerms
        let build = Self.median(20) { _ = DictionaryRewriter(entries: entries, builtIn: true, projectTerms: Self.projectTerms) }
        let buildWithoutProjects = Self.median(20) { _ = DictionaryRewriter(entries: entries, builtIn: true) }
        _ = DictionaryRewriter.cached(entries: entries, builtIn: true, projectTerms: Self.projectTerms)
        let cached = Self.median { _ = DictionaryRewriter.cached(entries: entries, builtIn: true, projectTerms: Self.projectTerms) }
        var settings = AppSettings()
        settings.dictionary = entries
        let transcript = Transcript(text: Self.dictation)
        let mode = settings.modes.first { $0.id == DictationMode.promptID }!
        _ = DictationPipeline.format(transcript, settings: settings, mode: mode, projectTerms: Self.projectTerms)
        let pipeline = Self.median(20) { _ = DictationPipeline.format(transcript, settings: settings, mode: mode, projectTerms: Self.projectTerms) }
        print(String(format: "perf rewriter build %.3f ms (%.3f ms without project terms), cached lookup %.4f ms, whole pipeline %.3f ms",
                     build, buildWithoutProjects, cached, pipeline))
        #expect(cached < build)
    }
}
