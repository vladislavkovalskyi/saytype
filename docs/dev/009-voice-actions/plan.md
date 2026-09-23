# 009 · Voice actions over the selection and the clipboard — Plan

**Review:** follows the proposal; waits for the owner.

Branch `009-voice-actions` from `main` at `509cff6` (005 and 008 merged). 006 (screen context)
and 007 (audio history) are built in parallel and both change `DictationController`: edits
there stay to one call in `startRecording`, one branch in `finalize`, two stored properties and
one notice case; the rest goes into an extension at the bottom of the file.

| # | Stage | What is in it | How it is checked |
|---|---|---|---|
| 1 | Detection | `VMCore/VoiceActions.swift`: `VoiceAction`, `VoiceActions.detect`, word classes, language names from `Locale`, default target by script, `RewriteRequest.translation(into:)` | `swift test`: the corpus of positives (owner's phrases, polite forms, both languages, cases of language names, sources before and after the verb) and negatives (chat and agent phrases, pointers as determiners, "на карту", long and subordinate residue), with and without a selection |
| 2 | Settings and history | `AppSettings.voiceActions` (default on), `DictationRecord.action`, stats count the spoken words of an action | `swift test`: 0.3.0 settings JSON loads with the switch on; a round trip keeps it off; old history JSON decodes; stats of an action record |
| 3 | Validator | Length bounds for translations into or out of Chinese, Japanese and Korean | `swift test`: a CJK translation passes, a Latin one still fails when too short |
| 4 | Sources | `SelectionReader.focusedSelection(pid:timeout:)`: AX only, nonisolated, messaging timeout | `xcodebuild`; read-through |
| 5 | Controller | Read at key press, the branch in `finalize`, source resolution, model run with esc, history, delivery, `clipboardEmpty` notice; `RewriteService.translate` | `xcodebuild` without new warnings; every path of the proposal walked through in code |
| 6 | Overlay and settings UI | Rewrite label shows the action; toggle in Text; strings with Russian; snapshot shots | `--snapshot-overlays build/dev/snapshots` (files, nothing on screen); `--show-main text` capture of the preview window |
| 7 | Bench | `Bench/action-corpus.txt`: Russian and English paragraphs; `vm-smart rewrite --styles translate --to es/en/ru` and the selection style with the owner's phrasings | Answers read and judged; validator verdicts; times |
| 8 | Close | README and README.ru sections, `implementation.md` with the exact hooks for merging 006 and 007 | Read through; `swift test`; `xcodebuild` |

What cannot be checked here: a real dictation through the microphone over a real selection or
clipboard. A plain launch of the dev build would take over the owner's settings and history, and
tests must not read or change the owner's clipboard or selection. The logic from transcript to
action is covered by tests; the controller side by the build and by reading.
