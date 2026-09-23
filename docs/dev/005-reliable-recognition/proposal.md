# 005 · Reliable recognition — Proposal

**Review:** approved by the owner on 23.09.2026 ("fix the bugs"), design details decided during
the work. Deviations during implementation go to [`implementation.md`](implementation.md).

## In short

Both bugs come from how the app calls WhisperKit, not from Whisper itself, and a third problem
sits at the edges of every recording. The fix changes four places: the engine call (tail
padding, no word timings, a shorter prompt), a voice gate in front of Whisper, one more rule in
the hallucination filter, and how the controller stops the microphone.

## How the causes were found

Synthetic Russian dictation (the Milena voice, 16 kHz, −62 dBFS noise underneath) was fed
through WhisperKit 1.1.0 with the owner's settings: the `large-v3-v20240930_turbo_632MB` model,
automatic language, and a prompt built from their 14 dictionary entries plus the built-in terms.
The test harness is `vm-bench lab` (committed with this update). The test set:

- 40 single-word clips of «да», «привет», «окей» and «отправь», 0.5–1.2 s long, with 0.1 s or
  0.3 s of silence in front;
- ten-sentence dictations with pauses of 0.7–3 s and one 4.5 s "thinking" pause, 20–93 s long
  (L20, L28, X35, L45, X59, L70, X93);
- the same sentences read fast (about 3.3 words per second, close to the owner's fastest
  dictations) at 25 and 77 s (F28, F60);
- noise-only clips of 0.5, 1 and 3 s, a quiet room and a fan.

## Causes

### 1. Nothing under one second is decoded

`TranscribeTask` walks the audio with `while seek < seekClipEnd - windowPadding`, and
`windowPadding` is `windowClipTime` (1.0 s by default) in samples. A recording of one second or
less never enters the loop: 32 of the 40 word clips came back empty before any other cause
applied. Every word the owner says in one short press falls into this.

### 2. Word timings break the text whenever there is a prompt

The app asks for word timings (for paragraph breaks) and always sends a prompt. WhisperKit trims
the decoded tokens to start at `<|startoftranscript|>`, but it stores the alignment weights at
the absolute decoder position, which begins with `<|startofprev|>` and the prompt. The word
aligner reads the rows from zero, so every word gets the attention of a token 86 positions
earlier. The timings come out as nonsense; segments whose end falls before their start are
filtered out (`currentSegments.filter { $0.end > $0.start }`); and the window's seek moves to a
bogus "last speech" time.

| Clip / file | App today | Same prompt, no word timings |
|---|---|---|
| single words 1.2 s, non-empty | 2 of 8 | 8 of 8 |
| X35, sentences found | 4 of 6 (the last two lost) | 6 of 6 |
| L45 | 7 of 8 | 8 of 8 |
| X93 | 12 of 16 (four in the middle lost) | 16 of 16 |

This is the "only the last sentences" and "only the first sentence" pattern from the owner's
history. It does not depend on the 30 s mark: X35 is 35 s, the history shows losses at 16 s.

### 3. The prompt eats the window's token budget

Whisper decodes at most 224 tokens per 30-second window, prompt included. The owner's prompt is
85 tokens (236 characters), plus 5 special tokens, which leaves 133 for text and timestamps.
Russian comes out at 4.2–4.4 tokens per second at a normal pace and 6.4 when read fast, so a
dense window needs up to about 190. When the budget runs out mid-window, the window ends with
no closing timestamp and WhisperKit moves on by the full window: the rest of it is lost. F28
lost its last sentence and F60 the end of its first chunk, with or without word timings. With
the prompt capped at 60, 40 or 20 tokens both came out complete.

The prompt also costs time: WhisperKit feeds it to the decoder one token at a time before every
window. A 5 s clip decodes in 1.50 s with the 85-token prompt and in 0.62 s without one.

### 4. The recording loses its edges

`finishRecording` stops the audio engine the moment the key goes up, cancels the task that reads
the capture stream and copies `samples` right away. Whatever is still in the stream, and the
audio of the last I/O cycle, never reaches Whisper. People release the key as the last word
ends, so the last word loses its tail. Then a guard throws away any recording under 0.4 s
without a word, although the key gesture already lets through holds from 0.3 s: the microphone
takes a moment to start, so a 0.35 s hold gives less than 0.35 s of audio.

### Also found

- Once decoding runs on silence, Whisper answers "Thank you.": 4 of the 6 noise-only clips did
  with the padding in place. The owner's history holds 4 dictations whose whole text is
  "Thank you." (1.6–4.0 s long), so this already reaches their text today.
- Refuted: the no-speech skip (`noSpeechProb` is hard-coded to 0 in WhisperKit 1.1.0);
  `maxInitialTimestamp` (1.0 gave byte-identical output on every file); the parallel decoding
  of VAD chunks (0, 1 and 16 workers gave identical text); and actor reentrancy between a
  cancelled live pass and the final pass (the final text matched a clean run 3 times of 3).

## Design

### Engine

**One second of zeros after every recording.** Whisper pads each window to 30 s with zeros
anyway, so to the model the tail is the same silence; to WhisperKit's loop it means every real
sample lies more than a second before the end. This fixes short recordings and the last second
of long ones, and it also reaches the VAD chunker, which has its own fixed one-second margin
(`VADAudioChunker(windowPadding: 16000)`, created inside WhisperKit, not configurable). Setting
`windowClipTime` to 0 fixed the short clips too but would leave the chunker's margin in place.

Segments that start inside the padding are dropped: there is nothing there to transcribe.

**No word timings.** The final pass always carries a prompt, so they were always misaligned.
The paragraph rule ("a pause of 1.5 s after a finished sentence") moves to the gaps between
Whisper's segments. `Transcript` gets `segments` (text, start, end) in place of `words`. Segment
timestamps come from Whisper's own timestamp tokens and are not affected by the prompt: in the
bench runs the gaps between segments matched the real pauses within 0.1 s. The trade-off: when
Whisper puts several sentences into one segment, a pause inside it does not start a paragraph.
Dropping word timings also removes the alignment pass from every window.

**The prompt capped at 40 real tokens.** The hints carry the glossary, not a finished string,
and the engine builds the prompt because only it has the tokenizer. Terms stay in priority
order: the user's dictionary, then project terms, then built-in terms. A term that does not fit
is skipped and a shorter one after it may still fit. The trimming has to happen on our side:
WhisperKit keeps the *last* 111 tokens of a long prompt, which would drop the user's dictionary
first. Without a tokenizer the existing estimate stands in. Trade-off: fewer terms bias Whisper's
spelling; the dictionary rewriter still turns the heard forms into the written ones afterwards.
With 40 tokens all long files came out complete and each window decodes about 0.5 s faster.

**Kept as they are.** `.vad` chunking above 30 s: without it the text was the same and the
decode slower (L45 5.4 s against 3.9 s, L70 9.0 s against 5.9 s). `maxInitialTimestamp` stays
unset: it changed nothing on any file, and the text was never lost at the start of a window.

### Voice gate

`VoiceGate` in VMCore decides whether a recording has any voice before Whisper runs. It uses the
silence detector's idea of voice with a floor taken from the whole recording:

- 50 ms frames on the final samples; frames of digital zeros (the microphone starting) are
  skipped;
- the floor is the quietest frame;
- a frame is voice when it is at least −45 dBFS (`SilenceDetector.minimumVoice`) and 9 dB above
  the floor (`SilenceDetector.voiceMargin`);
- the recording passes with 0.1 s of voice in total, continuous or not, or when no frame is
  quieter than −45 dBFS, since then there is no quiet moment to compare with.

No voice means "Nothing heard" right away, without Whisper. The gate is permissive on purpose: it
only turns away what is clearly silence. A cough or a click passes, and Whisper and the
hallucination filter handle it.

### Hallucination filter

A result that is only "Thank you", "Thank you very much" or "Thank you so much" (any case, any
punctuation) becomes empty, so the user sees "Nothing heard" instead of the phrase in their text.
The rule looks at the whole result only: "Thank you. Увидимся завтра." stays as it is. It is off
when Whisper itself translates, where «спасибо» → "Thank you." is a real answer. Trade-off: a
dictation of just "thank you" in English is lost; with anything after it, it is kept.

The subtitle phrases are now cleaned per segment as well as in the joined text, so a segment
that was only "Продолжение следует." no longer makes the segments disagree with the text and
switch paragraphs off.

### Recording edges

- **Tail grace.** After the key goes up, after the overlay's stop button, and after the key
  press that ends hands-free recording, the microphone keeps recording for 250 ms. Cancel and
  the hands-free silence stop get no grace: the silence is already recorded.
- **Drain.** Then the capture stops and the controller waits for the task that reads the stream
  to finish. `AsyncStream` hands out what it has buffered after `finish()`, so every chunk the
  tap delivered is in the samples.
- **No second recording during the stop.** The phase turns to `finishing` when the key goes up,
  so the overlay shows the transcription stage at once. A press of the record key before the
  drain ends is ignored, and so is the cancel its quick release would send. Until now such a
  press started a second recording that the first one's delivery then broke.
- **Minimum length.** The 0.4 s guard goes. The key gesture already cancels holds shorter than
  `tapThreshold` (0.3 s); whatever gets past it is a dictation. Empty audio returns to idle,
  anything else goes to the voice gate.

The live loop stays as it is.

## Rejected

- **Our own chunking at pauses** (cut at pauses of 0.5 s or more, chunks of 15–28 s, each
  decoded on its own). It lost text on fast speech (10 of 22 sentences on F60 without padding),
  invented "Thank you." at the padded end of a chunk, and was 2–3 times slower (L70: 20.1 s
  against 5.9 s), because every chunk pays the prompt and a full 30 s encoder pass.
- **Transcribing finished chunks while the user still speaks.** It has the same weaknesses as
  own chunking: sentences cut at chunk borders, no context across them, and a 5 s chunk costs
  1.5 s with the prompt. It would only pay off on very long dictations. It can come back as a
  separate update together with the live loop.
- **`windowClipTime = 0` instead of padding.** It leaves the VAD chunker's one-second margin in
  place.
- **Dropping the prompt and keeping word timings.** It loses the dictionary's spelling bias,
  which is the reason the prompt exists.

## Risks

- **Paragraphs.** They break less often where Whisper merges sentences into one segment.
- **Prompt terms.** The prompt holds fewer terms. For the owner this means their dictionary and
  a few built-in terms.
- **Voice gate.** A voice quieter than −45 dBFS is taken for silence. That is below a whisper at
  arm's length from the built-in microphone.
- **Latency.** The tail grace adds 250 ms to every dictation. The shorter prompt and the dropped
  alignment pass should win it back on anything longer than a few words.
