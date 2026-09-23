# 007 · Audio of recent dictations — Implementation

**Review:** waiting for the owner. Nothing ran live in the app with the owner's microphone; what
was and was not checked is listed at the end.

## What was built

### Recording file (`VMAudio/RecordingFile.swift`)

- **Format.** A Core Audio Format file: a `desc` chunk for 16 kHz mono Float32 little-endian,
  an `info` chunk, then the `data` chunk, written with the size −1 ("to the end of the file").
  The samples are exactly the ones Whisper got.
- **`info` chunk.** Start time (`recorded date`, ISO 8601), app name, bundle id and mode id, so
  a recording found after a crash becomes a record with its app and time.
- **Reading.** `RecordingFile.samples(at:)` reads the data chunk directly, bit for bit, and
  drops a half-written sample at the end. Core Audio (`AVAudioFile`, `AVAudioPlayer`) reads the
  same file too, sealed or not (unit-tested).
- **`seal`** writes the real size into the data chunk and trims a partial sample. It leaves a
  file that is already sealed alone.
- **`RecordingWriter`** does everything on a serial utility queue of its own, never on the
  real-time audio thread and never on the main thread: it creates the file, appends each chunk
  as it arrives from the controller, syncs to disk every 32 chunks (about 3 s), and seals and
  closes it on `finish()`. `discard()` deletes the file. A failed write stops the file; the
  dictation itself goes on from memory.

### Archive (`VMAudio/RecordingArchive.swift`)

- The folder is `~/Library/Application Support/dev.kovalskyi.saytype/Audio/`, derived from
  `HistoryStore.defaultURL`. A recording's file is `<record id>.caf`.
- `recover(known:active:)` seals every file it finds. A file no record points to becomes a
  record with no text and `failure: .interrupted`; its date, app and mode come from the `info`
  chunk (the file date if that is missing), its duration from the length. An empty or unreadable
  file, and one whose record exists but no longer links it, comes back as junk to delete.
  Recordings in `active` are left alone.
- `delete(ids)`, `deleteAll()`, `files()`, `size()`.

### History and retention (`VMCore`)

- `DictationRecord` gets `audio` (the file name), `modeID`, `failure` (`interrupted`,
  `nothingHeard`, `recognitionFailed`) and `previous` (text and raw before the last
  re-transcription). `init(from:)` is written out: the old fields decode as before, and the new
  ones with `try?`, so a value only a newer build knows drops that field instead of failing the
  whole file, which the store would then save back empty. `isTranscribed` is `failure == nil`.
- `HistoryStore` gains `modify(id, change)`, `insert(found)` (in date order, no duplicates),
  `remove(ids)` and `dropAudio(ids)`, which unlinks the audio and removes records that had only
  audio.
- `HistoryStats` skips records without text.
- `AppSettings.audioRetention` (`off`, `day`, `week`; default `day`, an unknown value falls back
  to it) and `audioLimit` (20).
- `AudioKeeping.expired` returns the records whose audio goes: past the period, past the 20
  newest recordings (records without audio don't count), or all of them when off.
  `AudioKeeping.strays` returns the ids of files that no record links and that aren't being
  recorded.

### Controller (`DictationController`, `DictationAudio.swift`)

- **`records` and `history`.** `records` is the whole history, newest first, including
  recordings without text. `history` is now computed: `records` filtered to finished
  dictations. Home, the menu bar, the island, the paste-again and copy-last shortcuts, the stats
  and the onboarding practice keep reading `history` and see exactly what they saw before. The
  History section reads `records`.
- **Writing.** `startRecording` calls `beginRecordingAudio()` once the microphone runs, unless
  the audio is off or the dictation is a voice edit over a selection. `consume` appends every
  chunk. `cancelRecording` discards the file. After the drain, `finishRecording` calls
  `closeRecordingAudio()`, which starts sealing in the background and returns the recording's
  id. That id goes through `transcribe` and `finalize` and becomes the record's id. Until
  `transcribe` returns, it sits in `closingAudio`, and no cleanup takes the file.
- **Records without text.** The voice gate's "Nothing heard", an empty result that is not just
  "отправь", and a recognition error call `keepUntranscribed`, which adds a record with the
  recording and the reason. App and mode come from the file's `info` chunk, because a new
  recording may have started during the final pass.
- **Cleanup (`sweepAudio`).** The cleanup unlinks expired audio from records, dropping records
  that had only audio, then deletes every stray file. It runs at launch after recovery, after
  every record is added, when the retention menu changes, and every hour. Listing and deleting
  happen in one go on the main actor, so a recording that starts meanwhile can't be taken for a
  stray.
- **Deletion.** `removeFromHistory` deletes the file and stops playback. `clearHistory` sweeps,
  and with no records every file except the one being recorded is a stray. Off expires every
  recording at once. Records pruned by the history's own period lose their files at the next
  cleanup.
- **Previews.** `--demo-*`, `--show-*` and `--snapshot-*` launches get an archive in a
  throwaway temporary folder, as the history already did.

### Re-transcription (`DictationAudio.swift`)

- `retranscribe(id, change)` reads the file with `RecordingFile.samples`, then calls
  `recognize` with the current settings and the record's mode (`modeID`, or the app's mode for
  records from before this update). One change is applied: `.model(variant)`,
  `.language(language)` or `.withoutTranslation`, which turns off both the overlay's switch and
  the mode's translation. The voice gate is skipped. The language model runs without the esc
  skip.
- **Engine.** When the variant is the loaded one and the model is ready, the main engine is used.
  When it is the loaded one but still loading, the run stops with "Model not ready" instead of
  loading it twice. Otherwise a second `WhisperKitEngine` is prepared, used once and unloaded;
  the main engine and `modelState` are never touched.
- **State.** `retranscription` holds the record id and the stage: loading (with the model's
  name), transcribing, rewriting. A failure (nothing heard, couldn't transcribe, model failed,
  model not ready, recording not found) stays for 3 s. One re-transcription runs at a time.
- **Result.** The store's `modify` sets `previous` (when the record had text), text and raw,
  and clears `failure`. `undoRetranscription` puts `previous` back and clears it.
  `cardRecordChanged` updates the card when it still shows that dictation.
- **Models.** `ModelStore.downloadedVariants()` lists every variant under `Models/` with all its
  Core ML parts. The menu names them "Whisper turbo" (any `turbo` or `v20240930` build),
  "Whisper large-v3", or the variant itself, and adds the size when two builds share a name.

### Playback (`RecordingPlayer.swift`)

`AVAudioPlayer`, one recording at a time, owned by the controller. Play, pause, resume, seek,
and a 50 ms ticker for the playhead. At the end of the file it stops, and the next play starts
over.

### UI

- **History header:** "Kept on this Mac for 30 days ⌄ · audio for 1 day ⌄". The menu has
  Don't Keep, 1 day, 7 days and a disabled "Up to 20 recordings". When off, the line reads
  "· audio not kept ⌄".
- **Rows:** a small play button before the bars, and the bars dim past the playhead while that
  recording is loaded. A record without text shows its reason ("Not transcribed", "Nothing
  heard", "Couldn't transcribe") in place of the text. The row is now a tap target instead of a
  `Button`, so the play button inside it gets its own clicks.
- **Detail:** a strip under the header with play/pause, "0:04 / 0:12", a track you can click,
  Undo (when there is a previous text) and the "Transcribe Again ⌄" menu, or "Transcribe ⌄" for
  a record without text. While it runs the strip shows a spinner and the stage; a failure shows
  for 3 s. A record without text shows its reason, no Final/As spoken/Changes switch, and only
  Delete.
- **Card:** ▶/❚❚ and ↻ (the same menu) beside the actions, only when the card's dictation has a
  recording; a spinner in place of ↻ while it runs.
- **Menu:** Transcribe Again (disabled while the current model isn't ready) · Model › every
  model on disk, the current one checked · Language › Automatic, Русский, English, then all the
  others · Without Translation (disabled when nothing would translate).
- `MenuOption` got `isEnabled` and `submenu`.
- 16 new strings, each with its Russian translation; existing keys are reused where they
  already said the same thing.

### Tools

- `vm-bench codec <audio>...` runs each file through the app's recorder in 0.1 s chunks,
  checks the stored copy bit for bit and compares texts with 24- and 16-bit copies.
- `vm-bench record <audio> <folder>` writes at the microphone's pace until it is killed.
  `vm-bench recover <folder> [--original audio]` does what the next launch does and transcribes
  what it finds.
- `saytype --snapshot-main <section> <file.png>` renders a main window section offscreen with
  sample data. For History it also writes `-untranscribed` and `-retranscribing`.

## The new shape of `finalize` (for the hand merge with 006 and 008)

The refactor alone is commit `40338fa` (`refactor(dictation): split the final pass…`). It
changes no behaviour and can go in first. Commit `3b354d5` then adds the `audio:` parameter and
the records without text.

```swift
struct PassResult { var text: String; var raw: String; var send: Bool }

/// Whisper, formatting, language model or smart structure, backticks. Reads only its arguments.
func recognize(_ recorded: [Float], engine: WhisperKitEngine, settings value: AppSettings,
               mode: DictationMode, instruction: Bool = false, skippable: Bool,
               stage: (FinishingStage) -> Void) async throws -> PassResult

/// Live only: recognize, then the selection edit, the empty cases, the record, the delivery.
private func finalize(_ recorded: [Float], duration: Double, engine: WhisperKitEngine, audio: UUID?) async
```

What moved where:

| Old `finalize` step | Now |
|---|---|
| `projectTerms`, glossary `terms`, `translateTo`, `whisperTranslates`, `TranscriptionHints` | `recognize` (`selection == nil` became `!instruction`) |
| `engine.transcribe` | `recognize`, which throws; `finalize` catches, keeps the recording as "recognition failed" and shows the notice |
| `DictationPipeline.format` | `recognize` |
| `if let selection { editSelection … }` | `finalize`, after `recognize(instruction: true)` returned the formatted instruction |
| rewrite (`finishingStage`, `rewriteSkippably`) or `smart.apply`, `Backticks.wrap` | `recognize`; the stage goes out through `stage`, and `skippable: false` calls `rewriter.rewrite` directly |
| empty text: "отправь" / "Nothing heard" | `finalize` (+ `keepUntranscribed`) |
| `DictationRecord`, `history.insert`, `historyStore.add` | `finalize`; the record now has `id: audio`, `audio`, `modeID`, goes into `records`, and the add is followed by `sweepAudio()` |
| `deliver` | `finalize` |

Merge notes:

- **006, screen context (terms read at key press).** A re-transcription has no key press, so
  `recognize` must not read controller state. Add a parameter, e.g. `screenTerms: [String] =
  []`, merge it into `terms` where `DictionaryRewriter.promptTerms` is called, and pass the terms
  captured at key press from `finalize`. A re-transcription passes none. To reuse them later,
  store them on the record.
- **008, snippets resolved inside `finalize`.** Resolving snippet markers is formatting: put it
  in `recognize` right after `DictationPipeline.format`, before the rewrite, reading
  `value.snippets` from the `settings` argument. That way a re-transcription resolves them too.
  Anything with a side effect (pressing keys) stays in `finalize`.
- **`history` is computed now.** Code that assigned `history = …` must assign `records`. Code
  that only reads `history` needs no change.
- Other shared files: `AppSettings` got two fields and two decode lines after
  `historyRetentionDays`. `Localizable.xcstrings` got new keys only. The READMEs got one section
  before "Languages", the Privacy bullet, the reset lines and one FAQ sentence. `MainWindow.swift`
  is untouched.

## Codec: how it was chosen

Twelve synthetic dictations (Milena and Samantha at 16 kHz): 21, 42 and 96 s Russian with
pauses, a 19 s English one, two single words. Each exists at −62 dBFS noise and again 18 dB
quieter over −70 dBFS. Model turbo 632 MB, automatic language, the 16-term bench glossary. Each
copy was transcribed next to the original in one process; every file gave the same text on
every run and in any order.

| Format | Same text | Size per minute |
|---|---|---|
| Float32 CAF (chosen) | 12 of 12 | 3.84 MB |
| 16-bit ALAC / FLAC / PCM | 10 of 12 | 1.03 / 1.01 / 1.92 MB |
| 24-bit ALAC / FLAC / PCM | 7 of 12 | 1.99 / 1.97 / 2.88 MB |
| AAC 48 kbit/s | 7 of 12 | 0.38 MB |
| Opus 24 kbit/s | 5 of 12 | 0.18 MB |
| AAC 32 kbit/s | 4 of 12 | 0.25 MB |

`vm-bench codec` over the same twelve files, through the app's own recorder: stored copy
bit-exact 12 of 12 and same text 12 of 12; 24-bit 7, 16-bit 10; the recorder writes 3.84 MB per
minute.

## Crash recovery, verified

- **Unit test.** A file holding a header, 8000 samples and half a sample, with the data size
  still −1, reads as 8000 samples through both our reader and `AVAudioFile`. `recover` turns it
  into an `interrupted` record with the app and date from its `info` chunk and 0.5 s duration,
  seals it (the half sample trimmed, the real size written) and keeps the samples bit for bit.
- **A real kill.** `vm-bench record R90-n62.wav` wrote at the microphone's pace and was killed
  with `kill -9` after 40 s. The file held 37.3 s with the data size still −1.
  `vm-bench recover` found 1 recording and 0 junk: app `vm-bench`, 37.30 s, `interrupted`. Its
  596,800 samples were identical to the first 596,800 of the original, and Whisper gave the same
  text for both. After sealing, `afinfo` reads it as 16 kHz Float32, 37.3 s.
- **In the app.** The launch path (`records = await historyStore.all()`, then
  `recoverRecordings()`) was read through, not run: a plain launch of a dev build would run
  against the owner's real data.

## Decisions the owner should know

1. **Float32, 3.84 MB per minute**, not 16-bit ALAC (1.03 MB): 16-bit changed words in both
   quiet long dictations. The folder holds 13–38 MB on a typical day and 154 MB at most for 20
   two-minute monologues.
2. **Lost dictations are history entries.** "Nothing heard", recognition errors and crashes show
   in the History section only, with their reason, and vanish with their audio after the period.
   Everything else that reads the history ignores them.
3. **A voice edit over a selection is not recorded.** It has no history record.
4. **The period is strict for recovered recordings too.** A crash found days later, past "a day",
   goes at the first cleanup. Relaunching within the period recovers it.
5. **Off deletes every recording at once.** Switching back on keeps only new dictations.
6. **Re-transcription skips the voice gate**, so "Nothing heard" recordings can be tried. Real
   silence may return a phrase Whisper invents that the filter does not know.
7. **Undo is one step and survives relaunches** (`previous` is saved in the history).
8. **"Another model" on the owner's Mac today** means the two turbo builds on disk, 632 MB and
   626 MB (`large-v3-v20240930_626MB` is a turbo build too). Whisper large-v3 (947 MB) is not
   downloaded; once it is (Model → Other models), the menu lists it.
9. **The retention setting lives in the History header**, next to the history's own period, not
   in a settings section; the count of 20 has no control of its own.
10. **The card's audio controls exist only in the Card output mode**, since only that mode has a
    card.

## Deviations from the proposal

1. **The bench loader was cutting the end of every file.** `AudioFileLoader` read the whole file
   with one `AVAudioFile.read(into:)`. That read returns a few hundred frames short, a different
   number for WAV and CAF (330,741 and 330,752 of 331,239 on one file). So two identical copies
   gave different text, and every earlier bench number, 005's included, lost the last ~30 ms of
   each file. The loader now reads until the file ends (`1737fb4`). 005's conclusions are not
   affected: its test files end in silence. The first codec table in the proposal draft was
   measured with the old loader and was redone. Only vm-bench uses the loader; the app reads its
   own recordings directly.
2. **Cleanup lists and deletes files on the main actor.** The proposal kept disk I/O off the main
   thread for recording. The cleanup touches at most a few dozen small directory entries. Doing
   it in one go on the main actor is what keeps a recording that starts meanwhile from being
   taken for a stray.
3. **A re-transcription on the current model does not wait for a live dictation or block it.**
   Both run on the same engine concurrently, as the live text and the final pass already did.
   The proposal first said the live pass would wait.
4. **"Transcribe" vs. "Transcribe Again".** The menu is titled "Transcribe" on a record without
   text.

## Checked

- `swift test` in `Packages/SaytypeKit`: 235 tests in 45 suites pass (210 before). New:
  - history decoding: a 0.3.0 file through the decoder and through the store, new fields
    round-trip, an unknown failure value is dropped;
  - retention: a day, a week, the count of 20, records without audio, off, strays next to a
    recording in progress, ids from file names;
  - store: `dropAudio`, `insert` in date order without duplicates, `modify`, stats without
    untranscribed records;
  - settings: older documents get a day and 20, an unknown period falls back, off round-trips;
  - recording file: a bit-exact round trip in 0.1 s chunks with the `info` chunk; Core Audio,
    `AudioFileLoader` and `AVAudioPlayer` read it; a crash-cut file is readable, recovered and
    sealed; recovery leaves linked and active files alone and reports empty and unlinked ones;
    `delete`, `deleteAll`, `discard`;
  - `ModelStore.downloadedVariants`: complete variants only, without the prefix.
- `xcodebuild … -configuration Debug -derivedDataPath build/dev -skipPackagePluginValidation
  -skipMacroValidation build`: builds. A clean build gives the same warning set as a clean
  build of `main` (mlx's C++17 notes, `fed` in `AudioCapture` and `AudioFileLoader`,
  `ProjectScanner`), no new ones. SwiftPM rewrites `Package.resolved` (its `originHash` follows
  `Package.swift`, which gained the `VMAudioTests` target); the file was reverted each time, as
  instructed.
- UI through snapshots only, with sample data and default settings: `--snapshot-main history`
  in English and Russian (the list, a recording without text, a re-transcription loading
  "Whisper large-v3"), and `--snapshot-overlays` for the island and the pill card with audio
  and while re-transcribing. The Russian strip fits: "Отменить" and "Распознать заново ⌄" next
  to a 0:06 recording.
- The codec measurement and the kill test above.

## Not checked

- **A live run in the app.** Recording to disk from the real microphone during a dictation,
  playback through the speakers, clicks in the menus, Undo, deleting and the retention menu,
  the hourly cleanup, and recovery at an actual launch. All of it was read through path by path,
  and the storage layer under it is tested, but none of it ran in the app.
- **Re-transcription in the app,** with either engine: memory while a second model is loaded
  (~1–1.5 GB more), how long a model Core ML has not prepared takes to load, the language model
  step, the card updating.
- **The card's menu while its shortcuts are on.** The key interceptor takes esc, C, V and E from
  every app while the card is up, so esc may close the card rather than the open menu.
- **The spinner in snapshots** renders faint offscreen; on screen it is the system spinner in
  dark appearance.
- **Real voices.** The codec choice rests on synthetic speech. A real microphone's noise floor
  is usually above the 16-bit step, so 16-bit may well be safe for most real dictations. The
  quiet synthetic files are where it was not.
