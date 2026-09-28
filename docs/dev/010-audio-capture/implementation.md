# 010 · Microphone capture that survives other apps — Implementation

**Review:** built and verified 28.09.2026; released as 0.4.1 at the owner's request ("протести
пожалуйста и выкати фикс").

## Diagnosis

- Crash reports: 6 of 0.4.0 and 1 of a 0.2.0 debug build, all `EXC_BAD_ACCESS` at `0x1e`/`0x0` in
  `swift_task_isMainExecutorImpl` under `MainActor.assumeIsolated` in the permissions timer.
- Each crash report has a thread named `SOME_OTHER_THREAD_SWALLOWED_AT_LEAST_ONE_EXCEPTION`, and
  the unified log shows `[com.apple.hiservices:HIExceptions] FAULT: com.apple.coreaudio.avfaudio`
  on the **main thread** 0.1–3 s before each crash. Seven exceptions in three days, seven
  crashes (one of them is the debug build's).
- A scratch harness ran the app's `AudioCapture` with an Objective-C catcher and printed the
  reason: `Failed to create tap due to format mismatch, <1 ch, 48000 Hz>`, raised when the
  microphone went from 48 to 44.1 kHz between two recordings on the same engine.

## What changed

| File | Change |
|---|---|
| `Sources/VMCatch` (new, Objective-C) | `VMCatchException(block)`: `@try` around a block, returns the exception |
| `VMAudio/AudioCapture.swift` | fresh engine per `start()`; tap in `inputNode.inputFormat(forBus:)`; every engine call through `guarded`; lifecycle on a serial queue; configuration changes retap the same engine, a fresh one only if that fails; a watchdog relaunches a stalled engine (0.6 s without buffers, 2 s before the first one, at most 3 times); the converter follows the buffers' format; the device is set only when it differs |
| `VMCore/VoiceGate.swift` | `hasSignal`: false for exact zeros |
| `DictationController` | all-zero recordings end with "No microphone signal" and drop their audio |
| `OverlayModel`, `Localizable.xcstrings`, `OverlaySnapshots` | the notice, «Нет сигнала микрофона», a snapshot |
| `vm-bench capture` | records through `AudioCapture`, several rounds on one instance, prints chunks, seconds, peak and signal |

Deviation from the proposal: the proposal rebuilt a fresh engine on every configuration change.
In practice a fresh engine announces a configuration change of its own right after it starts,
so every rebuild triggered the next one and no buffer ever arrived (0 chunks in every
scenario). The configuration change now retaps the same engine. That alone didn't cover a rate
change in the middle of a recording: the notification comes while the engine still reads the
old rate, the retap succeeds and no buffers follow. The watchdog covers that case.

The notice is shorter than proposed ("No signal from the microphone" ran the island to its full
width).

## Verified

`vm-bench capture` on the owner's MacBook Pro microphone (`BuiltInMicrophoneDevice`). The rate
changes were made through Core Audio and restored to 48 kHz afterwards. Another process with
voice processing on stood in for a call app.

| Scenario | 0.4.0 `AudioCapture` | 0.4.1 |
|---|---|---|
| 2–3 recordings in a row, 48 kHz | audio | audio |
| rate 48 → 44.1 kHz between recordings | exception (the crash) | audio in both |
| microphone at 44.1 kHz | 0 buffers | audio |
| another app's voice processing during recording 1 | zeros | zeros, "No microphone signal" |
| … and recording 2 after it ends | zeros until relaunch | audio |
| rate change in the middle of a 6 s recording | exception on the notification thread | 4.7–4.8 s of 6 s, recording goes on |

- `swift test`: 332 tests pass (new: `CaptureGuardTests`, `SignalTests`).
- App build: succeeds, no new warnings (the `fed` capture warning moved with the converter code).
- Overlay snapshots of the new notice, island and pill, English and Russian.

## Not verified

- A live dictation in the app with Discord in a real voice call; the harness process stood in
  for it. Whether Discord uses voice processing is not known, so the README names no app.
- Bluetooth headsets and USB microphones.
