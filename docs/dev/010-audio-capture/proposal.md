# 010 · Microphone capture that survives other apps — Proposal

**Review:** the owner asked for the fix to be tested and released (28.09.2026); measurements from
the scratch harness are in [`implementation.md`](implementation.md).

## Changes

### A new engine for every recording

`AudioCapture` creates its `AVAudioEngine` in `start()` instead of once per app run. An engine
costs a few milliseconds; a long-lived one keeps a stale input format and, after another app's
voice processing, a dead input chain. The harness showed both: the stale format raised the
exception behind the crashes, and the dead chain gave silence until relaunch. A fresh engine
per recording heard the mic again (peak level 0.40 against 0.00 on the old engine).

### The tap in the hardware's format

After the device is selected, the tap uses `inputNode.inputFormat(forBus: 0)`, the device's own
format, and the converter to 16 kHz is built from it. The node's output format stayed at 48 kHz
when the mic ran at 44.1 kHz and the tap got no buffers; `format: nil` failed to start
(`-10868`). With the hardware format both rates record.

Each tap buffer is still checked against the converter's input format; a buffer in another
format rebuilds the converter instead of being converted wrong.

### No Objective-C exception reaches Swift

AVFoundation reports misuse of `AVAudioEngine` with Objective-C exceptions, which Swift can't
catch and which must never unwind through Swift frames. A small Objective-C target, `VMCatch`,
wraps a block in `@try/@catch` and returns the exception. Every engine call that can raise
(`installTap`, `removeTap`, `prepare`, `start`, `stop`) goes through it; an exception becomes
`CaptureError.engine(reason)`, and the dictation shows "Microphone unavailable".

### Device changes during a recording

`AVAudioEngineConfigurationChange` rebuilt the tap on whatever thread posted the notification,
racing the main thread, with errors dropped. Now the capture rebuilds a fresh engine on its own
serial queue, under the same exception guard, and keeps the same stream: the recording goes on
with the new device. If the rebuild fails, the stream finishes and the dictation ends with what
it has.

### Digital silence gets its own notice

A recording whose samples are all exact zeros is a microphone that gave nothing, typically
because another app holds it for a call. It ends with a new notice, "No microphone signal"
(«Нет сигнала микрофона»), instead of "Nothing heard", and without Whisper.

## Not changed

- Recording while another app runs voice processing on the same mic still gets silence: the
  harness got zeros from `AVAudioEngine` and `AVCaptureSession` alike. The notice says so
  instead of pretending nothing was said.
- The permissions timer keeps `MainActor.assumeIsolated`; it was the victim, not the cause.
