# 008 · Voice snippets — Proposal

**Review:** decided by the implementing agent under the owner's go-ahead of 23.09.2026; waits for
the owner. Deviations found while building go to [`implementation.md`](implementation.md).

## In short

Snippets live in `AppSettings`. After Whisper, the transcript is split at voice commands as
today; in the text between commands each trigger phrase is replaced by a marker `⟦1⟧`, `⟦2⟧`…
The formatter, smart structure, backticks and the language model see only the marker. At the
very end the markers become the snippets' text with the variables filled in, and the dictation
goes out the usual way. A dictation that is nothing but snippets skips every model.

## Model

```swift
public struct Snippet: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// "мой имейл", "my email". Any of them inserts the text.
    public var triggers: [String]
    /// Inserted as written; {clipboard}, {selection}, {date} and {time} are filled in.
    public var text: String
}

// AppSettings
public var snippets: [Snippet] = []
```

`AppSettings.init(from:)` already decodes field by field with `decodeIfPresent`, so settings
saved by 0.3.0 get an empty list. `Snippet` decodes the same way, so a snippet saved by a later
version with more fields still loads. No starter snippets ship: a sample address would fire on
"мой имейл" and insert something wrong.

The order of the list matters in one place: when two snippets share a phrase, the one higher in
the list wins.

## Matching

`SnippetMatcher` runs on the raw transcript, inside `DictationPipeline.format`.

1. `VoiceCommands.parse` splits the transcript first, exactly as now. Snippets are looked up only
   in the `.text` pieces, so a command always wins, including a snippet phrase that is a command
   ("отправь"). With voice commands off, the whole transcript is one text piece.
2. A word is a run of letters and digits. Both the trigger and the transcript are cut into words
   and folded: lowercase, without diacritics (ё = е), so case and Whisper's marks do not matter.
3. A trigger matches a run of consecutive transcript words whose letters, joined, equal the
   trigger's letters, joined. That is what makes "шаблон ревью", "Шаблон, ревью", "шаблон-ревью"
   and "шаблонревью" all match. Boundaries come for free: the run starts and ends on whole
   words, so "мой имейлы" does not match "мой имейл".
4. A match never spans the end of a sentence (`.`, `!`, `?`, `…`) or a line break: "это мой.
   Имейл потом" is not a trigger.
5. Left to right, at each word the longest trigger wins; matches do not overlap. Triggers
   shorter than two letters are ignored so a stray "я" never fires.

Matching is on what Whisper wrote, before dictionary spellings, so a phrase is written the way it
is heard. When Whisper hears the same words two ways ("шаблон ревью", "шаблон review"), the
snippet gets two phrases.

## Markers through the formatter

The matched words, including punctuation between them, are replaced by `⟦n⟧` (U+27E6, U+27E7)
where `n` is the snippet's position in the result's list. Punctuation around the match stays, so
"Шаблон ревью." becomes "⟦1⟧.", and the formatter punctuates the sentence the marker sits in.

The marker is chosen so the deterministic steps leave it alone: it has no letters (letter case,
dictionary, term canonicalizer and backticks do nothing to it), no spoken-code head words, and the
punctuation steps only strip `,.;:!?…` at word ends. Tests pin that for every text style.

`PipelineResult` gets the list:

```swift
/// Snippets the text holds as ⟦1⟧, ⟦2⟧…, in that order.
public var snippets: [Snippet]
```

A single-piece transcript with a marker loses paragraph breaks by pause: `Paragraphs.split`
checks that the words still match the timings, and they no longer do. Snippet dictations are
short, so this is accepted.

## Putting the text in

`SnippetPlacement.resolve(text, texts:)` replaces each marker with the snippet's text, variables
filled in, and tidies the edges:

- **A line that is only snippets** (after removing markers, no letters or digits are left): the
  marks the formatter put around them go away, so "мой имейл" gives the address exactly, not
  "address.".
- **A snippet inside a sentence:** the sentence keeps its punctuation. If the snippet ends with
  `.`, `!`, `?` or `…` and the formatter put `.`, `,`, `;` or `:` right after the marker, that
  mark is dropped ("bugs..", "bugs.,"). A snippet that starts or ends with a line break takes the
  space next to it.
- **An empty snippet** (say `{clipboard}` with nothing copied): the marker goes, and so does the
  double space it leaves.
- The snippet's own leading and trailing whitespace is trimmed; everything inside is verbatim.
  A trailing newline typed by accident in the editor must not send a line in a terminal.

## Language model steps

Three cases, decided on the text with markers:

1. **Only snippets** (plus voice commands): no rewrite, no translation, no smart structure, no
   backticks. The dictation is the snippets. The model never sees the trigger, so it cannot
   translate it first.
2. **Snippets inside longer speech, and the mode or "translate everything" calls the model:** the
   model gets the text with markers. The user message, right before the `<dictation>` tag, says:
   `⟦1⟧ marks text that is inserted later. Keep every such marker exactly once, as it is.` The
   rule sits in the user message, not the system prompt, so the cached system prompt of the
   built-in model is reused. `RewriteValidator.check` rejects an answer in which any marker is
   missing, repeated, changed or invented. A rejected answer already falls back to the formatted
   text, so the dictation is inserted without the model and the snippet is kept.
3. **Snippets inside longer speech, no model:** smart structure and backticks run as usual; they
   only move or wrap words, and the marker is not a word they touch.

Trade-off of case 2: when the model drops the marker, the words around the snippet stay
untranslated for that dictation. Losing a translation is recoverable, losing a saved prompt is
not.

**Whisper translating on its own** (no language model, "translate everything" into English on a
large-v3 model): the transcript arrives already in English, so a Russian trigger cannot match.
Fixing that needs a second, untranslated Whisper pass inside `finalize`, which 005 is rewriting.
Instead the snippet can carry an English phrase too ("review template"). Written down in the
README.

## Variables

`SnippetVariables.expand(text, values:)` fills `{clipboard}`, `{selection}`, `{date}` and
`{time}`. Names are matched without regard to case; anything else in braces is left as it is.

Values are read in the app at delivery, and only for variables a matched snippet uses:

- **`{clipboard}`** — `NSPasteboard.general.string(forType: .string)`, read first. Delivery
  pastes through the clipboard, so it has to be read before the paste.
- **`{selection}`** — `SelectionReader.read()`. It asks Accessibility first, which has no side
  effects; apps that do not answer (terminals, many Electron apps) get a ⌘C and the clipboard is
  put back. So it is read only when a snippet uses it, after the clipboard, while the target app
  is still in front and before the paste replaces the selection. In an Edit selection dictation
  the selection was already read when the shortcut was pressed, and that text is used.
- **`{date}`, `{time}`** — `Date.now` formatted with `Locale.current`: `.long` date
  ("23 сентября 2026 г.", "September 23, 2026") and `.shortened` time ("14:05", "2:05 PM").

With paste output, the paste replaces whatever is selected, so `{selection}` wraps the selection
in the template. That is the natural reading of "review {selection}".

## Where it hooks in

`DictationController.finalize` is being rewritten by 005. It gets exactly one new line, right
after the transcript is ready:

```swift
if await finishWithSnippets(transcript, duration: duration, mode: mode, settings: value,
                            projectTerms: projectTerms, modelTranslates: translateTo != nil && !whisperTranslates) { return }
```

`finishWithSnippets` returns `false` at once when no snippet phrase is in the transcript (a
cheap scan), and the old path runs untouched. Otherwise it runs its own copy of the tail of
`finalize`: format with markers, the Edit selection branch, the model or smart structure,
backticks, then variables, placement, history and delivery. The copy is about 30 lines. Sharing
the tail would mean moving lines 005 is editing; the copy is the price of a clean merge, and
`implementation.md` lists what to keep in step.

`deliver` learns which snippet texts the card holds, for the mark in the card.

## Main window

A **Snippets** section in the rail between Dictionary and History, built like Modes:

```
┌ list ──────────────┐ ┌ editor ─────────────────────────────────────────┐
│ мой имейл          │ │ Phrases   [мой имейл ✕] [my email ✕] [+ Add phrase]│
│ v@example.com      │ │                                                  │
│ шаблон ревью     • │ │ Text      ┌──────────────────────────────────┐   │
│ Review the diff…   │ │           │ Review {selection} for bugs…     │   │
│                    │ │           └──────────────────────────────────┘   │
│ [+ New snippet]    │ │ Variables {clipboard} {selection} {date} {time}  │
└────────────────────┘ └──────────────────────────────────────────────────┘
```

- The list shows each snippet's first phrase and the first line of its text.
- The editor has phrase chips with ✕, an inline field that adds a phrase on Return, the text in a
  multi-line field in the mono font, and variable chips that append the variable. Next to
  `{date}` and `{time}` the chip shows today's value.
- A phrase that a voice command takes, or that an earlier snippet already has, is dimmed and
  tagged `command` or `duplicate`.
- Delete sits in the editor's header, as in Modes. A snippet left with no phrase and no text is
  removed when the section closes.
- The rail object is a new glass "{ }" rendered by `design/3d/glass.py` in the green world. If
  the render does not come out right, the section borrows an existing object and says so in
  `implementation.md`.
- All strings are English with Russian in `Localizable.xcstrings`.

Preview launches (`--show-main snippets`) get three sample snippets, so screenshots never show
the owner's own.

## Card mark

The card keeps the snippet texts it holds; the text view gives each one a faint background. It
is a search by string, so an edit that changes the snippet drops the mark by itself. Cheap
enough to do.

## Alternatives

- **Format the pieces around a snippet separately and glue.** "проверь" and "для этого файла"
  would come out as two sentences ("Проверь. Для этого файла."). Markers keep one sentence.
- **Insert the snippet before the model and ask it not to touch it.** A 4B model translating
  a 300-word template is slow, and nothing proves it kept the text. A marker is three
  characters and is checked exactly.
- **Match on the formatted text.** The dictionary and the canonicalizer change words first
  ("ревью" may become a term), so the phrase would have to be written the way the formatter
  writes it. Raw text is what the user hears themselves say.
