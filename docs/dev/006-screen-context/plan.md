# 006 · Screen context — Plan

**Review:** follows the proposal, 24.09.2026.

Branch `006-screen-context` from `main` after 008 landed (`509cff6`). Nothing is merged or pushed
until the owner has tried the build. Update 007 is built in parallel; the shared files
(`DictationController`, `AppSettings`, `MainWindow`, `Localizable.xcstrings`, the READMEs) get
small additive edits only.

| # | Stage | What is in it | How it is checked |
|---|---|---|---|
| 1 | Sound key | `SoundKey`: key of a word in either script, weighted distance | `swift test`: the pairs from the proposal's table get equal or near keys; unrelated words do not |
| 2 | Terms | `ScreenText`, `ScreenTerms.extract`: identifiers, files, handles, Latin names; filters; ranking; cap | `swift test`: each kind, each filter, source weights, the cap, a noisy UI text |
| 3 | Matcher | `ScreenTermMatcher`; `TextFormatter` and `DictationPipeline.format` take it | `swift test`: every row of the proposal's table, separators, case endings, punctuation kept, handles, names; ordinary Russian and English sentences unchanged with a screen full of terms |
| 4 | Bench | `vm-bench context`: synthetic dictations with a screen text each, through the engine and the pipeline; prompt variants | Terms right with no context, with the matcher, with a prompt share, with both; decides the prompt |
| 5 | Reader | `ScreenContextReader` in VMSystem; `vm-context` debug command that reads only marked windows | TextEdit, Terminal, Safari and a separate VS Code profile: what each gives and how long it takes |
| 6 | App | `AppSettings.screenContext`; the read at key press and its use in `finalize`; the switch and readout in Dictionary; strings with Russian | `xcodebuild` without new warnings; `--show-main dictionary` captured in both languages |
| 7 | Close | README sections and the Privacy line in both languages; `implementation.md` | Read through; `swift test` all green |

Stages 1–3 carry the logic and come with their tests first. The app side (6) cannot be run with a
real dictation here: a plain launch of the dev build would take over the owner's settings and
history, and preview launches never record. The path from transcript to text is covered by tests
and the bench; the reader by the debug command.
