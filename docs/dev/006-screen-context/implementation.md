# 006 · Screen context — Implementation

**Review:** waiting for the owner. No dictation has run through the app with a real window yet;
what was and was not checked is listed at the end.

## What was built

### Terms (`VMCore`)

- **`SoundKey`** turns a word in either script into sound classes, one ASCII letter each: vowels
  collapse into `a`; г/g/j/дж are `g`; с/з/s/z are `s`; ш/щ/ж/sh and the English "tion" are `S`;
  ч/ch/tch are `C`; the English th is `T`, near т, с, з and ф. An English final e after a consonant
  becomes `e`, a vowel that costs 0.1 to add, drop or swap, since it is silent in "case" and
  sounded in "readme". Identifiers are keyed part by part. The distance is a weighted edit
  distance: a vowel or a voicing pair costs half, anything else one.
- **`ScreenTerms.extract`** keeps identifiers of two parts or more, file names with a known
  extension (and their stem when it is an identifier), @handles, and capitalised Latin names of five
  letters or more that are not everyday English. URLs, e-mail addresses, hashes, prose with hyphens
  ("built-in") and terms the built-in dictionary already spells are left out. The focused field and
  the title weigh three times the rest; then frequency; then length. 80 terms at most.
- **`ScreenTermMatcher`** rewrites a run of one to six heard words to a term when their keys are
  close and the run passes the rules below. It runs in `TextFormatter` right after the dictionary
  rewriter, only when "Terms in Latin script" is on, and its terms are also kept by the lowercase
  style. `DictationPipeline.format` and `TextFormatter.format` take it as an optional parameter.

The matching rules as they ended up, each one there because of a sentence it broke:

| Rule | What it stops |
|---|---|
| The run has at least as many words or camelCase parts as the term has parts | «контроллер» → ControllerView |
| Keys within 10% of the term's key; 20% when a spoken mark or a dot in the heard word backs it | «системный промпт» → systemPrompt |
| A key under 10 sounds allows half a point: one vowel or voicing slip | «из базы» → isBusy |
| An identifier Whisper wrote moves by half a point at most, unless a mark backs it | ModelStore → ModelState |
| A function word only where the term has a part that sounds the same, and 6+ other sounds | «из кода» → isCode |
| The first sound agrees; a first word the match does not need stays out | «дай» swallowed into DictationController |
| In English text only one code-looking token may match | "the language model" → LanguageModel |
| In Russian text a run of Latin words needs every word capitalised | «Language model is off» → LanguageModel |
| A hyphenated English word only matches a kebab-case term | "built-in" → builtIn |
| Two or more capitalised Cyrillic words are a name | «Иван Петров» → ivan_petrov |
| A handle only after «собака», "at" or a written @ | «напиши влад ковальский» → @vlad_kovalskyi |
| A Latin name only from one capitalised Latin word, same key, spelling 75% alike | "Russian" → Reason |

### Reader (`VMSystem/ScreenContextReader`)

- Blocking, bounded, called off the main thread: 80 ms in all, 600 nodes, 20 000 characters, and a
  40 ms messaging timeout per Accessibility call.
- The focused window's title; the focused element unless it is a secure text field: its visible
  character range read with `AXStringForRange`, else 4 000 characters around the caret, else the
  start of its value (never the value of a field longer than 16 000 characters).
- A breadth-first walk of the window: role, subrole, title, description and children in one
  `AXUIElementCopyMultipleAttributeValues` call per element; visible rows and children for lists
  and tables; static text values; other text fields the same way as the focused one. Secure fields
  are skipped with their subtree, and so are scroll bars, images and splitters. Toolbars wait until
  the content is read.
- A web area gives the text in view in one piece: the text marker at the top left of the scroll
  area around it, its index, and 6 000 characters from there. Without that, the page from its start
  when it is longer, or the whole page when it is shorter.
- Text cut out of a longer one loses the word cut in two at either end.
- Every number and range from the other app is checked before arithmetic. The first version
  crashed on a page whose top marker sat on a form field: `AXIndexForTextMarker` answered
  NSNotFound and `index + limit` overflowed.
- Nothing is ever set on the app.

### App

- `AppSettings.screenContext`, on by default.
- `ScreenContextService` (new file) starts a detached read of the front app in `startRecording`,
  right after the target app is taken, unless the switch is off, the dictation is an Edit selection
  one, the front app is saytype itself or the launch is a preview. The window's text never leaves
  that task; only the extracted terms do.
- The final pass: the terms are a field of `Pass` (`screenTerms`, empty by default). `finalize`
  takes them after Whisper has run, so a slow read never delays the decode, and `compose` hands a
  matcher to the pipeline and the terms to backticks. A re-transcription from history makes its
  own pass and gets no screen terms. Cancel drops the read.
- The readout keeps the terms the last dictation took from the screen: the terms in the final text
  that are not in what Whisper wrote.
- **Dictionary → Screen context**: a switch above the Projects panel. Its detail reads
  "Last: DictationController +1", or "Last: 14 terms, none used", or "Terms from the active window"
  before the first dictation. Four strings, with Russian.

### Tools

- `vm-context <pid | app> --marker <text>`: runs the reader on an app's focused window and prints
  timings, sizes and terms; `--text` prints the text. It reads nothing unless the focused window's
  title carries the marker, before and after the read.
- `vm-bench context speech Bench/screen-context/corpus.tsv`: 23 synthetic dictations over two
  screens, each decoded with and without a screen share of the prompt, each formatted with and
  without the matcher. `Bench/screen-context/make-audio.sh` makes the audio.
- `vm-bench context text <files> --terms-from <folder>`: every sentence of the files through the
  matcher with a code folder's identifiers as the screen; prints what changed.

## The merge with 007, 008 and 009

`main` gained audio history, snippets and voice actions while this update was built, and the final
pass was split into `makePass` → `hear` → `compose`. The merge put the screen terms into `Pass` as
a field with a default, so there is one path and no call site changed: a live dictation fills it,
a re-transcription leaves it empty. `compose` uses it; `hear` does not, since the prompt stays as it
is (below).

009 reads the selection through Accessibility at key press as well (`focusedSelection`). The two
reads were left separate: they are gated by two switches, 009's is three calls with a 250 ms
timeout and feeds the voice action decision, and sharing one task would tie that decision to the
screen reader's budget. The overlap is two Accessibility calls.

## Measured

### The reader

`vm-context`, windows opened for the test only, in the background; five reads each.

| App | Title | Focused element | Rest of the window | Time |
|---|---|---|---|---|
| TextEdit, a 700-character file | file name | text area, 698 characters | 13 nodes | 4–55 ms, most under 10 |
| Terminal, the file printed | shell | text area, the 782 characters in view of 1 186 | 12 nodes | 2–45 ms, most under 10 |
| Safari, short page | page title | the address field | 30 nodes; page text 575 characters | 3–41 ms |
| Safari, 257 000-character page | page title | the address field | 6 142 characters from the top of the view | 28–71 ms |
| Safari, page with a password field | page title | none | 42 nodes; the password never read, the text field's value read | 5–26 ms |
| VS Code, own profile | `DictationController.swift — saytype-006-project` | none | 12 nodes, no text | 0.6–5 ms |

- **Terms.** TextEdit and Terminal gave 21–23 terms from the sample file, Safari 21 from the page,
  VS Code two: `DictationController.swift` and `DictationController`.
- **First contact.** The first read of a freshly opened Safari page ran into the deadline with the
  title and the address field only; the next reads were complete. The first read of an app from a
  new process often took 25–70 ms.
- **Electron.** With `AXManualAccessibility` set on the test instance (by a scratch probe, not by
  the reader), VS Code built a tree of 392 nodes about three seconds later. The editor still gave
  no code: "The editor is not accessible at this time. To enable screen reader optimized mode, use
  Shift+Option+F1". So the attribute would help no dictation it is set for, keeps Chromium's
  accessibility on until the app quits, and the code needs VS Code's screen reader mode, which
  changes how the editor behaves. The reader never sets it.

### Extraction and matching

A 23 600-character window (400 lines of code and 60 chat lines) against a 204-word dictation,
release build: 80 terms in 9 ms, the matcher built in 0.9 ms, the dictation matched in 3.8 ms. All
of it runs off the main thread except the match, which is part of formatting.

### Speech

`vm-bench context speech`, 23 dictations by the Milena voice: 15 over a code screen (29 terms),
8 over a chat screen (8 terms). 18 terms expected; 5 dictations are ordinary speech. The owner's
settings: automatic language, their 14 dictionary entries in the 40-token prompt.

| | Terms right | Ordinary dictations changed |
|---|---|---|
| Owner's prompt, as today | 1 of 18 | 0 of 5 |
| Owner's prompt + matcher | **18 of 18** | 0 of 5 |
| Top 3 screen terms first in the prompt | 5 of 18 | 0 of 5 |
| Screen share + matcher | 18 of 18 | 0 of 5 |

What Whisper wrote and what came out, a selection:

| Whisper | Text |
|---|---|
| Поправь диктишн контроллер, чтобы он читал экран. | Поправь DictationController, чтобы он читал экран. |
| Открой project-therms-service.swift. | Открой ProjectTermsService.swift. |
| Добавь тест для термканоника лазер. | Добавь тест для TermCanonicalizer. |
| Где используется MaxRetroAccount. | Где используется MAX_RETRY_COUNT. |
| Напиши Кириллу, что фич-юзер профил падает. | Напиши Кириллу, что fetchUserProfile падает. |
| Проверь из лайдинг в хедере. | Проверь isLoading в хедере. |
| Отметь собака Влад Ковальский в ревью. | Отметь @vlad_kovalskyi в ревью. |
| Переименуй GetUserByAde. | Переименуй getUserById. |
| Поправь контроллер, он плохо читает экран. | unchanged |
| Напиши Ивану Петрову про релиз. | unchanged |
| Системный промпт у модели слишком длинный. | unchanged (systemPrompt on screen) |

**The prompt stays as it is.** A share of three screen terms fixed 4 more terms on its own and none
on top of the matcher, took three of the owner's dictionary entries out of Whisper's bias, and its
pick depends on the ranking guessing what will be said. Decode time was the same either way.

### Ordinary text

`vm-bench context text` over 4 173 sentences (both READMEs, the docs of 001–005 and 007–009, the
bench corpora), with a code folder's identifiers standing in for a screen, five times the real
cap:

| Screen | First version | Final |
|---|---|---|
| SaytypeKit's 356 identifiers | 38 changed (of 2 003 sentences then) | 6 |
| App/Sources' 400 identifiers | — | 1 |

All seven left are an identifier typed in the docs turned into another one that differs only in
case: `historyStore` → `HistoryStore`, `voiceActions` → `VoiceActions`, `modelState` →
`ModelState`, `screenTerms` → `ScreenTerms`, `audioRetention` → `AudioRetention`. That is the case
fix the matcher is meant to make ("GetUserByID" → `getUserById`), applied where two names differ
only in case and just one is on the screen.

## Deviations from the proposal

1. **Time budget 80 ms, messaging timeout 40 ms**, not 60 and 50. Safari's first reads of a page
   ran past 60 ms; the read runs while the user speaks, so the extra 20 ms cost nothing.
2. **Tolerance 10%, not 12%, and more rules.** The proposal's rules rewrote 38 of 2 003 prose
   sentences. The table in "What was built" is what it took to get that to single digits without
   losing a term in the speech bench.
3. **Latin names only from the middle of a sentence**, and matched only when the spelling is also
   75% alike. Headings and buttons ("Refactor …", "Translation Available") were being taken as
   names, and "Russian" has the key of "Reason".
4. **Web text from the view, not the whole page.** The whole-page text of a long page is too big to
   copy; the proposal's length check would have dropped such a page altogether.
5. **The switch sits above Projects**, not next to "Built-in dictionary": the header art occupies
   that corner. The readout says "Last: …" to fit one line in 340 points in both languages.
6. **A case fix of an identifier is allowed.** A rule that left case-only differences alone kept
   the docs' `historyStore`, and lost `GetUserByID` → `getUserById` in the bench. Dictation is the
   case that matters.

## Checked

- `swift test` in `Packages/SaytypeKit`: 327 tests in 54 suites pass, 36 of them new (sound keys,
  extraction, matching with every sentence the first version broke, the pipeline, the setting,
  timings, the reader's word trimming and number checks).
- `xcodebuild … clean build` after the merge: builds; the only warnings are the old ones in
  `AudioCapture`, `AudioFileLoader` and `ProjectScanner`.
- `--snapshot-main dictionary` in English and Russian, rendered to files: the switch and its
  readout fit, clear of the header art.
- The reader against TextEdit, Terminal, Safari and a separate VS Code profile, as above, with a
  password page. No window of the owner's was read: `vm-context` refuses any window without the
  marker, and the scratch probes only printed marked titles.

## Not checked

- **A live dictation in the app.** A plain launch of the dev build would take over the owner's
  settings and history, and preview launches never record. The path from key press to text is
  covered by the reader runs, the bench through the real engine and pipeline, and the build.
- **The owner's apps.** iTerm2, Cursor, Telegram and Chrome were not read: they hold the owner's
  work and chats. iTerm2 is expected to expose its session as a text area the way Terminal does, and
  Chrome its pages through text markers the way Safari does; if Chrome lacks the view-start call,
  the reader takes the page from its start. Neither is confirmed, and Telegram is unknown.
- **A real voice.** The bench is synthetic Russian speech; English terms in a real voice may come
  out in other shapes.
- **An app in front.** The test windows were in the background, where App Nap slows their answers;
  the app in front at key press should answer faster.

## Known limits

- Cursor, VS Code and other Electron apps give their window title only.
- The first read of a freshly loaded web page may run out of time and give the title and the
  focused field only.
- Adjacent labels in web text can run together into noise terms ("GitYesAlwaysNever" from VS Code's
  notifications with accessibility on); they take room in the 80 but match nothing said.
- Two identifiers that differ only in case: the one on the screen wins.
- Russian names are not taken: inflection ("Кириллу") makes rewriting them unsafe.
