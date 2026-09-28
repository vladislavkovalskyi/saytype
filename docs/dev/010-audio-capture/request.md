# 010 · Microphone capture that survives other apps — Request

**Review:** requirements taken from the owner's message of 28.09.2026.

## What is needed

The owner's words:

> Братан, чет приложение перестало работать нормально, оно мой голос не распознает чишо, я не
> знаю, протести пожалуйста и выкати фикс если что. А если я сижу в дискорде, к примеру (в
> приложении, которое использует микрофон), saytype вовсе вылетает

## What the Mac showed

- Six crash reports of 0.4.0 (and one of a 0.2.0 debug build) on 27–28.09, all the same: the main
  thread dies with `EXC_BAD_ACCESS` inside `MainActor.assumeIsolated`, called from the
  permissions timer in `AppModel.start()`.
- Each crash is preceded, 0.1–3 s earlier on the main thread, by an Objective-C exception from
  `com.apple.coreaudio.avfaudio` that AppKit swallowed (`HIExceptions FAULT`). Seven such
  exceptions in three days, each followed by a crash.
- The history holds no dictation between the 0.4.0 install and 28.09 16:52, though the owner kept
  relaunching the app (five launches in two minutes on 27.09).

## Reproduced (scratch harness running the app's `AudioCapture`)

1. **Crash.** The mic's sample rate changes while saytype is idle (48 → 44.1 kHz, which apps
   like Discord do). The next recording on the app's long-lived `AVAudioEngine` raises
   `Failed to create tap due to format mismatch`. Thrown through Swift async code, the exception
   leaves the concurrency runtime's thread state pointing at an unwound stack; the next
   `assumeIsolated` reads it and crashes.
2. **Silence that never ends.** While another process runs voice processing on the built-in mic
   (a voice call), every capture API gets digital silence. That much is macOS. But saytype's
   engine stays silent after the call ends too, for every dictation until the app is relaunched,
   while a fresh engine hears the mic again within seconds. That is "it does not recognise my
   voice": each dictation ends in "Nothing heard".
3. **No audio at 44.1 kHz.** With the mic at any rate other than 48 kHz, even a fresh engine gets
   no buffers: after the device is selected, the input node still reports 48 kHz, and a tap in
   that format receives nothing.

## How we will know it worked

- No recording start, device change or sample-rate change can crash the app; the worst case is
  the "Microphone unavailable" notice.
- After another app's voice call ends, the next dictation hears the mic.
- Dictation works with the mic at 44.1 kHz and at 48 kHz.
- A recording of pure digital silence says so, instead of "Nothing heard".
