# 008 · Voice snippets — Implementation

**Review:** waits for the owner. What was checked, and how, is at the end.

## What was built

### Model and settings (`VMCore/Snippets.swift`, `AppSettings`)

```swift
public struct Snippet: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var triggers: [String]
    public var text: String
}
// AppSettings
public var snippets: [Snippet] = []
```

`AppSettings.init(from:)` decodes `snippets` with `decodeIfPresent`, so 0.3.0 settings load with
an empty list. `Snippet` decodes field by field too. No snippets ship by default.

### Matching (`SnippetMatcher`)

As proposed: words are runs of letters and digits, folded without case, diacritics and width; a
trigger matches whole consecutive words whose letters join into the trigger's letters; a match
never crosses `.`, `!`, `?` or `…` followed by a space, or a line break (so `Next.js` still
matches); the longest trigger wins at each word, the higher snippet wins a shared trigger;
triggers under two letters are ignored.

`DictationPipeline.format(…, snippets:)` splits voice commands first and runs the matcher only on
the text pieces, so commands always win. Without the `snippets` argument it is byte for byte the
old function. `PipelineResult.snippets` lists what the markers stand for.

### Placement and variables

`SnippetPlacement.resolve` and `SnippetVariables.expand` as in the proposal, plus one rule found
while writing the model path: backticks a model puts around a marker are dropped, since the
snippet is not code. `Snippet.insertion(_:)` is expansion plus trimming of the edges.

`{date}` is `.long` and `{time}` `.shortened`, both with `Locale.current`: "23 сентября 2026 г." /
"22:59" with a Russian interface, "23 September 2026" / "22:58" with English on the owner's Mac.

### Language model

- `RewriteRequest.userMessage` adds one line before the `<dictation>` tag when the text holds a
  marker: `⟦1⟧, ⟦2⟧ and so on mark text that is inserted later. Keep every marker exactly once
  and exactly as written, where it belongs in the sentence.` The system prompt is unchanged, so
  the built-in model's prompt cache still hits.
- `RewriteValidator.check` rejects first thing an answer whose markers differ from the input's:
  lost (`dropped ⟦1⟧`), doubled or made up (`invented ⟦1⟧`), or mangled (`⟦ 1 ⟧`). The rejection
  shows in Model → last run like any other.

### Delivery (`DictationController`)

Dictations with and without snippets go through the one `finalize`:

```swift
let formatted = DictationPipeline.format(transcript, …, snippets: value.snippets)   // markers
if let selection { /* instruction = placingSnippets(…, selection:) → editSelection */ }
let onlySnippets = SnippetMarker.isOnlyMarkers(text)
if !onlySnippets, <mode or translation needs the model>, … { rewrite }               // marker rule + check
else if !onlySnippets { smart structure }
if mode.backticks { Backticks.wrap }                                                 // markers have no letters
let placed = await placingSnippets(formatted.snippets, in: text)                     // variables + placement
… history record with placed.text …
await deliver(text, …, snippets: placed.snippets)                                    // card mark
```

1. `format` gets `value.snippets`; a dictation that says no phrase comes out exactly as before
   (tested).
2. Edit selection: the instruction gets the snippets' text in place, `{selection}` is the
   selection the shortcut already read.
3. Nothing but markers: no model, no smart structure; backticks have nothing to wrap.
4. Otherwise the model (with the marker rule and check) or smart structure, then backticks.
5. `placingSnippets` returns the text unchanged, reading nothing, when there are no snippets.
   Otherwise it reads variables only for snippets whose marker is still in the text (a snippet
   removed by "удали последнее предложение" reads nothing) and only the variables they use: the
   clipboard first, then `SelectionReader.read()`.
6. History keeps the final text in `text` and the spoken trigger in `raw`; `deliver` keeps the
   snippet texts in `cardSnippets` for the card.

The first version ran snippet dictations through a copy of the tail of `finalize`
(`finishWithSnippets`) to leave `finalize` alone while 005 rewrote it. After 005 landed, the copy
was folded back: one path, so 006 and 007 have one place to change.

### Card mark

`OverlayCard.marking` gives the snippet text in the card a background of the ink colour at 16 %.
It searches the card's text for each snippet in order, so an edit that changes the snippet drops
its mark. `--snapshot-overlays` got a `9d-card-snippet` shot.

### Main window

A **Snippets** section between Dictionary and History, green world, built like Modes (screenshots
below were taken from preview launches with sample data):

- list: first phrase and the first line of the text that has words in it (a code fence says
  nothing); a count in the header; "New snippet" at the bottom;
- editor: phrase chips with ✕ and an inline field that adds on Return or when focus leaves;
  the text in JetBrains Mono; variable chips that insert at the caret (`TextEditor(text:selection:)`),
  with today's date and the current time next to `{date}` and `{time}`, refreshed every minute;
- a phrase that never fires is dimmed and tagged: `voice command` (only while voice commands are
  on), `duplicate` (a higher snippet or an earlier phrase has the same words), `too short`. The
  rules live in `Snippet.issue(trigger:of:in:voiceCommands:)` and are tested;
- a snippet with no phrase and no text is removed when the section closes; "New snippet" reuses
  an untouched blank one;
- the editor looks its snippet up by id on every change, so a delete during the animation cannot
  hit a stale index.

The rail object is new: `obj_braces` in `design/3d/glass.py` — rounded glass braces (SF Rounded)
with a neon core and two glowing lines, green like the lock. Rendered with the full-quality
settings and exported with `export_app.py --glass` into `ObjectBraces.imageset`.
`smooth_text` got an optional `font`.

Preview launches seed four sample snippets in `AppModel.start`; preview settings are never saved.

Strings: 17 new keys in `Localizable.xcstrings`, each with Russian. Checked against the strings
the compiler extracted from every source file: none missing.

## Deviations from the proposal

| What | Why |
|---|---|
| Tag `too short` besides `command` and `duplicate` | A one-letter phrase is silently ignored by the matcher; the editor should say so |
| Backticks around a marker are dropped | Prompt-style rewrites put identifiers in backticks and may treat the marker as one |
| Variables read only for snippets still in the text | "удали последнее предложение" can remove a marker; reading the selection for it would send a ⌘C for nothing |
| List preview skips lines without words | The first line of a fenced snippet is "```" |
| No copy of the tail of `finalize`; snippets run through `finalize` itself | 005 landed first, so the one-line hook was no longer needed to keep its merge clean, and a copy would drift |

## Checked

- `swift test` after merging 005: 247 tests pass (37 of them in `SnippetsTests`): matching (case,
  punctuation, hyphens, joined and split words, ё, word boundaries, sentence ends, `Next.js`,
  longest trigger, list order, short triggers, repeats), pipeline and placement (alone, inside a
  sentence, period after a sentence-ending snippet, empty snippet, trimmed edges, several in a
  line, every punctuation style and letter case, spoken code and backticks, paragraphs from
  segment gaps),
  verbatim text through chat style, fillers, word filters, dictionary and censoring, voice
  command precedence and "отправь", variables (values, locale, unknown braces, case), markers
  (only-markers, mismatches), the model prompt and the validator, editor tags, and settings
  (0.3.0 JSON, round trip, snippets with missing or unknown fields).
- **The built-in model keeps the markers.** `vm-smart rewrite Bench/snippet-corpus.txt` (Release
  build, Qwen3 4B Instruct 2507 4-bit, read from the downloaded model), eight dictations with one
  or two markers, the answers checked by the new validator:

  | Style | Markers kept | Notes |
  |---|---|---|
  | translate | 8/8 | "Check ⟦1⟧ for this file.", "…send me a message on ⟦2⟧ if anything falls." |
  | cleaner | 8/8 | |
  | prompt | 7/8 | dropped the marker that opened the dictation ("⟦1⟧ Начни с src/app.tsx…") |
  | commit | 5/8 | twice turned `⟦1⟧` into a bare "1"; the validator caught every one |

  Translate everything, the owner's setting, is the case that matters, and it held. Each
  rejection falls back to the text without the model, with the snippet in place. Speed did not
  change: 0.5–1.5 s per dictation, the system prompt stayed cached.
- `xcodebuild build` (Debug, `build/dev`, after merging 005 and folding the path): builds; the
  warnings are exactly the ones main has (AudioCapture, AudioFileLoader, ProjectScanner, MLX's
  Metal headers).
- `--snapshot-overlays build/dev/snapshots`: `island-9d-card-snippet.png` and
  `pill-9d-card-snippet.png` show the mark; nothing is put on screen.
- `--show-main snippets` in English and Russian, captured with `screencapture -l`: layout
  matches Modes, the rail object sits with the others, all strings translated.

## Not checked

1. **A real dictation.** A plain launch of the dev build would read and write the owner's
   settings and history, and preview launches do not record. The path from transcript to final
   text is covered by the pipeline tests; the calls around them in `finalize` were only built
   and read.
2. **`{selection}` and `{clipboard}` in other apps.** `SelectionReader` is the one the Edit
   selection shortcut uses and was checked live in 003; here it is only called.
3. **Clicks in the editor.** Preview windows were only captured, not clicked: adding and
   removing phrases, the tags and inserting a variable at the caret were not exercised on screen.

## Known limits

- Whisper translating on its own (no language model, translate everything into English on a
  large-v3 model) hands over English text, so a Russian phrase cannot match. The README says to
  add an English phrase.
- A dictation with a snippet and no voice command loses paragraph breaks by pause: the segments
  no longer match the text with a marker in it.
- With a model and a snippet inside longer speech, a lost marker means the whole dictation goes
  in without the model, untranslated when translate everything is on.
- Editing the snippet part of a card can teach the dictionary only if the edit looks like a
  spelling fix of words Whisper heard; snippet words were never heard, so in practice nothing is
  learned from them.
- The README tour and the Settings table have no Snippets screenshot yet; `design/media` needs
  window captures with shadow, which the owner makes.
