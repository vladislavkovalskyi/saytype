# 006 · Screen context — Proposal

**Review:** follows the owner's approval of 23.09.2026; the design details were decided during
the work, as the owner asked. Deviations during implementation go to
[`implementation.md`](implementation.md).

## In short

At key press a background task reads the window in front through Accessibility, keeps the rare
terms of its text and drops the text. After recognition, words that sound like one of those terms
are rewritten to its on-screen spelling, the same way project identifiers are fixed today but by
sound, so Cyrillic ("диктишн контроллер") and near-miss Latin ("ScreenContextRider") both land on
`DictationController` and `ScreenContextReader`. The Whisper prompt stays as it is unless the
bench shows a share of it is worth taking from the owner's dictionary.

## What the first probes showed

Before the design, two quick probes (scratch code, not committed).

**What apps expose.** Windows opened for the test only, read by process id, second and later
reads:

| App | Window title | Focused element | Rest of the window | Time |
|---|---|---|---|---|
| TextEdit | file name | `AXTextArea`, visible range and text | 13 nodes | 1–2 ms |
| Terminal | shell and size | `AXTextArea` with the whole scrollback and a visible range | 11 nodes | 1–3 ms |
| Safari | page title | the address field (the page was opened in the background) | 56 nodes; the page text in one call through text markers | 4 ms |
| VS Code (Electron) | `DictationController.swift — project` | none | 12 nodes, no text | 3–6 ms |

The first read of an app from a new process took 40–70 ms: Accessibility sets up the connection
on the first call. VS Code builds its tree only after `AXManualAccessibility` is set, a few
seconds later, and even then the editor says "The editor is not accessible at this time. To
enable screen reader optimized mode, use Shift+Option+F1": the code itself stays hidden unless
VS Code switches into its screen reader mode.

**How Whisper writes on-screen names.** Fifteen synthetic Russian dictations (the Milena voice)
through the app's engine with the owner's settings (automatic language, their 14 dictionary
entries in the 40-token prompt). Ten names came out wrong, in three shapes:

| Said | Whisper wrote | On screen |
|---|---|---|
| диктейшн контроллер | диктишн контроллер | `DictationController` |
| скрин контекст ридер | ScreenContextRider | `ScreenContextReader` |
| юз ауф сешн | useAufSession | `useAuthSession` |
| терм канонекалайзер | термканоника лазер | `TermCanonicalizer` |
| макс ретрай каунт | MaxRetroAccount | `MAX_RETRY_COUNT` |
| фетч юзер профайл | фич-юзер профил | `fetchUserProfile` |
| юзер профайл кард точка тэ эс икс | UserProfileCart.tsx | `UserProfileCard.tsx` |
| проджект термс сервис точка свифт | project-therms-service.swift | `ProjectTermsService.swift` |
| ридми точка эм дэ | ridme.md | `README.md` |
| виспер кит энджин, фокус инспектор | WhisperKit Engine, Focus Inspector | `WhisperKitEngine`, `FocusInspector` |

With the screen terms in place of the owner's dictionary in the prompt, the six terms that fit in
40 tokens came out exact, the ones that did not fit mostly did not. Two conclusions: the terms
must be matched by sound, not by letters, because the existing project-term matching only fixes
spacing and case; and the prompt helps only the few terms that fit, which are exactly the owner's
dictionary's tokens.

## Design

### Reading (`VMSystem/ScreenContextReader`)

Synchronous, called off the main thread, with a deadline and a node cap:

1. The application element of the front app, with a messaging timeout of 50 ms per call so a
   hung app cannot hold the reader.
2. The focused window's title.
3. The focused element, unless it is a secure text field. Its visible character range, read
   with `AXStringForRange`; without a visible range, a window around the caret; without either,
   its value up to a limit. Terminals and text editors give their screen here.
4. A breadth-first walk of the focused window: role, value, title and description of each node
   in one `AXUIElementCopyMultipleAttributeValues` call; visible children for lists, tables and
   outlines; secure fields are skipped with their subtree. A web area gives its text through
   `AXTextMarkerRangeForUIElement` and `AXStringForTextMarkerRange`, bounded by length, and is
   not walked further.
5. Limits: 60 ms in all, 600 nodes, 20 000 characters. Whatever was read by the deadline is used.

The reader never sets an attribute. `AXManualAccessibility` and `AXEnhancedUserInterface` are left
alone: in VS Code the first builds the tree seconds later, so it would only help the next
dictation, it keeps Chromium's accessibility on until the app quits (memory and CPU in every
Electron app), and the editor still hides its code unless it switches into screen reader mode,
which changes how the editor behaves. Electron apps give their window title, which in Cursor and
VS Code is the file and the project.

### Terms (`VMCore/ScreenTerms`)

Pure and unit-tested. From the title, the focused text and the visible text it keeps:

- **Identifiers** of two parts or more: `DictationController`, `useAuthSession`,
  `MAX_RETRY_COUNT`, `react-query`, `iTerm`.
- **File names** with a known extension (`ProjectTermsService.swift`, `README.md`), taken from
  paths too, plus the stem when the stem is an identifier.
- **@handles**: `@vlad_kovalskyi`.
- **Latin names**: capitalised words of five letters or more that are not ordinary English words
  and not already in the built-in dictionary.

Left out: URLs, e-mail addresses, hashes and ids (long runs with digits), terms the built-in
dictionary already spells, words of one or two letters, anything over 60 characters. Russian
names are not taken: Russian inflects them ("Кириллу", "Кирилла"), so rewriting a heard form to
the on-screen one would break the grammar, and Whisper spells common Russian names well.

Ranking: the focused text and the title weigh three times the rest of the window; then how often
a term occurs; then length. 80 terms at most.

### Matching (`VMCore/ScreenTermMatcher`)

A sound key turns a word in either script into a rough transcription, the way a Russian speaker
says an English word: `tion` → `шн`, `c` → `к` or `с`, `ph` → `ф`, `j` and `дж` and `г` into one
class, `с` and `з` into one class, silent final `e` dropped, doubled letters and runs of vowels
collapsed into one vowel mark. "диктишн контроллер" and `DictationController` get the same key;
so do "термканоника лазер" and `TermCanonicalizer`, "MaxRetroAccount" and `MAX_RETRY_COUNT`.

A run of one to six words matches a term when:

- the keys differ by at most 12% after a weighted edit distance (a vowel or a voiced/voiceless
  pair costs half), and the key has at least six sounds;
- the first sound agrees;
- the run has no function word ("и", "в", "что", "the", "and") unless the term has a short part
  at that place (`isLoading` ← "из лоадинг");
- the run is not two or more capitalised Cyrillic words, which is a person's name;
- words between the parts may be "точка", "dot", "слэш", "slash", "андерскор", "underscore" when
  the term has that mark there.

The longest run wins, then the closest key. Punctuation around the run is kept. A handle matches
only after "собака", "at" or "@", and comes out as `@handle`, so "напиши Владу" never turns into a
nickname. A Latin name replaces a single capitalised Latin word only when the keys are equal
("Kovalsky" → `Kovalskyi`).

The matcher runs in `TextFormatter` right after the dictionary rewriter, so the user's own entries
and the built-in dictionary win, and it applies to this dictation only. A single-part word is
never rewritten from Cyrillic: "контроллер", "проект", "сервис" stay Russian words.

### Whisper prompt

Decided by the bench (stage 4 of the plan): the owner's prompt as it is with the matcher, against
the same prompt with the top two or three screen terms put first. A share of the 40 tokens is
taken only if it wins dictations the matcher cannot fix. The cap does not change.

### Controller

- `startRecording`: when the switch is on and the dictation is not an Edit selection one, a
  detached task reads the front app's window and extracts the terms. The recording starts
  without waiting for it.
- `finalize`: awaits the task (it is long done by the time the key goes up) and passes the terms
  to `DictationPipeline.format`, which hands a matcher to `TextFormatter`. Terms also go to the
  backticks of developer modes and to the terms kept in lowercase style.
- A cancelled or ended dictation drops the task and its terms. The only thing kept is the list of
  terms the last dictation changed, for the readout.

### Settings

`AppSettings.screenContext`, on by default. The switch sits in the Dictionary section, next to
"Built-in dictionary", titled "Screen context"; its detail line reads the terms the last dictation
took from the screen, or "Terms from the active window" before the first one.

## Privacy

- The text is read from the window in front, only when a dictation starts, and only with the
  Accessibility permission the app already holds.
- Secure text fields are skipped; their values are never requested.
- The text lives inside the reading task. Only the extracted terms leave it, and they live in
  memory until the next dictation. Nothing is written to disk, to the history or to a log.
- The debug command reads only windows whose title carries a marker given on its command line.

## Rejected

- **OCR of a screenshot.** Needs the Screen Recording permission, costs hundreds of milliseconds,
  and reads what Accessibility reads anyway for most apps.
- **Enabling Electron accessibility.** See Reading.
- **Screen terms as project terms.** `TermCanonicalizer` matches letters, which covers
  "Focus Inspector" but none of the Cyrillic or near-miss forms above. Adding the terms to the
  cached rewriter's key would also rebuild it, a thousand terms and a regex per entry, on every
  dictation.
- **Reading in `finalize`.** By then the user may have switched windows, and the read would add to
  the time between key release and text.

## Risks

- **False rewrites.** A Russian phrase that sounds like an on-screen identifier. The limits above
  (two parts, six sounds, 12%, first sound, no function words, no names) are tested against
  sentences of ordinary speech with a screen full of terms.
- **Busy apps.** A hung app costs at most the deadline plus one messaging timeout, off the main
  thread.
- **First read of an app.** The 40–70 ms setup may eat the budget once per app; that dictation
  gets fewer terms.
- **Terminals.** Terminal and iTerm2 give a lot of text; a long scrollback is cut to the visible
  range.
