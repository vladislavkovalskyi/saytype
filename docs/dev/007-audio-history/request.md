# 007 · Audio of recent dictations — Request

**Review:** the feature as the owner approved it on 24.09.2026; the details are decided during
the work and written down in [`proposal.md`](proposal.md).

## What is needed

The owner's ask, as approved:

> Audio of recent dictations is kept locally: a day or the last 20 recordings, and it can be
> turned off. The history and the card get "play" and "re-transcribe", with another model,
> another language, or without translation. If recognition eats something again or the app
> crashes mid-recording, a two-minute monologue does not have to be dictated again.

## Why

Update 005 fixed the known ways recognition lost words, but when a dictation still comes out
wrong, the audio is gone the moment the text is pasted. A dictation that ended in "Nothing heard",
a recognition error, a crash or a force quit loses everything that was said. Kept audio makes all
of these recoverable: listen to what was said, run it again with the other Whisper model or the
right language, and get the text without speaking it again.

## How it is read

- **What is kept.** The recording of each dictation, the same 16 kHz mono audio Whisper gets, in
  the app's folder on this Mac. Nothing leaves the Mac.
- **How long.** A day by default, a week as the other choice, and never more than the 20 newest
  recordings. Off keeps no audio at all. The text of the history keeps its own period
  (7/30/90 days); only the audio goes sooner.
- **Play.** From the history, and from the card if it fits the card's design.
- **Re-transcribe.** Runs the kept audio through the same final pass as a live dictation:
  Whisper, formatting, the dictionary, the mode, rewrite or translation. What can change: the
  Whisper model (any other one on disk), the language, or translation turned off. The new text
  replaces the old one in the history, the old one can be brought back once, and the new text can
  be copied or pasted.
- **Crash.** Audio reaches the disk while the key is held. If the app quits, crashes or loses
  power mid-recording, the next launch finds the recording and lists it in the history as not
  transcribed, ready to be transcribed.
- **Lost text.** A dictation that ended in "Nothing heard" or a recognition error keeps its audio
  too, so it can be tried again.

## Scope

- Recording to disk during the dictation, the storage format, cleanup by age and count.
- The history record's link to its audio; deleting audio with the record, the whole history and
  in "Reset everything".
- The retention setting next to the history's own retention.
- Playback and re-transcription in the History section and the card.
- The final pass split so re-transcription reuses recognition and formatting without delivery.
- README (a short section and the Privacy section), both languages.

Out of scope: the live text while recording, editing the audio, exporting it, keeping audio of a
voice edit over a selection (it has no history record).

## How we will know it worked

- The stored file, transcribed again, gives the same text as the samples the live dictation used,
  on the synthetic bench audio; the size per minute is known.
- A recording whose process was killed mid-dictation is found on the next launch, readable up to
  the moment of the kill, and becomes a "not transcribed" history entry.
- With the setting on "a day", nothing older than a day and nothing past the 20th recording is on
  disk after a dictation or a launch. Off leaves the folder empty.
- Deleting a record, clearing the history, turning the audio off delete the files.
- A history file written before this update loads unchanged.
- Re-transcribing with another model loads that model, transcribes, unloads it, and the main
  model keeps working throughout.
