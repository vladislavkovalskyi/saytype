# 007 · Audio of recent dictations — Plan

**Review:** follows the proposal, 24.09.2026.

Branch `007-audio-history` from `main` (066f0fc, with 005 merged). Nothing is merged or pushed
until the owner has tried the build.

| # | Stage | What is in it | How it is checked |
|---|---|---|---|
| 1 | Codec | The format test on synthetic dictations; `vm-bench codec` runs the app's recorder and compares texts | The table in the proposal; `vm-bench codec` on the same files |
| 2 | History record | `audio`, `modeID`, `failure`, `previous` on `DictationRecord`, lenient decoding; `HistoryStore` gains `modify`, `insert`, `remove(ids)`, `dropAudio`; stats skip records without text | `swift test`: a 0.3.0 history file decodes and loads, new fields round-trip, an unknown value is dropped, the store operations, the stats |
| 3 | Retention | `AppSettings.audioRetention` (off, day, week) and `audioLimit` (20); `AudioKeeping.expired` and `strays` | `swift test`: a day, a week, the count, records without audio, off, strays with a recording in progress |
| 4 | Recording file | `RecordingFile` (CAF, Float32, open-ended data chunk, `info` chunk), `RecordingWriter` on its own queue, `RecordingArchive` with recovery | `swift test`: bit-exact round trip, Core Audio and `AVAudioPlayer` read the file, a file cut mid-sample is readable and sealed, recovery leaves linked and active files alone, deletion |
| 5 | Final pass split | `recognize` (recognition and formatting, no delivery) and `finalize` (live only) in `DictationController` | `xcodebuild`; a read-through of every path that ends a dictation |
| 6 | Controller | The writer's lifecycle, records without text, cleanup at launch / after each dictation / hourly / on the setting, recovery at launch, deletion with the record and the history | `xcodebuild`; the paths reviewed one by one; the throwaway folder for previews |
| 7 | Re-transcription | `retranscribe` with the current settings, another model (a second engine, loaded and unloaded), another language, without translation; one-step undo; downloaded models listed | `xcodebuild`; `swift test` for the model list; a run through the engine with `vm-bench codec` shows stored audio gives the same text |
| 8 | UI | Retention menu, play in rows, the detail's audio strip and menu, card icons, strings in English and Russian | `--snapshot-main history` and `--snapshot-overlays` rendered to files with sample data |
| 9 | Close | README both languages, `implementation.md` | What was and was not verified, the new shape of `finalize` for the hand merge with 006 and 008 |

Shared files are touched as little as possible and only additively: `AppSettings` (two fields),
`Localizable.xcstrings` (new keys), `README.md` / `README.ru.md` (one section, the Privacy bullet
and the reset line), `SectionControls.swift` (submenus and disabled items in `MenuOption`).
`MainWindow.swift` is not touched: the setting lives in the History section's header.
