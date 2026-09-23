# 005 · Reliable recognition — Plan

**Review:** follows the approved proposal, 23.09.2026.

Branch `005-reliable-recognition` from `main`. Nothing is merged or pushed until the owner has
tried the build.

| # | Stage | What is in it | How it is checked |
|---|---|---|---|
| 1 | Bench | `vm-bench lab`: decoding options one at a time, per-sentence coverage, `--engine` through the real `WhisperKitEngine` | The "before" tables in the proposal come from it |
| 2 | Transcript segments | `TranscriptSegment` replaces `TranscriptWord`; `Paragraphs.split` works on segment gaps | `swift test`: paragraphs at long pauses after a sentence, none inside one, fallback when the text differs |
| 3 | Prompt budget | `PromptBuilder.prompt(glossary:tokenLimit:countTokens:)`, limit 40, skips what does not fit; hints carry the glossary | `swift test`: priority order kept, limit held by a real-looking counter and by the estimate |
| 4 | Engine | 1 s of zeros, no word timings, prompt from the tokenizer, segments in the padding dropped, per-segment cleaning | Bench through the engine: 40 word clips, the long files, the fast files |
| 5 | Filters | `VoiceGate`, `Loudness` shared with `AudioCapture`; whole-result "Thank you" rule | `swift test`: quiet speech passes, room and fan do not, clicks of digital zeros ignored; filter cases |
| 6 | Recording edges | Tail grace, drain, stop in flight blocks start and cancel, no 0.4 s guard, gate before `finalize` | `xcodebuild`, a read-through of every path that ends a recording |
| 7 | Close | Bench after, `implementation.md`, README if behaviour visible to users changed | Tables before and after, what was and was not verified live |

The controller's `finalize` keeps its signature; the gate runs before it, so the snippets work
(008) can hook into `finalize` without conflicts.
