# 009 · Voice actions over the selection and the clipboard — Implementation

**Review:** waits for the owner. What was checked, and how, is at the end; a real dictation was
not run.

Branch `009-voice-actions` from `main` at `509cff6`. Commits:

| Commit | What |
|---|---|
| `273e410` | docs: request, proposal, plan |
| `6eea9e5` | VMCore: detection, setting, history field, CJK length bounds |
| `3b56f86` | tests: the corpus and the rest of `VoiceActionsTests` |
| `b7a962c` | validator: three false rejections the bench found |
| `a69ad8c` | app: selection read, the branch in `finalize`, overlay, settings row, strings |
| `d1d845a` | `Bench/action-corpus.txt` |

## What was built

### Detection (`VMCore/VoiceActions.swift`)

`VoiceActions.detect(_ transcript:selectionAtStart:sendCommand:) -> VoiceAction?` works on the raw
transcript. `VoiceAction` has the source (`selection` / `clipboard`), how the words refer to it
(`named` / `pointer` / `implied`), the job (`translate(language)` / `translateUnnamed` / `instruct`),
the instruction as said, and `send`.

The rules as built:

| Reference | Verbs | Besides the verb and source |
|---|---|---|
| Named: "выделенное", "буфер обмена", "clipboard", "what I copied" | translate, text (сократи, rephrase…): any | up to 6 other words, no clause words (чтобы, если, который, он, it, when…) |
| | fix (исправь, fix), general (сделай, make) | modifiers only |
| Pointer: "это", "this", "it", "этот текст", "the text" | translate, text | modifiers and a target only |
| | fix | the same, with a mistake word ("опечатки", "typos") |
| | general | the same, with a word about the text ("короче", "formal"), not just "до", "в", numbers |
| Implied: nothing, a selection read at key press | as for a pointer; translate needs a target or a source language ("переведи с английского") | |

- The source must come before any other word that is not part of the instruction ("исправь
  ошибки в выделенном" passes, "поправь вставку из буфера обмена" does not), or before the verb
  ("выделенное переведи на английский").
- A source keyword counts only when the word after it (after glued text nouns) belongs to the
  instruction: "the selected tab", "clipboard manager", "выделенной области" name something else.
- A pronoun followed by a word outside the instruction is a determiner: "fix this bug".
- "на X" / "to X" that is not a language makes a translate verb over a pointer or an implied
  selection a dictation: "переведи мне деньги на карту", "переведи его на другую должность".
- A language adjective before a text noun is the source language: "переведи английский текст на
  русский".
- More than 24 words, two different sources, or any voice command other than a trailing
  "(и) отправь" / "(and) send it": a dictation. The trailing send is cut off the instruction and
  sets `send`.
- Languages: every Whisper code by its `Locale` name in English (two-word names included) and in
  Russian (adjective stem with its case endings, other names whole or with a noun ending), plus
  aliases: mandarin, farsi, bengali, maori, filipino, flemish, голландский, фарси, бенгали,
  филиппинский.
- `VoiceActions.defaultTarget(for:instruction:translateTarget:)`: for `translateUnnamed`, the
  translate everything language if the text is in another script, else the instruction's
  language (Cyrillic → Russian, Latin → English) if its script differs, else `nil` and the
  instruction goes to the model.
- `RewriteRequest.translation(into:)`: translate everything's request for a given language.

Detection takes about 0.2 ms per utterance (400 calls in 0.09 s in `detectionIsCheap`).

### Settings and history

- `AppSettings.voiceActions = true`, decoded with `decodeIfPresent`.
- `DictationRecord.action: DictationRecord.Action?` (`source`, `target` Whisper code), optional, so
  old history files decode. `spokenWordCount` is the instruction's words for an action;
  `HistoryStats` uses it, so a translated page does not add a page of dictated words and "time
  saved".
- Record of an action: `text` = the model's result, `raw` = the transcript of the instruction. The
  card's edit learning works on it like on a translated dictation.

### Validator (`RewriteValidator`)

Found by the bench, all limited to translations:

- a number spelled out in the answer counts as kept: "3 раза" → "three times";
- size and frequency units (KB…TB, Hz…GHz) are not protected: "4 GB" → "4 ГБ";
- in Latin-script text, lowercase hyphenated words without digits are prose, not kebab-case:
  "double-check", "follow-up". In Russian text "feature-flag" stays protected;
- a translation into or out of Chinese, Japanese or Korean (over 30 % Han, kana or Hangul
  letters) is checked only against a wide upper bound (4× + 120 characters).

### App

- `SelectionReader.focusedSelection(pid:timeout:)` (VMSystem): Accessibility only, no ⌘C,
  `nonisolated`, a 0.25 s messaging timeout on the app element and the focused element, `nil` for
  secure input and password fields. `limit` and `usable` became `nonisolated`.
- `RewriteService.translate(_:into:settings:)`: `run` with `RewriteRequest.translation(into:)`.
- `DictationController`:
  - `readSelectionForActions()` at the end of `startRecording`: with the switch on, not for the
    Edit selection shortcut, not in previews; a detached task reads the frontmost app's selection.
    When it finds one and the built-in model is not loaded, it warms the model up (a loaded model
    keeps translate everything's cached prompt).
  - `runVoiceAction(_:duration:settings:)` in `finalize` (hook below): detection; no model ready →
    "Language model is off", except a pointer with nothing AX could see, which stays words;
    clipboard empty → "Clipboard is empty"; selection from key press, else `SelectionReader.read()`
    (AX, then ⌘C with the clipboard put back); nothing → "Nothing selected" for a named selection,
    words for a pointer.
  - `perform`: resolves the target, sets `action` for the overlay, runs the model through
    `skippable` (esc leaves everything as it was), "Model didn't answer" on failure or rejection,
    writes the history record, `deliver`s by the mode's output with `pressReturn: send`.
  - `actionTag`: "Selection → ES", "Clipboard → EN", "Selection", "Clipboard".
- Overlay: `RewritingLabel(title:)` shows the tag instead of "Rewriting" in the island and the
  pill; widths use `RewritingLabel.width(title:)`. Notice `.clipboardEmpty` ("Clipboard is
  empty", `doc.on.clipboard`). Snapshot shots `6d-action-clipboard-translate`,
  `6e-action-selection`, `8e-notice-clipboard-empty`.
- Text section: "Voice actions" under Voice commands, detail “translate the selection to
  Spanish”, “shorten the clipboard text”; with the engine off the row is dimmed and reads
  "language model is off".
- Strings: 4 new keys with Russian (Voice actions, its two details, Clipboard is empty); the tag
  reuses "Selection" and "Clipboard".
- README and README.ru: a "Voice actions" section after "Edit the selection by voice".

## Hooks for merging 006 and 007

Everything else of the feature is in new files or in the `// MARK: Voice actions` extension at the
bottom of `DictationController.swift`.

| File | Hook |
|---|---|
| `DictationController.swift`, `Notice` | `case clipboardEmpty` after `editFailed` |
| `DictationController.swift`, properties | after `selection`: `private(set) var action: VoiceAction?` and `@ObservationIgnored private var actionSelection: Task<String?, Never>?` |
| `DictationController.startRecording` | last line, after `runLiveLoop()`: `readSelectionForActions()` |
| `DictationController.cancelRecording` | `actionSelection = nil` after `selection = nil` |
| `DictationController.finalize` | right after the `do { transcript = … } catch { … return }` block, before `let style = value.applying(mode)`: `if await runVoiceAction(transcript.text, duration: duration, settings: value) { return }` |
| `DictationController`, demo helpers | `demoAction(_:)` after `demoCardSnippets` |
| `AppSettings` | `voiceActions` after `snippets`, its decode line after `snippets`' |
| `History.swift`, `DictationRecord` | `action` after `date`; init parameter `action: Action? = nil` last; `HistoryStats` counts `record.spokenWordCount` |
| `RewriteService` | `translate(_:into:settings:)` after `editSelection` |
| `TextSection` | `RowDivider()` and the Voice actions row after Voice commands |
| `OverlayParts`, `IslandView`, `PillView` | `RewritingLabel(title:)`, `RewritingLabel.width(title: dictation.actionTag)` |
| `OverlayModel`, `OverlaySnapshots` | the notice's three cases; `Shot.action`, three shots |

- **006 (screen context)** also reads Accessibility at key press. The two reads are independent;
  if 006 already has the focused element in a detached task, the selected text could be read in
  the same pass. 006's terms go into Whisper's hints; detection uses the transcript either way.
- **007 (audio history)** splits `finalize` into recognize+format and deliver. The hook belongs
  between recognition and formatting: an action replaces both formatting and delivery. Two
  points: 007's re-transcription must not rewrite a record whose `action` is set (its `text` is
  the model's result, not the instruction), and both branches add a field to `DictationRecord`
  and a parameter to its init, which merge side by side.

## Deviations from the proposal

| What | Why |
|---|---|
| A named source allows 6 other words, not 12, and none at all with "исправь" or "сделай" | Instructions to coding agents about this app: "поправь буфер обмена в Paster", "исправь выделенный текст в карточке, он не подсвечивается" |
| A keyword counts only when the next word belongs to the instruction | "make the selected tab bold", "translate the clipboard manager docs" |
| "Сделай" / "make" over a pointer or an implied selection with a word about the text | "сделай это короче", "make it more formal" were rejected and are natural |
| An implied selection may be translated with only the source language named | "переведи с английского" |
| Thanks as fillers, "содержимое" as glue, a language adjective as the source language | Found by probing phrasings: "…Спасибо.", "содержимое буфера обмена", "английский текст" |
| Three validator changes for translations | The bench: right answers rejected |
| Accessibility is read at key press even with the language model off | So "переведи это" over a visible selection with no model shows the notice instead of typing over the selection |
| The warm-up runs only when the built-in model is not loaded | Otherwise it would evict translate everything's cached prompt |
| No tag in the recording stages, only in the model stage | The action is known after Whisper; the stage before the model lasts milliseconds unless ⌘C runs |

## Checked

- `swift test`: 264 tests pass (247 on `main`). `VoiceActionsTests`: 15 tests; the corpus is
  **89 utterances that must be actions** (the owner's phrases, Russian and English, polite forms,
  named sources in both orders, pointers, implied selections, 18 target languages among them,
  "и отправь", other instructions) and **50 that must stay dictations**, 46 of them checked with
  and without a selection (chat messages, instructions to coding agents about selections and the
  clipboard, pointers as determiners, "на карту", clause words, two sources, too long, voice
  commands, instructions with nothing selected). All pass. Plus: every one of Whisper's 99
  languages by its English name and Russian name in three cases; explicit sources independent of
  the selection at key press; the instruction without the send; voice commands off; the default
  target; the translation request; the history field, decoding and stats; the setting; speed.
  `RewriteTests`: 2 new tests for the validator changes.
- `xcodebuild` Debug into `build/dev`: builds; warnings are the ones `main` has (AudioCapture,
  AudioFileLoader, ProjectScanner, MLX Metal headers, AppIntents metadata).
- Strings: all 410 keys the compiler extracted are in the catalog with Russian.
- `--snapshot-overlays` into `build/dev/snapshots` and, with `-AppleLanguages (ru)`,
  `build/dev/snapshots-ru`: the tag fits in the island and the pill in both languages ("Буфер
  обмена → ES" is the longest); the notice renders. Nothing was put on screen.
- `--show-main text` (English, engine off) and `--show-main text --show-language-model builtIn`
  (Russian), captured by window id with `screencapture -l`, with a temporary, uncommitted scroll
  anchor to bring the bottom panel into view: the row, its dimmed state and both details.

### Bench: the built-in model

`vm-smart rewrite Bench/action-corpus.txt` (Release, Qwen3 4B Instruct 2507 4-bit, the downloaded
model read in place). Six texts: three Russian (a reminder with a date and time, a dev message with
`useEffect` and `src/app.tsx`, a chat message), two English (product copy, a deploy message with a
URL and `vercel.json`), one short Russian line. After the validator changes:

| Request | Accepted | Mean time | Notes |
|---|---|---|---|
| Translation → Spanish | 5/6 | 1.9 s | The rejection is real: `src/app.tsx` became `app.tsx`. Meaning slips the check cannot see: "Напоминаю" → "Me recordó" (it reminded me), "до среды" → "hasta el miércoles", "до вечера" → "antes de la medianoche" |
| Translation → English | 6/6 | 1.2 s | Good throughout; "3 раза" → "three times" (was rejected before the change) |
| Translation → Russian | 6/6 | 1.5 s | Good; "4 GB" → "4 ГБ" (was rejected before) |
| "Переведи выделенное на испанский и сделай вежливее" (instruction path) | 6/6 | 2.1 s | All Spanish and more polite; one answer made up a fact ("now it runs only once") and dropped `src/`: the instruction path checks length only |
| "Сократи выделенный текст до одного предложения" | 6/6 | 1.0 s | English text stayed English; one answer had two sentences |

Before the validator changes, Spanish 4/6 ("double-check"), English 5/6, Russian 5/6. First call
after loading about 0.6 s to the first token, then about 0.2 s with the system prompt cached. The
instruction path's invented fact is the reason a plain translation goes through the translation
request and its checks.

## Not checked

1. **A real dictation.** A plain launch would take over the owner's settings and history, and
   preview launches don't record. Detection and the validator are covered by tests; the
   controller path was built and read through, not run.
2. **The Accessibility read at key press** in real apps: which apps answer, the 0.25 s timeout
   against a busy app, and that a password field gives nothing.
3. **The ⌘C fallback** in terminals and Electron apps for a named or pointed selection.
4. **Delivery**: paste over the selection, the card, clipboard mode, Return after "отправь".
5. **Ollama and LM Studio** with actions; only the built-in model was benched.

## Known limits

- **Terminals keep selections.** Text left selected in Terminal counts as a selection if the
  terminal answers Accessibility, so "переведи на английский" dictated to Claude Code over it is
  an action.
- **VS Code copies the current line** on ⌘C with nothing selected: "translate this" there with
  nothing selected runs on that line (same as the Edit selection shortcut).
- **Long texts** can hit the model's time limit (20 s by default); the source is cut at 6000
  characters, like the selection of 003.
- **"Nothing selected" and "Clipboard is empty" drop the words**: no history record is written for
  a notice.
- **The history row has no tag** for an action yet: `HistorySection` was left alone while 007
  reworks it. The record carries `action` for it.
- **Inside an action** snippet phrases are words and only a trailing "отправь" acts.
- **The translation prompt still calls the text a dictation**; the model translates it all the
  same and the cached prompt is shared with translate everything.
- **A 4B model's meaning slips** in translation (see the bench) are not caught by any check.
