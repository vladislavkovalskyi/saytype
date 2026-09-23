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

- `retranscribe(id, change)` reads the file with `RecordingFile.samples`, then runs `hear` and
  `compose` with the current settings and the record's mode (`modeID`, or the app's mode for
  records from before this update). One change is applied: `.model(variant)`,
  `.language(language)` or `.withoutTranslation`, which turns off both the overlay's switch and
  the mode's translation. The voice gate and the voice action check are skipped, snippets are
  resolved with variables read at that moment, and the language model runs without the esc skip.
  A record with `action` set is never re-transcribed (`canRetranscribe`).
- **Engine.** When the variant is the loaded one and the model is ready, the main engine is used.
  When it is the loaded one but still loading, the run stops with "Model not ready" instead of
  loading it twice. Otherwise a second `WhisperKitEngine` is prepared, used for `hear` and unloaded
  before the language model step; the main engine and `modelState` are never touched.
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

## The final pass after merging 008 and 009

`main` at `6373463` (008 voice snippets, 009 voice actions) was merged into this branch. 007's
`recognize` did Whisper and the text in one call. 009's voice action check has to sit between
the two, so `recognize` became two functions around a `Pass`. There is still one path: a live
dictation and a re-transcription call the same functions, and only `finalize` adds the live
parts.

```swift
/// What one run depends on, fixed when it starts. New inputs go here as fields with a default.
struct Pass {
    var settings: AppSettings
    var mode: DictationMode
    var selection: String?          // Edit selection: the words are an instruction over it
    var skippable = false           // esc skips the language model (live)
    var readsSelection = true       // {selection} in a snippet reads the app in front
    var projectTerms: [String] = [] // taken once, for the glossary and formatting
    var translateTo: AppSettings.SpeechLanguage?
    var whisperTranslates = false
}
struct PassResult { var text: String; var raw: String; var send: Bool; var snippets: [String] = [] }

func makePass(settings:mode:selection:skippable:readsSelection:) -> Pass          // translation decision, project terms
func hear(_ recorded: [Float], engine: WhisperKitEngine, pass: Pass) async throws -> Transcript
func compose(_ transcript: Transcript, pass: Pass, stage: (FinishingStage) -> Void) async -> PassResult
private func finalize(_ recorded: [Float], duration: Double, engine: WhisperKitEngine, audio: UUID?) async
```

**A live dictation, from the key to the text:**

1. Key down, `startRecording`: the target app and the mode; the recording file opens (not for
   Edit selection); `readSelectionForActions()` reads the selection by Accessibility in the
   background (009).
2. Key up, `finishRecording`: 250 ms of tail, the drain, `closeRecordingAudio()`. Then
   `transcribe`: empty audio goes back to idle; the voice gate's "Nothing heard" keeps the
   recording without text.
3. `finalize`, first `makePass(settings, activeMode, selection, skippable: true)`, then
   `hear`: Whisper with the glossary. An error keeps the recording as "recognition failed".
4. `runVoiceAction(transcript.text, …)` on the raw transcript, with `actionSelection` from key
   press. When the words are an action, it carries it out, writes its own record (with `action`)
   and returns. `finalize` deletes the recording and stops.
5. `compose`. First `DictationPipeline.format(…, snippets:)`, which turns snippet phrases into
   markers. For Edit selection it stops here: the instruction gets the snippets' text via
   `placingSnippets(…, selection:)` and comes back. Otherwise, when the text is only markers, the
   model and smart structure are skipped; if not, the model (esc skips it) or smart structure
   runs. Then backticks. Last, `placingSnippets` puts the snippets' text in place of the
   markers, reading `{clipboard}` and `{selection}` while the target app is still in front.
6. Back in `finalize`: Edit selection goes to `editSelection`. Only "отправь" presses Return and
   deletes the recording. Empty text keeps the recording as "Nothing heard". Otherwise the record
   (id = recording id, `audio`, `modeID`) goes into `records` and the store, then `sweepAudio()`
   and `deliver(text, …, snippets:)` (the card's mark).

**A re-transcription** reads the file, then runs `makePass(settings with one change, the
record's mode, readsSelection: false)`, `hear` and `compose`. It has no voice gate, no voice
action and no delivery; the text replaces the record's.

### Decisions at the merge

1. **Snippets are resolved in a re-transcription too.** Placement is the last step of `compose`,
   so a re-transcribed dictation gets the snippet's text, not ⟦1⟧. Variables are read at the
   moment of the re-transcription: `{date}` and `{time}` are then, `{clipboard}` is what the
   clipboard holds then. `{selection}` stays empty (`readsSelection: false`): the app in front is
   saytype's own window, and reading it would send a ⌘C into it. The record's `raw` keeps the
   spoken trigger, as 008 does.
2. **Voice actions run only live, between `hear` and `compose`.** A re-transcription never
   checks for one, so the same words come back as a dictation. A record with `action` set can't
   be re-transcribed: `canRetranscribe` is false, so the menu and ↻ are hidden and `retranscribe`
   refuses. Its `text` is the model's work on a selection or clipboard the recording can't bring
   back, and re-transcribing only its `raw` would add nothing to the history.
3. **Recordings of voice actions are not kept**, just as Edit selection keeps none. When
   `runVoiceAction` returns true, carried out or refused with a notice ("Nothing selected",
   "Clipboard is empty", "Language model is off"), the recording is deleted at once. A crash
   during what would have become an action leaves an interrupted recording, and transcribing it
   gives the instruction as text. A dictation that is only "отправь" also deletes its recording
   at once now, instead of at the next cleanup.
4. **`history` stays computed.** 009's `perform` inserts into `records` and follows the store's
   `add` with `sweepAudio()`, like `finalize`. `DictationRecord` has 009's `action` beside 007's
   fields, and the init takes it last. `init(from:)` decodes `action` leniently too. Tests cover a
   0.3.0 file, a 009 file with an action, and a round trip with both.

### For 006 (screen context)

Add `var screenTerms: [String] = []` to `Pass`. Merge it into the glossary in `hear`, where
`DictionaryRewriter.promptTerms` is called, and into `compose`'s formatting if the terms should
reach the dictionary step. `finalize` fills it with the terms read at key press
(`var pass = makePass(…); pass.screenTerms = …`). A re-transcription leaves it empty, or fills it
from the record if 006 stores the terms there. No other call site changes.

Before the merge the split was one `recognize(_:engine:settings:mode:instruction:skippable:stage:)`
(commit `40338fa`, behaviour unchanged); the merge commit turned it into `hear` and `compose`.

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
3. **A voice edit over a selection is not recorded, and a voice action's recording is deleted**
   as soon as the words turn out to be one. Neither can be replayed from the audio alone.
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

- `swift test` in `Packages/SaytypeKit`: 291 tests in 47 suites pass after merging `main`
  (264 on `main`, 235 on this branch before the merge). New in 007:
  - history decoding: a 0.3.0 file through the decoder and through the store, new fields
    round-trip, an unknown failure value is dropped, a 009 record with `action` decodes, and a
    record with both `action` and the audio fields round-trips;
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
