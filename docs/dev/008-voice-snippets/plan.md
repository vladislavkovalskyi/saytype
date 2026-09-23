# 008 · Voice snippets — Plan

**Review:** waits for the owner.

Branch `008-voice-snippets` from `main` at 0.3.0 (`6bcd506`). 005 rewrites the recognition path
in parallel, so `DictationController.finalize` gets one line and nothing else.

| # | Stage | What is in it | How it is checked |
|---|---|---|---|
| 1 | Model and settings | `Snippet`, `AppSettings.snippets`, decoding | `swift test`: 0.3.0 settings JSON decodes with no snippets; a round trip keeps them |
| 2 | Matching | `SnippetMatcher`, markers in `DictationPipeline.format`, `PipelineResult.snippets` | `swift test`: case, punctuation, hyphens, joined words, word boundaries, sentence ends, longest phrase, list order, command precedence |
| 3 | Placement and variables | `SnippetPlacement`, `SnippetVariables` | `swift test`: snippet alone, mid-sentence, at the end, empty, multi-line; every text style keeps the marker; unknown braces stay |
| 4 | Language model | Marker rule in `RewriteRequest.userMessage`, marker check in `RewriteValidator` | `swift test`: prompt names the marker only when there is one; missing, doubled, changed and invented markers are rejected |
| 5 | Delivery | `finishWithSnippets` in `DictationController`, values read at delivery, `deliver` passes snippet texts to the card | `xcodebuild` without new warnings; the path is walked through in code review against `finalize` |
| 6 | Main window | Snippets section, rail object, preview samples, strings with Russian | `--show-main snippets` screenshot of the window, no overlays; `xcodebuild` |
| 7 | Card mark | Faint background on snippet text in the card, a snapshot shot | `--snapshot-overlays` into a folder under `build/dev` |
| 8 | Docs | README and README.ru sections, `implementation.md` | Read through |

Tests come first in stages 1–4, since they carry the logic; stages 5–7 are glue and UI.

What cannot be checked here: a real dictation through the microphone. A plain launch of the dev
build would take over the owner's settings and history, and preview launches do not record. The
pipeline from transcript to final text is covered by tests; the app side is covered by the build
and by reading.
