# 007 · Audio of recent dictations — Proposal

**Review:** follows the feature the owner approved on 24.09.2026; the design details below were
decided during the work, as the owner asked. Deviations go to
[`implementation.md`](implementation.md).

## In short

Every dictation is written to disk as it is recorded, in a file that stays readable if the app
dies halfway. The file is exactly the samples Whisper got, 16 kHz mono Float32. The history record
points to it. A day and the 20 newest recordings are kept by default. The History section and the
card can play a recording and run it through the final pass again, with the current settings,
another Whisper model on disk, another language, or without translation. The final pass is split
into recognition-and-formatting, which both paths share, and delivery, which only a live
dictation has.

## Storage format, chosen by measurement

The test: the recording format must give the same text as the samples the live dictation used.

Twelve synthetic dictations went through `vm-bench transcribe`: Russian (Milena) at 21, 42 and
96 s, English (Samantha) at 19 s, two single words, each at −62 dBFS white noise and again 18 dB
quieter over −70 dBFS noise. Model `large-v3-v20240930_turbo_632MB`, automatic language, a
16-term glossary prompt. Each file was encoded with the system encoders (`afconvert`) and
transcribed next to the original Float32 samples in the same process.

| Format | Same text as the original | Size per minute |
|---|---|---|
| Float32, 16 kHz (CAF) | 12 of 12; the same bits | 3.84 MB |
| 16-bit lossless (ALAC or FLAC) | 10 of 12 | 1.01–1.03 MB |
| 16-bit PCM | 10 of 12 | 1.92 MB |
| 24-bit lossless (ALAC or FLAC) | 7 of 12 | 1.97–1.99 MB |
| AAC 48 kbit/s | 7 of 12 | 0.38 MB |
| Opus 24 kbit/s | 5 of 12 | 0.18 MB |
| AAC 32 kbit/s | 4 of 12 | 0.25 MB |

The 16-bit copies changed words in both quiet long dictations ("фича" → "фичи", "процесс" →
"Process" and three more words gone in the 96 s one). The 24-bit copies did worse than the 16-bit
ones: they flipped "ворсел" to "Worsal" and "user data" to "userData" in the normal files. Whisper
sits on a knife edge between spellings, and any change to the samples, even 144 dB down, can tip
it either way. ALAC and FLAC gave exactly the text of the PCM they encode: the loss is in the
integer samples, not in the codec. Each file gave the same text on every run, in any order, so
the differences come from the samples, not from the engine.

On the way the bench's own loader turned out to cut the last ~30 ms of every file, a different
amount for each container, which at first made even identical Float32 copies disagree. It now
reads to the last frame (see `implementation.md`).

**Decision: Float32 in a CAF file, 3.84 MB per minute.** Quiet speech is where recognition is
most fragile, which is where a re-transcription is most needed, and that is where 16-bit changed
the text. With the default of a day and 20 recordings, a typical day of 10–30 s dictations holds
13–38 MB. The most the folder can hold is 20 × the longest dictation: 20 two-minute monologues are
154 MB. If the size ever matters more than identical text, 16-bit ALAC is a quarter of it.

## Recording to disk

- **When.** A writer opens when the microphone starts, unless audio is off or the dictation is a
  voice edit over a selection (it has no history record). Esc and a tap too short to count delete
  the file.
- **How.** The microphone's chunks already reach the controller on the main actor, about ten per
  second. Each chunk is handed to a serial queue of its own that appends it to the file: nothing
  is written on the real-time audio thread, and no disk I/O happens on the main thread. Every
  32 chunks (about 3 s) the file is synced to disk, so even a power cut loses at most a few
  seconds.
- **Crash-safe by format.** The file is a CAF whose `data` chunk comes last and is written with
  the size −1, which the format defines as "until the end of the file". Core Audio and our own
  reader read such a file at any moment of its life. When the recording ends, the real size is
  written in and the file is closed ("sealed").
- **Metadata inside the file.** An `info` chunk carries the start time, the app, its bundle id and
  the mode, so a recording found after a crash becomes a history entry with its app and time.
  One file per recording, `Audio/<record id>.caf`.
- **Folder.** `~/Library/Application Support/dev.kovalskyi.saytype/Audio/`, next to
  `history.json`. Preview and snapshot launches use a throwaway folder in the temporary directory,
  as the history already does, so they never see or touch real recordings.

## What becomes of a recording

| How the dictation ended | History | Audio |
|---|---|---|
| Text delivered | a record, as today, now with its audio and mode | kept |
| "Nothing heard" (the voice gate, or nothing left after formatting) | a record without text, marked "Nothing heard" | kept |
| Recognition failed | a record without text, marked "Recognition failed" | kept |
| The app quit, crashed or lost power | found on the next launch: a record marked "Not transcribed" | kept |
| Esc, a tap too short to count | nothing | deleted at once |
| Only "отправь" (Return pressed, nothing typed) | nothing | deleted by the next cleanup |
| Voice edit over a selection | nothing | never written |

Records without text show in the History section only. Home, the menu bar, the island's last
dictation, the paste-again and copy-last shortcuts, the stats and the onboarding practice see
finished dictations only, as before. A record without text lives as long as its audio: when the
audio goes, the record goes with it. So "Nothing heard" entries are brief by design.

## History link

`DictationRecord` gets four optional fields: `audio` (the file name), `modeID`, `failure`
(`interrupted`, `nothingHeard`, `recognitionFailed`) and `previous` (text and raw transcript
before the last re-transcription). A history file written before this update decodes unchanged.
The new fields are decoded leniently, so a value a newer build writes (an unknown failure kind)
drops that field instead of failing the whole file, which would empty the history on the next
save.

## Retention

- **Setting.** Off, a day (default) or a week, plus the 20 newest recordings. It sits in the
  History section header next to the history's own period: "Kept on this Mac for 30 days ·
  audio for 1 day". The count is a setting (`audioLimit`, 20) without its own control; the menu shows it
  as a fact.
- **Cleanup.** At launch (after recovery), after every dictation, when the setting changes and
  once an hour while the app runs, so "a day" holds even when nothing is dictated. A cleanup
  unlinks expired audio from records, deletes records that had nothing but audio, then deletes
  every file no record points to, except the recording in progress.
- **Deletion.** Deleting a record deletes its file at once. Clearing the history deletes the
  folder. Off deletes the folder. Records the history's own period prunes lose their files at the
  same cleanup. "Start from scratch" in the README already removes the whole support folder; the
  line about keeping the models now says to delete `Audio` along with `history.json`.

## Recovery after a crash

At launch, before the first cleanup: every recording file that no record points to is sealed
(the size written in, a half-written sample at the end trimmed) and becomes a record marked
"Not transcribed", with the app, mode and start time from its `info` chunk and the duration from
its length. Empty or unreadable files are deleted. Recordings a record already points to are
sealed too, in case the crash came after the record was saved.

## Playback

`AVAudioPlayer`, one recording at a time, owned by the controller so it survives switching
sections. In the History section: a play button in each row that has audio, and a strip in the
detail with play/pause, a progress bar and the time. In the card: a play icon next to the actions.

## Re-transcription

**What it runs.** The same recognition and formatting as a live dictation: the voice gate is
skipped (the user asked for it explicitly), then Whisper with the glossary prompt, the formatting
pipeline, the dictionary, the record's own mode (from `modeID`, or the app's mode for older
records), then the language model or smart structure, then backticks. Nothing is pasted and
nothing is learned. Settings are those of the moment, with one change:

| Menu item | Change |
|---|---|
| Transcribe Again | none |
| Model › each Whisper model on disk | that model; the current one is checked |
| Language › Automatic, Russian, English, then the rest | that language |
| Without Translation | the overlay's switch and the mode's translation off; disabled when nothing would translate |

**Result.** The new text and transcript replace the record's; the old ones are kept as `previous`
for one Undo. A record without text becomes a normal dictation. An empty result leaves the record
as it was and says "Nothing heard". Copy, Drag and Paste Again work on the new text as on any
record. If the card still shows that dictation, its text changes too.

**Another model.** A second `WhisperKitEngine` for that variant: loaded on demand, used once and
unloaded, while the main engine stays loaded and keeps serving dictations. The strip shows the
stage: loading the model, transcribing, rewriting. A model Core ML has not prepared on this Mac
yet can take minutes the first time; that is shown as loading. Only one re-transcription runs at a
time. On the current model a re-transcription uses the main engine, the same way the live text
and the final pass already share it; a dictation made meanwhile shares the Neural Engine with it
and finishes a little later.

**Models listed.** Every variant with all its Core ML parts under `Models/`, not only the two the
Model section offers: whatever is on disk can be used.

## The split of the final pass

Today `finalize` recognises, formats, rewrites, saves the record and delivers, all in one. It
becomes two functions:

- `recognize(_:engine:settings:mode:instruction:skippable:stage:) async throws -> PassResult` —
  Whisper, formatting, the language model or smart structure, backticks. It reads nothing from
  the recording in progress, only its arguments, so a re-transcription passes its own settings,
  mode and engine. `instruction` stops after formatting (a voice edit over a selection);
  `skippable` lets esc skip the language model (live only); `stage` reports transcribing and
  rewriting.
- `finalize` keeps its job for a live dictation: call `recognize`, then the selection edit, the
  empty-text cases, the record and the delivery.

The glossary and the translation decision move into `recognize` unchanged, which is where the
screen-context terms (006) and snippet markers (008) will land.

## Trade-offs

- **Size over compression.** Float32 is 3.8 times the size of 16-bit ALAC. The owner's rule was
  identical text, and only the same bits give it.
- **Records without text in the history.** They make the lost dictations findable where the owner
  looks for them; they vanish with their audio after a day.
- **The main engine is shared.** A re-transcription on the current model slows a live dictation
  started during it. Loading a second copy of the same model to avoid that would double the
  memory for a rare overlap.
- **No gate on re-transcription.** A recording of real silence may come back with a phrase
  Whisper invents; the hallucination filter catches the known ones.

## Privacy

Audio never leaves the Mac, as before. What changes: it is now written to disk, in the app's
support folder, for the chosen time and at most the 20 newest recordings, and it goes with its
record, with the history and when the setting is turned off. The README's Privacy section says
so instead of "never written to disk".
