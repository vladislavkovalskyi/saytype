# 009 · Voice actions over the selection and the clipboard — Proposal

**Review:** decided by the implementing agent under the owner's go-ahead of 24.09.2026; waits for
the owner. Deviations found while building go to [`implementation.md`](implementation.md).

## In short

When the record key goes down, saytype reads the text selected in the app in front through
Accessibility, off the main thread, and keeps it in memory for this one dictation. When Whisper
has the transcript, and before voice commands, snippets, modes or translate everything touch it,
a deterministic parser in VMCore decides whether the words are an instruction over a source: the
selection or the clipboard. If they are, the language model carries the instruction out over
that text and the result is delivered by the output mode, like the Edit selection shortcut of
update 003. If not, the dictation goes on exactly as today.

## Where it hooks in

```
key down ─ startRecording ─┬─ microphone, live text           (as today)
                           └─ AX selection read, detached     (new, feature on only)
key up ─ tail grace ─ drain ─ voice gate ─ finalize
finalize: Whisper transcript
          ├─ voice action? ── source text ─ model ─ history ─ deliver   (new, one branch)
          └─ DictationPipeline.format ─ snippets ─ model/structure ─ deliver   (as today)
```

- `startRecording` gets one call after the microphone started. It never delays the microphone.
- `finalize` gets one branch right after the transcript: `if await runVoiceAction(…) { return }`.
  Everything the branch needs lives in an extension at the bottom of `DictationController.swift`.
- The Edit selection shortcut (003) keeps its own path: a recording it started never goes
  through detection.

## Detection

`VoiceActions.detect(_ transcript:selectionAtStart:sendCommand:)` in VMCore. Pure, no I/O,
unit-tested. It works on the raw transcript, so neither a mode nor translate everything can
translate or rewrite the instruction first.

### Words

The transcript is lowercased, `ё` folded to `е`, split into runs of letters and digits
("по-английски" is two words), hesitations (эээ, um) dropped. The word classes:

| Class | Russian | English |
|---|---|---|
| Lead-in (skipped at the start) | пожалуйста, ну, так, слушай, давай, а, теперь; можешь / можете / ты можешь / можешь ли ты / не мог(ла) бы ты / не могли бы вы / будь добр(а) / мне нужно | please, so, now, hey, ok; can / could / would / will you (please); i need you to; i want you to; i'd like you to; let's; go ahead and |
| Translate verb | переведи(те), перевести, переведёшь | translate |
| Text verb | сократи, перепиши, перефразируй, переформулируй, отредактируй, упрости, резюмируй, перескажи, укороти (and infinitives) | shorten, rewrite, rephrase, reword, paraphrase, summarize, simplify, proofread, condense |
| Fix verb | исправь, поправь | fix, correct |
| General verb | сделай, преврати, оформи, разбей, улучши, отформатируй, расширь | make, turn, convert, improve, format, polish, edit, expand |
| Named selection | выделенное / выделенный / выделенного … (every case), выделение, то что я выделил(а), что выделено | selected, selection, highlighted, what I selected / highlighted |
| Named clipboard | буфер / буфера / буфере (обмена), клипборд, скопированное / скопированный …, то что я скопировал(а) | clipboard, copied, what I copied |
| Pointer | это, его, её, их; этот / эту / данный + text noun; a bare text noun ("текст") | this, it, that; this / that / the + text noun |
| Text noun | текст, фрагмент, абзац, предложение, кусок, часть, строка, сообщение, письмо, фраза, слово | text, paragraph, sentence, passage, fragment, part, piece, line, message, email, letter, phrase, word |
| Target | на + language (any case: английский, английском), по-английски; + язык | to / into / in + language; + language |
| Source language (ignored) | с + language | from + language |
| Filler after the verb | мне, нам, для меня, пожалуйста, весь, всё, целиком, вот | please, for me, the, a, my, just |
| Modifier | короче, проще, формальнее, вежливее, понятнее, грамотнее, более, менее, до, двух, трёх, предложений, слов, список, пункты; ошибки, опечатки, грамматику, пунктуацию, орфографию | shorter, simpler, clearer, more, less, formal, polite, concise, professional, casual, friendly, to, into, one, two, three, sentences, words, list, bullet, points; typos, mistakes, errors, grammar, spelling, punctuation |

Languages are every one of Whisper's 99, named by `Locale` in Russian and English: the Russian
name's stem matches every case ("испанск" in испанский, испанском, по-испански), and a few
aliases are added (голландский, фарси, mandarin, farsi).

A named source is a span: the keyword plus the words glued to it ("текст из буфера обмена", "то,
что в буфере", "the text in my clipboard", "the selected text").

### Rules

The utterance is: lead-ins, then an optional source, then the verb, then slots (source, target,
source language, fillers, modifiers, other words). Words that fit no slot are the **residue**.
Three kinds of reference, three sets of rules:

| Reference | Verbs | Residue allowed | Needs |
|---|---|---|---|
| **Named** ("выделенное", "буфер", "clipboard") | any action verb | anything up to 12 words, no subordinate clause (чтобы, если, когда, который, because, if, when, which); the source comes before the first residue word, or is preceded only by a modifier ("исправь ошибки в выделенном") | — |
| **Pointer** ("это", "this", "этот текст") right after the verb, or right before it | translate, text, fix with a mistake word | modifiers and a target only | a selection: AX at key press, or ⌘C at finalize |
| **None** | translate with a target; text; fix with a mistake word | modifiers and a target only | a selection read by AX at key press |

Further:

- A translate verb whose "на X" / "to X" is not a language is never an action without a named
  source: "переведи мне деньги на карту", "переведи его на другую должность".
- A pointer followed by a word that is not a text noun is a determiner, not a pointer: "fix this
  bug", "переведи этот баг в статус готово".
- More than 24 words is never an action.
- Two named sources in one utterance is not an action.
- With voice commands on, a trailing "(и) отправь" / "(and) send it" is taken off and remembered:
  Return after the paste, as for any dictation. Any other voice command in the utterance makes
  it an ordinary dictation.

### What the action does

- **Pure translation**: a translate verb, a target, and no residue. Runs as the translation
  request of update 004 (`RewriteRequest` style `.none`, `translate`, target by English name):
  the prompt a 4B model is reliable with, and the validator that keeps code, numbers, links and
  terms.
- **No language named** ("переведи выделенное"): into the translate everything language (English
  by default) when the text is written in another script; otherwise into the language of the
  spoken instruction (Cyrillic → Russian, Latin → English) when that script differs from the
  text's; otherwise the instruction goes to the model as spoken.
- **Anything else**: the spoken instruction as it was said, minus a trailing "отправь", over the
  source text, through the Edit selection request of 003 (`RewriteRequest` style `.selection`).

## Precedence

1. The Edit selection shortcut (003): its recording is its instruction; no detection.
2. A voice action, when the switch is on and the transcript is one.
3. Everything else in the order it has today: voice commands, snippets, mode, translate
   everything, smart structure.

Inside an action, snippet phrases are words of the instruction, not snippets, and only a
trailing "отправь" acts.

## Sources

- **Selection.** Read at key press with Accessibility only, in a detached task with a 0.25 s
  messaging timeout on the app's element, so a hung app can't delay anything. No ⌘C at key
  press: it would overwrite the clipboard and fire on every dictation. At finalize, when the
  words name the selection or point at it and AX gave nothing, `SelectionReader.read()` runs
  (AX, then ⌘C with the clipboard put back), while the target app is still in front.
- **Clipboard.** Read at finalize, only when the words name it. Plain text only; the first 6000
  characters, the same limit as the selection.
- Neither is stored anywhere: the text lives in memory until the dictation ends.
- When a selection was read at key press, the language model is warmed up right away, so the
  first action after a pause does not wait for loading.

## Output

- **The result is delivered by the output mode**, as 003 does: paste replaces the selection (or,
  for the clipboard, inserts at the cursor), the card shows it, clipboard mode copies it.
- **The clipboard keeps its text.** The result is not also put on the clipboard: paste mode puts
  the old clipboard back after pasting, the card has ⌘C, and clipboard mode copies the result
  anyway. Writing it in the other modes would destroy the source the user may still need.
- **Notices, nothing inserted:** a named selection with nothing selected → "Nothing selected";
  an empty clipboard → "Clipboard is empty" (new); no language model ready → "Language model is
  off"; the model failed, timed out or its answer did not pass the check → "Model didn't
  answer". A pointer or an implied selection with no language model and nothing selected by AX
  is an ordinary dictation.
- **Esc** during the model run: nothing is inserted and the selection stays, as in 003.

## History

One record per action. `text` is the result, `raw` is the spoken instruction, as Whisper heard
it. A new optional field `action` on `DictationRecord` says which source it was and, for a
translation, the target language. The stats count the spoken words for such records, not the
result's: a translated page did not take the user a page of speech. Old history files decode
unchanged (the field is optional).

## Overlay

While the model runs, the rewrite stage's label reads the action instead of "Rewriting":
"Selection → ES", "Clipboard → EN", or "Selection" / "Clipboard" for other instructions. The
language code matches the translate everything chip. Esc and the Skip button work as for any
rewrite.

## Settings

`AppSettings.voiceActions`, default on. A toggle "Voice actions" in **Text**, under Voice
commands, with the detail “translate the selection to Spanish”, “shorten the clipboard text”.
With the language model engine off, the detail reads "language model is off".

## Trade-offs

- **AX read at every key press** while the switch is on: a few milliseconds, off the main
  thread, only the focused element's selected text. Apps that do not answer AX (terminals,
  Electron) cost nothing and give nothing, so an implied selection works only in apps that
  answer; there the words must point at it ("это", "this") or name it.
- **Rules over a model.** A classifier would catch more phrasings, but it would run on every
  dictation, cost latency, and could not be tested to "never on this negative". The rules are
  narrow on purpose; the residue limits are what keep instructions to coding agents ("поправь
  вставку из буфера обмена в карточке") out.
- **A pointer with nothing selected in an app without AX** sends a ⌘C. VS Code copies the
  current line then, and the action runs on it. This already applies to the Edit selection
  shortcut.
- **Translation keeps the dictation prompt.** The translation prompt still calls the text a
  dictation; the model translates it all the same, and the prompt stays cached between
  translate everything and actions into the same language.

## Rejected

- **A separate shortcut** — the owner asked for the record key.
- **Detection after formatting** — translate everything would have translated the instruction.
- **⌘C at key press** — clobbers the clipboard on every dictation.
- **Asking the language model whether a dictation is an instruction** — a second model call on
  every dictation, 0.5–1 s, and untestable negatives.
- **Putting the result on the clipboard** — loses the source; see Output.
