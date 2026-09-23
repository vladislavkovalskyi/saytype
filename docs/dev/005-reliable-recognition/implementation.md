# 005 · Reliable recognition — Implementation

**Review:** waiting for the owner. The live run with their voice has not been done yet; what
was and was not checked is listed at the end.

## What was built

### Engine (`WhisperKitEngine.transcribe`)

- **Where windows may start.** WhisperKit starts no window in the last `windowClipTime` of the
  audio (1 s by default), and its VAD chunker keeps a fixed second of its own. The engine now
  moves that margin to 0.3 s before the last frame of voice (`VoiceGate.voiceEnd`):
  - it pads with zeros when the voice ends less than a second before the end, so the chunker's
    fixed second doesn't reach past the margin;
  - it sets `windowClipTime` to reach back from the end of the audio to the margin;
  - the first window always starts, at least 0.05 s of room;
  - segments from a window begun after the margin, and segments that begin in the padding, are
    dropped.

  `WhisperKitEngine.windowPlan` does the arithmetic and has its own tests.
- **No word timings.** `Transcript.words` is replaced by `Transcript.segments` (text, start,
  end), and `Paragraphs.split` uses the gaps between segments.
- **No first-token fallback.** `firstTokenLogProbThreshold` is `nil`; see the deviations below.
- **Prompt within 40 real tokens.** `TranscriptionHints` carries `glossary: [String]` in place
  of `prompt` and `wordTimestamps`. The engine calls
  `PromptBuilder.prompt(glossary:tokenLimit:countTokens:)` and counts tokens with the Whisper
  tokenizer. Terms stay in priority order and a term that does not fit is skipped. Without a
  tokenizer, the existing estimate counts instead.
- **Hallucination filtering.** Subtitle credits are cleaned per segment and again in the joined
  text. A whole result that is only "Thank you", "Thank you very much" or "Thank you so much"
  becomes empty, except when Whisper translates.
- **Kept as they were.** `.vad` chunking above 30 s, and no `maxInitialTimestamp`.

### Voice gate (`VMCore/VoiceGate.swift`)

- The recording is cut into 50 ms frames. Frames of digital zeros are skipped.
- The room level is the 10th percentile of the frames.
- A frame is voice at −45 dBFS or louder and at least 9 dB above the room. These are the silence
  detector's `minimumVoice` and `voiceMargin`.
- A recording passes with 0.1 s of voice frames in total, continuous or not.
- `voiceEnd` gives the end of the last voice frame; the engine uses it for the window margin.
- `Loudness` holds the −60…0 dBFS → 0…1 scale, now shared with `AudioCapture.level`.

### Recording edges (`DictationController`)

- `finishRecording(grace:)` sets the phase to `finishing` at once. After 250 ms (none for the
  hands-free silence stop), it stops the capture, waits for the task that reads the stream, and
  only then reads `samples`.
- While that stop runs (`stopping`), `startRecording` does nothing. `cancelRecording` acts only
  on a running recording, so the quick release of an ignored press cannot reset the dictation
  being finished.
- The 0.4 s minimum is gone. Empty audio returns to idle. A recording with no voice shows
  "Nothing heard" without Whisper. Everything else goes to `finalize`, whose signature did not
  change; the only edit inside it is the hints (`glossary:`).

### Bench (`vm-bench lab`)

- **Default mode.** Replays the decoding of 0.3.0: the legacy 240-character prompt, word timings
  and no padding.
- **Flags.** One flag per variable: `--no-words`, `--pad-tail`, `--clip-time`, `--max-initial`,
  `--no-vad`, `--workers`, `--prompt-tokens`, `--no-first-token-check`, and own chunking
  (`--chunk`).
- **`--engine [--gate]`.** Runs the current `WhisperKitEngine`, with the voice gate in front
  when `--gate` is given.
- **Output.** `--refs` with `--sentences` marks every reference sentence found or missing.
  `--log` prints WhisperKit's fallback reasons. The header shows which glossary terms the
  prompt kept.

## Deviations from the proposal

1. **The window margin sits at the end of the voice, not at the end of the audio.** The plain
   second of padding from the proposal worked for single words. Through the real engine,
   though, 2 of 10 dictations (X35, L45) came back with "Thank you." at the end. After
   decoding the last phrase, the seek stopped at Whisper's last timestamp, 0.1 s before the
   voice really ended. The padding then let one more window start on the 0.6 s of trailing
   silence. The margin now stops windows 0.3 s before the last frame of voice. `windowClipTime`
   carries it when the recording ends in a long silence, so no window is decoded only to be
   thrown away. The cost shows in the T files: before this change, a dictation ending in more
   than 0.7 s of silence took 2.2 s instead of 1.3 s.
2. **WhisperKit's first-token check is off.** It is WhisperKit's own rule, not Whisper's: if the
   first sampled token has a log-probability under −1.5, the window is decoded again at
   temperature 0.2, 0.4 and so on, up to five times. After the prompt the first token is a
   timestamp that often looks unlikely. With the new prompt and padding it fired 29 times on 40
   single words and 3 times on one 70 s dictation. The results changed from run to run, and in
   one run a whole VAD chunk came back empty. With the check off there were no fallbacks on any
   file, the text was the same on every run, and the coverage was complete. Silence is the gate's
   job now.
3. **The gate's room level is the 10th percentile, not the quietest frame.** With the quietest
   frame, one or two frames of the microphone ramping up would pull the room down and let a
   steady fan through. The proposal's rule "loud from start to end passes" is dropped for the
   same reason. A steady fan above −45 dBFS would have passed it, while speech always has dips
   of more than 9 dB between syllables and passes anyway (unit-tested with no quiet moment at
   all).
4. **Cancel acts only on a running recording.** The proposal only ignored cancel while a stop
   was running. A tap during a notice (password field, no model) used to hide the notice at
   once; now the notice stays for its time.

## Bench: before and after

All audio is synthetic Russian (the Milena voice) at 16 kHz with −62 dBFS noise. The model is
`large-v3-v20240930_turbo_632MB` with automatic language and the owner's dictionary in the
prompt. Hardware: the owner's Mac. "Before" is `vm-bench lab` in its default mode, the decoding
of 0.3.0. "After" is `vm-bench lab --engine --gate`, the app's current path. Decode times are
the median of three runs, and every file gave the same text on all three runs.

### Single words

«да», «привет», «окей», «отправь», 0.5–1.2 s long, with 0.1 or 0.3 s of silence in front.

| | Before | After |
|---|---|---|
| Words recognised | 2 of 40 | 40 of 40 |
| Decode time | 1.38 s (the only clips decoded were the 1.2 s ones) | 0.89 s on average over all 40 |

«окей» comes out as "Okay." because the language is automatic and the word is English-like.
With the language set to Russian that should not happen; it was not tested.

### Dictations

| File | Length | Before: sentences | Before: decode | After: sentences | After: decode |
|---|---|---|---|---|---|
| L20 | 20.0 s | 4/4 | 2.21 s | 4/4 | 1.74 s |
| X23 | 23.2 s | 4/4 | 2.30 s | 4/4 | 1.80 s |
| L28 | 27.7 s | 5/5 | 2.39 s | 5/5 | 1.91 s |
| F28, fast | 25.0 s | 6/7 | 2.75 s | 7/7 | 2.49 s |
| X35 | 35.0 s | 4/6 | 3.43 s | 6/6 | 2.68 s |
| L45 | 46.5 s | 7/8 | 3.87 s | 8/8 | 3.08 s |
| X59 | 58.8 s | 10/10 | 5.27 s | 10/10 | 4.14 s |
| L70 | 72.0 s | 13/13 | 5.77 s | 13/13 | 4.59 s |
| F60, fast | 76.8 s | 21/22 | 8.20 s | 22/22 | 6.95 s |
| X93 | 93.3 s | 12/16 | 7.39 s | 16/16 | 5.98 s |

The final pass is 10–22% faster on every file. The time comes from the shorter prompt and the
alignment pass that no longer runs.

### Silence at the end and a last short word

The T files are two sentences followed by 0.25–3 s of silence. D8 is one sentence, a 1.2 s pause
and «да». D34 is seven sentences, a pause and «да», 37 s in all.

| File | Before | Before: decode | After | After: decode |
|---|---|---|---|---|
| T0.25 | 2/2 | 1.79 s | 2/2 | 1.28 s |
| T0.6 | 2/2 | 1.80 s | 2/2 | 1.28 s |
| T1.0 | 2/2 | 1.79 s | 2/2 | 1.30 s |
| T1.5 | 1/2 | 1.81 s | 2/2 | 1.30 s |
| T3.0 | 2/2 | 1.80 s | 2/2 | 1.30 s |
| D8 | nothing at all | 1.56 s | the sentence and «Да.» | 1.08 s |
| D34 | 4/7 and «Да.» | 3.74 s | 7/7 and «Да.» | 2.96 s |

None of the 17 files produced "Thank you." after the change.

### Silence only

The noise clips are a quiet room and a fan, at 0.5, 1 and 3 s.

| | Before (0.3.0, no gate) | After, with the gate | After, engine alone |
|---|---|---|---|
| Text | empty on all 6 | turned away by the gate on all 6 | empty on all 6 |
| Time | 0–6.4 s (the 3 s fan went through fallbacks) | 0 s | about 0.9 s each |

The owner's history holds 4 dictations whose whole text was "Thank you." (1.6–4.0 s long). A
recording like that now ends as "Nothing heard".

### The owner's prompt

The glossary is 25 terms: the owner's 14 dictionary entries and the built-in terms. Before, the
prompt held 236 characters and 85 tokens. Now it holds 11 terms in 40 tokens: the first 10
dictionary entries and one short built-in term. The four newest dictionary entries do not fit.
They are still applied by the dictionary rewriter after recognition; only Whisper's spelling
bias toward them is gone.

## Checked

- `swift test` in `Packages/SaytypeKit`: 210 tests in 39 suites pass. New tests cover:
  - the voice gate: quiet speech, a quiet single word, speech over a fan and speech with no
    quiet moment pass; a room, a fan, a click and a ramping microphone do not; digital zeros are
    skipped; the voice end is found;
  - the window plan: a short word, a long trailing silence, a recording that ends in voice, no
    voice;
  - the prompt: priority order, skipping, the limit with the estimate and with a counter;
  - the "Thank you" rule;
  - paragraphs from segment gaps, including a pause inside one segment.
- `xcodebuild -scheme Saytype -configuration Debug -derivedDataPath build/dev
  -skipPackagePluginValidation -skipMacroValidation build`: builds. The only warnings are old
  ones in `ProjectScanner`, `AudioCapture` and `AudioFileLoader`; none are new. Without
  `-skipPackagePluginValidation` the build stops at mlx-swift's plugin check, as it did before
  this update; the release script passes the same flag.
- The bench above, through the real `WhisperKitEngine` and `VoiceGate`.

## Not checked

- **A live run in the app.** Nothing was done with the owner's voice, microphone, room and key
  timing. The tail grace and the drain were read through on every path that ends a recording,
  but they have not run against real device buffers.
- **Start latency.** Bluetooth headsets that switch profile when the microphone opens can still
  cut the first word. This update does not touch the start of a recording.
- **Paragraphs on real dictations.** Segment gaps were checked in the bench logs and in unit
  tests only.
- **Other paths.** Project terms in the prompt (the owner has no project folders), Whisper's own
  translation on large-v3, and hands-free recording with the silence auto-stop on (the owner has
  it off).

## Known limits

- **Paragraphs.** Whisper sometimes puts several sentences into one segment, and then a pause
  inside it does not start a paragraph.
- **WhisperKit drops failed chunks.** If a VAD chunk fails to decode, WhisperKit drops it
  without an error (`updateSeekOffsetsForResults` skips `.failure`). No failures were seen; the
  code was not changed for this.
- **"Thank you" alone.** A dictation of only "thank you" in English ends as "Nothing heard".
- **Tail grace latency.** The grace adds 250 ms between the key release and the text. On
  anything longer than a word, the faster decode wins it back.
