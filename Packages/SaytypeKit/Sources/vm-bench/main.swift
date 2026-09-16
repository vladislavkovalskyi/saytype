import Foundation
import VMAudio
import VMCore
import VMTranscription

// Command-line harness for measuring recognition on recorded phrases.
//
//   vm-bench download [variant]
//   vm-bench transcribe <audio>... [--variant v] [--prompt] [--live]
//
// --prompt adds the punctuated sample and glossary; --live replays the file in
// one-second steps through LiveAgreement, the way the app does while fn is held.

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
    let files = arguments.dropFirst().filter { !$0.hasPrefix("--") && $0 != option("--variant") }
    let engine = WhisperKitEngine(store: store, variant: variant)
    let loadStart = ContinuousClock.now
    try await engine.prepare()
    print("model \(variant) loaded in \(String(format: "%.1f", seconds(loadStart))) s\n")
    let glossary = ["useEffect", "useState", "Header", "Vercel", "Supabase", "Next.js", "TypeScript", "Prisma", "Zod", "GitHub Actions", "React Query", "Docker Compose", "Postgres", "Redis", "SwiftUI", "Telegram"]
    let hints = TranscriptionHints(language: "ru", prompt: arguments.contains("--prompt") ? PromptBuilder.prompt(glossary: glossary) : (arguments.contains("--terms") ? glossary.joined(separator: ", ") + "." : nil), wordTimestamps: !arguments.contains("--no-words"))
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
            print(String(format: "  encode %.2f · decode %.2f · words %.2f · pipeline %.2f", t.encoding, t.decodingLoop, t.wordTimestamps, t.total))
        }
        print("  \(transcript.text)\n")
    }

default:
    print("usage: vm-bench download [variant] | vm-bench transcribe <audio>... [--variant v] [--prompt] [--live]")
}
