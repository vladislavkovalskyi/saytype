# 010 · Microphone capture that survives other apps — Plan

**Review:** follows the proposal; the owner asked for a tested release.

1. `VMCatch`: an Objective-C target with one function that runs a block and returns the
   exception it raised. `VMAudio` depends on it.
   *Check:* a unit test raises an `NSException` in a block and gets it back.
2. `AudioCapture`: a fresh engine per `start()`, the tap in the hardware format, the converter
   rebuilt when a buffer's format differs, every engine call guarded, configuration changes
   handled on a serial queue with a fresh engine and the same stream.
   *Check:* the scratch harness scenarios, run against the package's `AudioCapture` through a
   `vm-bench capture` command: two recordings around a sample-rate change, two recordings
   around another process's voice processing, recording at 44.1 and 48 kHz. No exception, audio
   in every case where the mic is free.
3. `DictationController`: "No signal from the microphone" for all-zero recordings; the capture
   error path shows "Microphone unavailable". Onboarding's microphone step uses the same class.
   *Check:* `swift test`, app build, overlay snapshot of the new notice in English and Russian.
4. Release 0.4.1: README FAQ line, implementation notes, `scripts/release.sh`, GitHub release,
   appcast, tap.
