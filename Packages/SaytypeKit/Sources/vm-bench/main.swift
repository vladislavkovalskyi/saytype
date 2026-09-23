import Foundation
import VMAudio
import VMCore
import VMTranscription
import WhisperKit

// Command-line harness for measuring recognition on recorded phrases.
//
//   vm-bench download [variant]
//   vm-bench transcribe <audio>... [--variant v] [--language ru|auto] [--prompt] [--live] [--translate]
//   vm-bench lab <audio>... [lab options, see `Lab`]
//
// --prompt adds a developer glossary; --live replays the file in
// one-second steps through LiveAgreement, the way the app does while fn is held;
// --translate asks Whisper for English text.

let arguments = Array(CommandLine.arguments.dropFirst())
let defaultVariant = AppSettings().whisperModel

func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

func seconds(_ start: ContinuousClock.Instant) -> Double {
    let d = ContinuousClock.now - start
    return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}

let store = ModelStore()

switch arguments.first {
case "download":
    let variant = arguments.dropFirst().first ?? defaultVariant
    print("downloading \(variant) into \(store.base.path)")
    let folder = try await store.download(variant) { fraction in
        FileHandle.standardError.write(Data(String(format: "\r%5.1f%%", fraction * 100).utf8))
    }
    print("\nready: \(folder.path)")

case "transcribe":
    let variant = option("--variant") ?? defaultVariant
    let files = arguments.dropFirst().filter { !$0.hasPrefix("--") && $0 != option("--variant") && $0 != option("--language") }
    let language = option("--language").map { $0 == "auto" ? nil : $0 } ?? "ru"
    let engine = WhisperKitEngine(store: store, variant: variant)
    let loadStart = ContinuousClock.now
    try await engine.prepare()
    print("model \(variant) loaded in \(String(format: "%.1f", seconds(loadStart))) s\n")
    let glossary = ["useEffect", "useState", "Header", "Vercel", "Supabase", "Next.js", "TypeScript", "Prisma", "Zod", "GitHub Actions", "React Query", "Docker Compose", "Postgres", "Redis", "SwiftUI", "Telegram"]
    let hints = TranscriptionHints(language: language, glossary: arguments.contains("--prompt") ? glossary : [], translate: arguments.contains("--translate"))
    for file in files {
        let samples = try AudioFileLoader.load(URL(fileURLWithPath: file))
        let duration = Double(samples.count) / AudioCapture.sampleRate
        if arguments.contains("--live") {
            var live = LiveAgreement()
            var cursor = 16_000
            while cursor < samples.count {
                let stepStart = ContinuousClock.now
                let partial = try await engine.transcribe(Array(samples[..<cursor]), hints: hints)
                live.update(with: partial.text)
                print(String(format: "  %4.1f s  (%.2f s)  %@ | %@", Double(cursor) / 16_000, seconds(stepStart), live.committedText, live.pendingText))
                cursor += 16_000
            }
        }
        let start = ContinuousClock.now
        let transcript = try await engine.transcribe(samples, hints: hints)
        let elapsed = seconds(start)
        print(String(format: "%@  %.1f s audio, %.2f s decode, RTF %.3f", (file as NSString).lastPathComponent, duration, elapsed, elapsed / duration))
        if arguments.contains("--timings"), let t = await engine.lastTimings {
            print(String(format: "  encode %.2f · decode %.2f · pipeline %.2f", t.encoding, t.decodingLoop, t.total))
        }
        print("  \(transcript.text)\n")
    }

case "lab":
    try await Lab.run(arguments: Array(arguments.dropFirst()))

case "context":
    try await ScreenBench.run(arguments: Array(arguments.dropFirst()))

default:
    print("usage: vm-bench download [variant] | vm-bench transcribe <audio>... [--variant v] [--language ru|auto] [--prompt] [--live] [--translate] | vm-bench lab <audio>... [options] | vm-bench context text|speech …")
}

/// Experiments on WhisperKit's decoding options, outside the app's engine.
///
///   vm-bench lab <audio>... [--variant v] [--language ru|auto]
///       [--owner-prompt settings.json | --bench-prompt] [--engine [--gate]] [--no-words]
///       [--pad-tail s] [--clip-time s] [--max-initial s] [--no-vad]
///       [--chunk] [--pause s] [--max-chunk s] [--refs refs.json --sentences sentences.txt]
///       [--runs n] [--segments] [--workers n] [--prompt-tokens n] [--no-first-token-check] [--log] [--reentrancy]
///
/// Without options it decodes the way the app's final pass did up to 0.3.0 (the prompt aside):
/// word timings on, no tail padding, WhisperKit's VAD chunks above 30 s. `--chunk` splits the
/// recording at pauses and decodes each piece on its own; `--refs` with `--sentences` marks each
/// reference sentence found (+) or missing (·). `--engine` runs the app's current
/// `WhisperKitEngine` instead, with the owner's glossary as hints; `--gate` puts `VoiceGate` in
/// front of it the way the controller does.
enum Lab {
    struct Config {
        var language: String?
        var prompt: String?
        var wordTimestamps = true
        var padTail = 0.0
        var clipTime: Float = 1.0
        var maxInitial: Float?
        var vad = true
        var chunk = false
        var pause = 0.5
        var maxChunk = 20.0
        var showSegments = false
        /// WhisperKit decodes VAD chunks concurrently, 16 at a time on macOS by default.
        var workers: Int?
        /// Keeps only the first n prompt tokens; WhisperKit itself keeps the last 111.
        var promptTokenCap: Int?
        var glossary: [String] = []
        /// WhisperKit re-decodes at a higher temperature when the first token is unlikely.
        var firstTokenCheck = true
    }

    struct Outcome {
        var text: String
        var outputTokens: Int
        var windows: Int
        var fallbacks: Int
        var seconds: Double
    }

    static func run(arguments: [String]) async throws {
        func option(_ name: String) -> String? {
            guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        let valued = ["--variant", "--language", "--owner-prompt", "--pad-tail", "--clip-time", "--max-initial", "--pause", "--max-chunk", "--refs", "--sentences", "--runs", "--workers", "--prompt-tokens"]
        let values = Set(valued.compactMap(option))
        let files = arguments.filter { !$0.hasPrefix("--") && !values.contains($0) }

        let variant = option("--variant") ?? "large-v3-v20240930_turbo_632MB"
        var config = Config()
        config.language = option("--language").map { $0 == "auto" ? nil : $0 } ?? nil
        config.glossary = try option("--owner-prompt").map(ownerGlossary) ?? (arguments.contains("--bench-prompt") ? PromptBuilder.builtInTerms : [])
        config.prompt = legacyPrompt(config.glossary)
        config.wordTimestamps = !arguments.contains("--no-words")
        config.padTail = option("--pad-tail").flatMap(Double.init) ?? 0
        config.clipTime = option("--clip-time").flatMap(Float.init) ?? 1.0
        config.maxInitial = option("--max-initial").flatMap(Float.init)
        config.vad = !arguments.contains("--no-vad")
        config.chunk = arguments.contains("--chunk")
        config.pause = option("--pause").flatMap(Double.init) ?? 0.5
        config.maxChunk = option("--max-chunk").flatMap(Double.init) ?? 20
        config.showSegments = arguments.contains("--segments")
        config.workers = option("--workers").flatMap(Int.init)
        config.promptTokenCap = option("--prompt-tokens").flatMap(Int.init)
        config.firstTokenCheck = !arguments.contains("--no-first-token-check")
        let runs = option("--runs").flatMap(Int.init) ?? 1
        let references = try loadReferences(refs: option("--refs"), sentences: option("--sentences"))

        let store = ModelStore()
        let start = ContinuousClock.now
        let pipe = try await WhisperKit(WhisperKitConfig(
            modelFolder: store.folder(for: variant).path, tokenizerFolder: store.base,
            verbose: arguments.contains("--log"), logLevel: arguments.contains("--log") ? .info : .error, prewarm: true, load: true, download: false
        ))
        print("model \(variant) loaded in \(format(ContinuousClock.now - start)) s")
        if arguments.contains("--log") {
            // WhisperKit's fallbacks and chunk boundaries, to standard output instead of os_log.
            Logging.shared.loggingCallback = { message in
                if message.contains("Fallback") || message.contains("Found chunk") || message.contains("Decoding Temperature") { print("    · " + message) }
            }
        }
        if let prompt = config.prompt, let tokenizer = pipe.tokenizer {
            let tokens = promptTokens(prompt, tokenizer: tokenizer)
            let kept = min(tokens.count, Constants.maxTokenContext / 2 - 1)
            // [startofprev] + prompt + [sot, language, task, timestamp begin]
            let initialPromptIndex = 1 + kept + 4
            print("prompt: \(prompt.count) chars, \(tokens.count) tokens, \(kept) kept; output budget per window \(Constants.maxTokenContext - 1 - initialPromptIndex) tokens")
        } else {
            print("prompt: none; output budget per window \(Constants.maxTokenContext - 1 - 4) tokens")
        }
        if let tokenizer = pipe.tokenizer, let current = PromptBuilder.prompt(glossary: config.glossary, countTokens: { promptTokens($0, tokenizer: tokenizer).count }) {
            let kept = current.dropLast().components(separatedBy: ", ")
            let positions = kept.compactMap { term in config.glossary.firstIndex(of: term).map { String($0 + 1) } }
            print("engine prompt: \(kept.count) of \(config.glossary.count) terms (positions \(positions.joined(separator: " "))), \(promptTokens(current, tokenizer: tokenizer).count) tokens")
        }

        if arguments.contains("--reentrancy") {
            try await reentrancy(files: files, variant: variant, config: config)
            return
        }
        if arguments.contains("--engine") {
            try await engine(files: files, variant: variant, config: config, gate: arguments.contains("--gate"), runs: runs, references: references)
            return
        }

        for file in files {
            let samples = try AudioFileLoader.load(URL(fileURLWithPath: file))
            let name = (file as NSString).lastPathComponent
            for _ in 0..<runs {
                let outcome = try await transcribe(samples, pipe: pipe, config: config)
                var line = String(format: "%@  %.1f s  decode %.2f s  windows %d  tokens %d  fallbacks %d", name, Double(samples.count) / 16_000, outcome.seconds, outcome.windows, outcome.outputTokens, outcome.fallbacks)
                if let reference = references[name] {
                    line += "  " + coverage(outcome.text, sentences: reference)
                }
                print(line)
                print("  " + (outcome.text.isEmpty ? "∅" : outcome.text))
            }
        }
    }

    // MARK: Decoding

    static func transcribe(_ samples: [Float], pipe: WhisperKit, config: Config) async throws -> Outcome {
        let start = ContinuousClock.now
        let pieces = config.chunk ? split(samples, pause: config.pause, maxChunk: config.maxChunk) : [samples]
        var texts: [String] = []
        var tokens = 0
        var windows = 0
        var fallbacks = 0
        for piece in pieces {
            let padded = piece + [Float](repeating: 0, count: Int(config.padTail * 16_000))
            var options = DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: config.language,
                temperature: 0,
                usePrefillPrompt: true,
                detectLanguage: config.language == nil,
                skipSpecialTokens: true,
                withoutTimestamps: false,
                wordTimestamps: config.wordTimestamps,
                maxInitialTimestamp: config.maxInitial,
                windowClipTime: config.clipTime,
                firstTokenLogProbThreshold: config.firstTokenCheck ? -1.5 : nil,
                concurrentWorkerCount: config.workers,
                chunkingStrategy: config.vad && padded.count > 30 * 16_000 ? .vad : ChunkingStrategy.none
            )
            if let prompt = config.prompt, let tokenizer = pipe.tokenizer {
                let tokens = promptTokens(prompt, tokenizer: tokenizer)
                options.promptTokens = config.promptTokenCap.map { Array(tokens.prefix($0)) } ?? tokens
            }
            let results = try await pipe.transcribe(audioArray: padded, decodeOptions: options)
            let segments = results.flatMap(\.segments)
            if config.showSegments {
                for segment in segments {
                    print(String(format: "    [%6.2f → %6.2f] seek %7d  %@", segment.start, segment.end, segment.seek, segment.text))
                }
            }
            tokens += segments.reduce(0) { $0 + $1.tokens.count }
            windows += results.reduce(0) { $0 + Int($1.timings.totalDecodingWindows) }
            fallbacks += results.reduce(0) { $0 + Int($1.timings.totalDecodingFallbacks) }
            texts.append(segments.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " "))
        }
        let text = HallucinationFilter.clean(texts.joined(separator: " "))
        return Outcome(text: text, outputTokens: tokens, windows: windows, fallbacks: fallbacks, seconds: seconds(ContinuousClock.now - start))
    }

    static func promptTokens(_ prompt: String, tokenizer: any WhisperTokenizer) -> [Int] {
        tokenizer.encode(text: " " + prompt.trimmingCharacters(in: .whitespaces))
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
    }

    /// Splits at pauses: 30 ms frames, a pause is `pause` seconds below the adaptive voice
    /// threshold, and each piece ends at the latest pause that keeps it under `maxChunk`.
    static func split(_ samples: [Float], pause: Double, maxChunk: Double) -> [[Float]] {
        let frame = 480
        let count = samples.count / frame
        guard count > 0 else { return [samples] }
        var db = [Float](repeating: -100, count: count)
        for i in 0..<count {
            var sum: Float = 0
            for s in samples[(i * frame)..<((i + 1) * frame)] { sum += s * s }
            db[i] = 10 * log10(max(sum / Float(frame), 1e-10))
        }
        let floor = db.sorted()[count / 10]
        let threshold = max(floor + 12, -50)
        // Midpoints of pauses long enough to cut at, in samples.
        var cuts: [Int] = []
        var run = 0
        let minFrames = Int(pause / 0.03)
        for i in 0...count {
            if i < count, db[i] < threshold {
                run += 1
            } else {
                if run >= minFrames { cuts.append((i - run / 2) * frame) }
                run = 0
            }
        }
        var pieces: [[Float]] = []
        var start = 0
        let limit = Int(maxChunk * 16_000)
        while samples.count - start > limit {
            let end = cuts.last { $0 > start + 16_000 && $0 <= start + limit } ?? (start + limit)
            pieces.append(Array(samples[start..<end]))
            start = end
        }
        pieces.append(Array(samples[start...]))
        return pieces
    }

    // MARK: The app's engine

    /// The final pass as the app runs it now: the voice gate, then `WhisperKitEngine`.
    static func engine(files: [String], variant: String, config: Config, gate: Bool, runs: Int, references: [String: [String]]) async throws {
        let engine = WhisperKitEngine(variant: variant)
        try await engine.prepare()
        let hints = TranscriptionHints(language: config.language, glossary: config.glossary)
        for file in files {
            let samples = try AudioFileLoader.load(URL(fileURLWithPath: file))
            let name = (file as NSString).lastPathComponent
            for _ in 0..<runs {
                let start = ContinuousClock.now
                var text = "∅ (gated)"
                if !gate || VoiceGate.hasVoice(samples) {
                    let transcript = try await engine.transcribe(samples, hints: hints)
                    text = transcript.text.isEmpty ? "∅" : transcript.text
                    if config.showSegments {
                        for segment in transcript.segments {
                            print(String(format: "    [%6.2f → %6.2f]  %@", segment.start, segment.end, segment.text))
                        }
                    }
                }
                var line = String(format: "%@  %.1f s  decode %.2f s", name, Double(samples.count) / 16_000, seconds(ContinuousClock.now - start))
                if let reference = references[name] {
                    line += "  " + coverage(text, sentences: reference)
                }
                print(line)
                print("  " + text)
            }
        }
    }

    // MARK: Reentrancy

    /// A live pass cancelled after 200 ms while the final pass starts on the same engine actor.
    static func reentrancy(files: [String], variant: String, config: Config) async throws {
        let engine = WhisperKitEngine(variant: variant)
        try await engine.prepare()
        for file in files {
            let samples = try AudioFileLoader.load(URL(fileURLWithPath: file))
            let hints = TranscriptionHints(language: config.language, glossary: config.glossary)
            let clean = try await engine.transcribe(samples, hints: hints).text
            var same = 0
            let trials = 3
            for _ in 0..<trials {
                let live = Task { try? await engine.transcribe(Array(samples.prefix(29 * 16_000)), hints: TranscriptionHints(language: config.language)) }
                try await Task.sleep(for: .milliseconds(200))
                live.cancel()
                let final = try await engine.transcribe(samples, hints: hints).text
                if final == clean { same += 1 } else { print("  differs: \(final)") }
            }
            print("\((file as NSString).lastPathComponent): \(same)/\(trials) final passes equal the clean run")
        }
    }

    // MARK: Scoring

    /// The owner's dictionary, then the built-in terms, in the app's priority order.
    static func ownerGlossary(_ path: String) throws -> [String] {
        struct Settings: Decodable { let dictionary: [DictionaryEntry] }
        let settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        return DictionaryRewriter.promptTerms(entries: settings.dictionary, projectTerms: [])
    }

    /// The prompt as the app built it up to 0.3.0: terms up to 240 characters or 224 estimated
    /// tokens, whichever came first, without the tokenizer.
    static func legacyPrompt(_ glossary: [String]) -> String? {
        var list = ""
        for term in glossary {
            let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            let next = list.isEmpty ? term : list + ", " + term
            if next.count + 1 > 240 || PromptBuilder.estimatedTokens(next + ".") > 224 { break }
            list = next
        }
        return list.isEmpty ? nil : list + "."
    }

    static func loadReferences(refs: String?, sentences: String?) throws -> [String: [String]] {
        guard let refs, let sentences else { return [:] }
        let lines = try String(contentsOfFile: sentences, encoding: .utf8).split(separator: "\n").map(String.init)
        let map = try JSONDecoder().decode([String: [Int]].self, from: Data(contentsOf: URL(fileURLWithPath: refs)))
        return map.mapValues { $0.map { lines[$0] } }
    }

    /// One mark per reference sentence: + when most of its words are in the text, · otherwise.
    static func coverage(_ text: String, sentences: [String]) -> String {
        func stems(_ s: String) -> [String] {
            s.lowercased().replacingOccurrences(of: "ё", with: "е")
                .components(separatedBy: CharacterSet.letters.inverted)
                .filter { $0.count >= 3 }
                .map { String($0.prefix(5)) }
        }
        var pool = stems(text)
        var marks = ""
        var found = 0
        for sentence in sentences {
            let words = stems(sentence)
            var hit = 0
            for w in words {
                if let i = pool.firstIndex(of: w) { pool.remove(at: i); hit += 1 }
            }
            let ok = Double(hit) / Double(max(words.count, 1)) >= 0.6
            marks += ok ? "+" : "·"
            if ok { found += 1 }
        }
        return "[\(marks)] \(found)/\(sentences.count)"
    }

    static func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    static func format(_ d: Duration) -> String { String(format: "%.1f", seconds(d)) }
}
