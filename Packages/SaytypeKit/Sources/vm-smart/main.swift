import Foundation
import VMCore
import VMSmart

// vm-smart download [repo]
// vm-smart structure <file with texts separated by "---" lines>
// vm-smart rewrite <file> [--repo repo] [--styles prompt,commit,cleaner,translate] [--out file]
//                         [--no-cache] [--ollama model | --lmstudio model] [--url url] [--to code]
//
// A style of the form "selection:<instruction>" runs the Edit selection shortcut's prompt over
// each text; --to names the language a translation goes into, English by default.
//
// rewrite runs every text through every style, validates each answer and prints load, warm-up,
// time to first token, tokens per second and peak memory. Bench/rewrite-corpus.txt is the corpus.

let arguments = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

func samples(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .utf8)
        .components(separatedBy: "\n---\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func now() -> Double { Date.timeIntervalSinceReferenceDate }

switch arguments.first {
case "download":
    let store = SmartModelStore(repo: arguments.dropFirst().first ?? SmartModelStore.defaultRepo)
    try await store.download { value in
        FileHandle.standardError.write(String(format: "\r%.0f%%", value * 100).data(using: .utf8)!)
    }
    print("\n\(store.folder.path)")

case "structure":
    guard arguments.count > 1 else { fatalError("usage: vm-smart structure <file>") }
    let structurer = SmartStructurer(store: SmartModelStore())
    let loadStart = Date()
    try await structurer.load()
    _ = try await structurer.labels(for: ["Прогрев.", "Готово."])
    print(String(format: "load + warmup %.2fs\n", Date().timeIntervalSince(loadStart)))
    for sample in try samples(arguments[1]) {
        let start = Date()
        let sentences = SmartStructure.sentences(sample)
        let labels = try await structurer.labels(for: sentences)
        let result = try await structurer.structure(sample)
        print(String(format: "=== %.2fs %@", Date().timeIntervalSince(start) / 2, String(labels.map(\.rawValue))))
        print(result ?? "(без изменений)\n\(sample)")
        print()
    }

case "rewrite":
    guard arguments.count > 1 else { fatalError("usage: vm-smart rewrite <file>") }
    let texts = try samples(arguments[1])
    let styles = (option("--styles") ?? "prompt,commit,cleaner,translate").split(separator: ",").map(String.init)
    // --to uk translates into Ukrainian instead of English.
    let target = option("--to").flatMap { Locale(identifier: "en").localizedString(forLanguageCode: $0) }
    let terms = PromptBuilder.builtInTerms + BuiltInDictionary.terms.map(\.written)
    var log = ""

    var generate: @Sendable (String, RewriteRequest) async throws -> RewriteGeneration
    var label: String
    if let model = option("--ollama") ?? option("--lmstudio") {
        let ollama = option("--ollama") != nil
        let server = ServerRewriter(api: ollama ? .ollama : .openAI, url: option("--url") ?? (ollama ? "http://localhost:11434" : "http://localhost:1234"), model: model)
        label = (ollama ? "ollama " : "lm studio ") + model
        let start = now()
        try await server.preload()
        print(String(format: "%@: preload %.2f s", label, now() - start))
        generate = { try await server.rewrite($0, request: $1) }
    } else {
        let repo = option("--repo") ?? SmartModelStore.rewriteRepo
        let store = SmartModelStore(repo: repo)
        guard store.isDownloaded else { fatalError("\(repo) is not downloaded: vm-smart download \(repo)") }
        let rewriter = LocalRewriter(store: store)
        if arguments.contains("--no-cache") { await rewriter.setReusesPrompt(false) }
        if arguments.contains("--no-drafts") { await rewriter.setDraftsFromDictation(false) }
        label = repo + (arguments.contains("--no-cache") ? " (no prompt cache)" : "") + (arguments.contains("--no-drafts") ? " (no drafts)" : "")
        var start = now()
        try await rewriter.load()
        let load = now() - start
        start = now()
        try await rewriter.warmUp()
        let warm = now() - start
        let weights = await rewriter.weightBytes
        print(String(format: "%@: load %.2f s, warm-up %.2f s, weights %.2f GB, active %.2f GB", repo, load, warm, Double(weights) / 1e9, Double(LocalRewriter.activeMemory) / 1e9))
        generate = { try await rewriter.rewrite($0, request: $1) }
        if arguments.contains("--ab") {
            // Each text twice, with and without drafting, so both see the same machine load.
            generate = { text, request in
                await rewriter.setDraftsFromDictation(false)
                let start = now()
                let plain = try await rewriter.rewrite(text, request: request)
                let plainTotal = now() - start
                await rewriter.setDraftsFromDictation(true)
                let drafted = try await rewriter.rewrite(text, request: request)
                print(String(format: "  plain %5.0f ms %5.1f tok/s | same output: %@", plainTotal * 1000, plain.tokensPerSecond, plain.text == drafted.text ? "yes" : "NO"))
                return drafted
            }
        }
    }

    struct Row {
        let style: String
        let words: Int
        let total: Double
        let firstToken: Double
        let tokensPerSecond: Double
        let generated: Int
        let cached: Int
        let prompt: Int
        let accepted: Bool
    }
    var rows: [Row] = []

    for style in styles {
        let request = switch style {
        case "prompt": RewriteRequest(style: .prompt, sourceLanguage: "Russian")
        case "commit": RewriteRequest(style: .commit, sourceLanguage: "Russian")
        case "cleaner": RewriteRequest(style: .cleaner, sourceLanguage: "Russian")
        case "translate": RewriteRequest(style: .none, translate: true, targetLanguage: target, sourceLanguage: "Russian")
        case "prompt-en": RewriteRequest(style: .prompt, translate: true, targetLanguage: target, sourceLanguage: "Russian")
        // selection:<instruction> — the Edit selection shortcut: the text is a fragment and
        // the style's instruction is what the user said over it.
        case let style where style.hasPrefix("selection:"):
            RewriteRequest(style: .selection, instruction: String(style.dropFirst("selection:".count)))
        default: RewriteRequest(style: .custom, instruction: style, sourceLanguage: "Russian")
        }
        for (index, text) in texts.enumerated() {
            let start = now()
            let generation = try await generate(text, request)
            let total = now() - start
            let cleaned = RewriteRequest.clean(generation.text, input: text)
            var verdict = RewriteValidator.check(original: text, candidate: cleaned, request: request, terms: terms)
            if generation.truncated { verdict = .rejected(.tooLong) }
            let words = [30, 80, 150].min { abs($0 - Words.split(text).count) < abs($1 - Words.split(text).count) }!
            rows.append(Row(style: style, words: words, total: total, firstToken: generation.timeToFirstToken, tokensPerSecond: generation.tokensPerSecond, generated: generation.generatedTokens, cached: generation.cachedTokens, prompt: generation.promptTokens, accepted: verdict.isAccepted))
            let verdictText = verdict.isAccepted ? "ok" : "REJECTED \(verdict)"
            let line = String(format: "%-9@ #%02d ~%3d words  total %5.0f ms  ttft %4.0f ms  %5.1f tok/s  %3d tok  prompt %4d (cached %4d)  drafts %3d/%3d  %@",
                              style, index + 1, words, total * 1000, generation.timeToFirstToken * 1000, generation.tokensPerSecond, generation.generatedTokens, generation.promptTokens, generation.cachedTokens, generation.acceptedTokens, generation.draftedTokens, verdictText)
            fflush(stdout)
            print(line)
            log += "=== \(line)\n\(cleaned)\n\n"
        }
    }

    print("\n\(label), peak memory \(String(format: "%.2f", Double(LocalRewriter.peakMemory) / 1e9)) GB\n")
    print("style      words  runs  total ms  ttft ms  tok/s  tokens  valid")
    for style in styles {
        for bucket in [30, 80, 150] {
            let group = rows.filter { $0.style == style && $0.words == bucket }
            guard !group.isEmpty else { continue }
            func mean(_ value: (Row) -> Double) -> Double { group.map(value).reduce(0, +) / Double(group.count) }
            print(String(format: "%-9@  %5d  %4d  %8.0f  %7.0f  %5.1f  %6.0f  %d/%d",
                         style, bucket, group.count, mean(\.total) * 1000, mean(\.firstToken) * 1000, mean(\.tokensPerSecond), mean { Double($0.generated) }, group.filter(\.accepted).count, group.count))
        }
    }
    if let out = option("--out") {
        try log.write(toFile: out, atomically: true, encoding: .utf8)
    }

default:
    print("usage: vm-smart download [repo] | structure <file> | rewrite <file> [--repo repo] [--styles list] [--out file]")
}
