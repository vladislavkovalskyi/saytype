# 009 · Voice actions over the selection and the clipboard — Request

**Review:** the owner approved the feature on 24.09.2026; this is how it was read, written down
before any code.

## The ask

The owner's words, as sent (the message was dictated, half of it came out translated into
English; "Iiшка" is "ИИшка", the built-in AI):

> I'll also set up the settings so that I can highlight words, and so that the built-in Iiшка
> understands when I ask it, for example, to translate text into English, into Spanish, or into
> another language. Or translate to English, or can you translate this to English, please. And
> it should understand that I need the text translated into English, either the text I've
> highlighted or the text in the clipboard. If I have text in the clipboard, I simply say
> "translate the clipboard text to English," and it will translate it.

## How it is read

**Same key, no new shortcut.** The owner presses the ordinary record key and speaks. When what
they say is an instruction over some text — the text selected in the app in front, or the text
on the clipboard — the language model carries it out and the result goes out instead of the
spoken words. Everything else is an ordinary dictation, exactly as today.

**Translation first.** Translating into any language is the main case, in Russian and English
phrasings and their polite forms:

- "переведи выделенное на испанский", "переведи это на английский, пожалуйста";
- "translate the clipboard text to English", "can you translate this to English, please";
- "translate to English" / "переведи на английский" with text selected.

**Other instructions if they fall out naturally.** "Сократи выделенный текст", "перефразируй
текст из буфера", "fix the typos in the selected text" go through the same path.

**Sources.** Two, named or implied:

| Source | Named as | Implied by |
|---|---|---|
| Selection | "выделенное", "выделенный текст", "selected / highlighted text", "the selection" | "это", "this", "it", "этот текст"; or text selected when recording started |
| Clipboard | "буфер", "буфер обмена", "скопированное", "clipboard", "what I copied" | — |

**A switch.** One setting turns the behaviour on and off; it is on by default.

**Negatives matter.** The owner dictates into chats and into coding agents all day. "Переведи
мне деньги на карту" in a chat, or "поправь вставку из буфера обмена в карточке" to Claude
Code, must stay ordinary dictations. A missed action costs a repeat; a false one destroys a
message or a selection.

**Translate everything stays on.** The owner keeps update 004's switch on with English. The
instruction must be recognized before anything translates it.

## Scope

In:

- recognition of an action in the transcript, deterministic, tested on a corpus of Russian and
  English phrasings and of negatives;
- reading the selection (Accessibility at key press, a ⌘C fallback only when the words name the
  selection) and the clipboard;
- translation into any of Whisper's 99 languages named in Russian or English, and free
  instructions through the Edit selection path of update 003;
- delivery by the output mode, a history record, an overlay tag, notices for "nothing
  selected", "clipboard is empty", "language model is off";
- the setting, Russian strings, README sections.

Out:

- a new shortcut; the Edit selection shortcut of 003 stays as it is;
- answers that are not a transformation of the text ("explain this", "what does this mean");
- other sources: files, the screen, the browser page;
- actions over the text of the card.

## How we will know it works

- The owner's phrases from the ask, and their Russian versions, are recognized as actions with
  the right source and target language; the negatives stay dictations. Checked by `swift test`
  on the corpus.
- "Translate the clipboard text to English" with a Russian paragraph on the clipboard gives an
  English paragraph in the card; the clipboard keeps the original.
- "Переведи выделенное на испанский" with text selected replaces it with the Spanish text in
  paste mode, or shows it in the card in card mode.
- With translate everything on, the instruction is not translated first: the action runs.
- With no language model, the overlay says so and nothing is inserted.
- Esc during the model run leaves everything untouched.
- The built-in model translates a few real paragraphs into Spanish and English acceptably
  (bench with vm-smart).
- `swift test` passes; the app builds without new warnings.
