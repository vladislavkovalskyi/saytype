import Foundation
import VMAudio
import VMCore
import VMTranscription

/// Screen context: how often a term on the screen comes out spelled as on the screen, and how
/// often ordinary speech is rewritten into one.
///
///   vm-bench context text <file>... --terms-from <folder>
///       Every sentence of the files through the screen matcher, with the code folder's
///       identifiers (up to 400) standing in for the screen. Prints each sentence it changed.
///
///   vm-bench context speech <corpus.tsv> [--language ru|auto] [--owner-prompt settings.json]
///       [--prompt-share n] [--runs n]
///       Each line of the corpus: audio file, screen text file, expected terms separated by
///       commas; paths relative to the corpus. Every file is decoded with the app's engine twice:
///       with the owner's prompt, and with the top n screen terms (default 3) put in front of it.
///       Each decode is formatted with and without the screen matcher.
enum ScreenBench {
    static func run(arguments: [String]) async throws {
        func option(_ name: String) -> String? {
            guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        let valued = ["--terms-from", "--language", "--owner-prompt", "--prompt-share", "--runs", "--variant"]
        let values = Set(valued.compactMap(option))
        let files = arguments.dropFirst().filter { !$0.hasPrefix("--") && !values.contains($0) }
        switch arguments.first {
        case "text":
            guard let folder = option("--terms-from") else {
                print("context text needs --terms-from <folder>")
                return
            }
            text(files: files, folder: folder)
        case "speech":
            guard let corpus = files.first else {
                print("context speech needs a corpus file")
                return
            }
            try await speech(
                corpus: corpus,
                language: option("--language").map { $0 == "auto" ? nil : $0 } ?? nil,
                ownerSettings: option("--owner-prompt"),
                share: option("--prompt-share").flatMap(Int.init) ?? 3,
                runs: option("--runs").flatMap(Int.init) ?? 1,
                variant: option("--variant") ?? AppSettings().whisperModel
            )
        default:
            print("usage: vm-bench context text <file>... --terms-from <folder> | vm-bench context speech <corpus.tsv> [options]")
        }
    }

    // MARK: False positives

    static func text(files: [String], folder: String) {
        let scan = ProjectScanner.scan(URL(fileURLWithPath: folder))
        let matcher = ScreenTermMatcher(terms: scan.terms)
        var sentences = 0
        var changed = 0
        let start = ContinuousClock.now
        for file in files {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            for sentence in Self.sentences(content) {
                sentences += 1
                let fixed = matcher.apply(to: sentence)
                guard fixed != sentence else { continue }
                changed += 1
                print("- " + sentence)
                print("+ " + fixed)
            }
        }
        let elapsed = ContinuousClock.now - start
        print("\(scan.terms.count) terms, \(sentences) sentences, \(changed) changed, \(elapsed.formatted(.units(allowed: [.milliseconds])))")
    }

    /// Prose lines of a text or Markdown file, cut at sentence ends. Code blocks, tables and
    /// headings are left out; inline code keeps its text.
    static func sentences(_ content: String) -> [String] {
        var result: [String] = []
        var inFence = false
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            guard !inFence, !trimmed.hasPrefix("|"), !trimmed.hasPrefix("#"), !trimmed.hasPrefix("<"), trimmed != "---" else { continue }
            let prose = trimmed.replacingOccurrences(of: "`", with: "").replacingOccurrences(of: "**", with: "")
            var current = ""
            for character in prose {
                current.append(character)
                if ".!?".contains(character) {
                    let sentence = current.trimmingCharacters(in: .whitespaces)
                    if sentence.count > 3 { result.append(sentence) }
                    current = ""
                }
            }
            let rest = current.trimmingCharacters(in: .whitespaces)
            if rest.count > 3 { result.append(rest) }
        }
        return result
    }

    // MARK: Speech

    struct Item {
        let audio: String
        let screen: String
        let expected: [String]
    }

    static func speech(corpus: String, language: String?, ownerSettings: String?, share: Int, runs: Int, variant: String) async throws {
        let base = URL(fileURLWithPath: corpus).deletingLastPathComponent()
        let items: [Item] = try String(contentsOfFile: corpus, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { line in
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard columns.count >= 2, !line.hasPrefix("#") else { return nil }
                let expected = columns.count > 2 ? columns[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } : []
                return Item(audio: base.appending(path: columns[0]).path, screen: base.appending(path: columns[1]).path, expected: expected)
            }
        var settings = AppSettings()
        settings.language = language.map { AppSettings.SpeechLanguage(rawValue: $0) } ?? .auto
        if let ownerSettings {
            struct Owner: Decodable { let dictionary: [DictionaryEntry] }
            settings.dictionary = try JSONDecoder().decode(Owner.self, from: Data(contentsOf: URL(fileURLWithPath: ownerSettings))).dictionary
        }
        let ownerGlossary = DictionaryRewriter.promptTerms(entries: settings.dictionary)
        let engine = WhisperKitEngine(variant: variant)
        try await engine.prepare()
        let mode = DictationMode(id: DictationMode.standardID)

        struct Tally {
            var found = 0
            var total = 0
            var changedWithout = 0
            var seconds = 0.0
        }
        var tallies: [String: Tally] = [:]
        let variants = ["owner prompt", "owner prompt + matcher", "screen share", "screen share + matcher"]
        for item in items {
            let screenText = (try? String(contentsOfFile: item.screen, encoding: .utf8)) ?? ""
            let terms = ScreenTerms.extract(from: ScreenText(focused: screenText))
            let matcher = ScreenTermMatcher(terms: terms)
            let samples = try AudioFileLoader.load(URL(fileURLWithPath: item.audio))
            let name = (item.audio as NSString).lastPathComponent
            print("\(name)  expected: \(item.expected.isEmpty ? "none" : item.expected.joined(separator: ", "))")
            for (index, glossary) in [ownerGlossary, Array(terms.prefix(share)) + ownerGlossary].enumerated() {
                let hints = TranscriptionHints(language: settings.language.whisperCode, glossary: glossary)
                for _ in 0..<runs {
                    let start = ContinuousClock.now
                    let transcript = try await engine.transcribe(samples, hints: hints)
                    let elapsed = ContinuousClock.now - start
                    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    for withMatcher in [false, true] {
                        let label = variants[index * 2 + (withMatcher ? 1 : 0)]
                        let text = DictationPipeline.format(transcript, settings: settings, mode: mode, screen: withMatcher ? matcher : nil).text
                        let hits = item.expected.filter { text.contains($0) }.count
                        var tally = tallies[label, default: Tally()]
                        tally.found += hits
                        tally.total += item.expected.count
                        tally.seconds += seconds
                        if item.expected.isEmpty, withMatcher, text != DictationPipeline.format(transcript, settings: settings, mode: mode).text {
                            tally.changedWithout += 1
                        }
                        tallies[label] = tally
                        print(String(format: "  %-24@ %d/%d  %.2f s  %@", label as NSString, hits, item.expected.count, seconds, text))
                    }
                }
            }
        }
        print("")
        for label in variants {
            guard let tally = tallies[label] else { continue }
            print(String(format: "%-24@ %d/%d terms, %d ordinary dictations changed, decode %.2f s in all", label as NSString, tally.found, tally.total, tally.changedWithout, tally.seconds / 2))
        }
    }
}
