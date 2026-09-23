# 008 · Voice snippets — Request

**Review:** the owner approved the feature on 23.09.2026; this is how it was read, written down
before any code.

## The ask

A spoken trigger phrase inserts saved text:

- "мой имейл" → the owner's e-mail address;
- "ссылка на репо" → a repository link;
- "шаблон ревью" → a ready prompt for Claude Code.

The saved text can hold variables: `{clipboard}`, `{selection}`, `{date}`, and `{time}` if it
is cheap. A trigger works in the middle of a phrase: "проверь шаблон ревью для этого файла"
puts the template where "шаблон ревью" was said. The owner dictates mostly in Russian with
English terms, and keeps "translate everything" on.

## How it is read

**Trigger phrase.** Words the user says, matched against what Whisper heard, not against the
formatted text. Whisper varies case, punctuation, spacing and hyphens ("Шаблон ревью.",
"шаблон-ревью", "шаблонревью"), so all of those match. It never matches part of a word:
"мой имейлы" does not fire "мой имейл". One snippet can have several phrases, for the ways a
phrase gets said or heard ("шаблон ревью", "шаблон review").

**Saved text.** Inserted exactly as the user wrote it: no lowercasing, no punctuation fixes, no
dictionary spellings, no backticks, no translation. The text around it is formatted as usual.

**Variables.** Filled in when the text is inserted:

| Variable | Value |
|---|---|
| `{clipboard}` | the text on the clipboard |
| `{selection}` | the text selected in the app the dictation goes to |
| `{date}` | today's date in the user's format |
| `{time}` | the current time in the user's format |

Anything else in braces stays as written, so a snippet can hold code like `{ id }`.

**Voice commands win.** "новая строка", "удали последнее предложение", "отправь" and the quote
commands keep working as they do. A snippet whose phrase is a command never fires where the
command acts.

**Language model steps.** A mode that rewrites, a mode that translates, and "translate
everything" must not touch the saved text, and must not translate the trigger before it is
matched. The words around a snippet are still rewritten or translated.

## Scope

In:

- snippets in settings, with a section in the main window to add, edit and delete them;
- matching in every mode and every output (paste, card, clipboard), and in the Edit selection
  instruction;
- the four variables;
- a mark in the overlay card on the part that came from a snippet, if it is cheap.

Out:

- sharing, import and export of snippets;
- snippets that run actions (open a URL, press keys);
- per-app snippets;
- screen context (006) and audio history (007), which come later.

## How we will know it works

- "мой имейл" alone inserts the address and nothing else: no period, no capital letter changed.
- "проверь шаблон ревью для этого файла" inserts the template between "Проверь" and "для этого
  файла", and the template is character for character what was saved.
- The same dictation with "translate everything" on: the words around are English, the template
  is unchanged. If the model loses the template's place, the dictation is inserted without the
  model instead of losing the template.
- `{clipboard}`, `{selection}`, `{date}`, `{time}` are filled in; `{name}` stays `{name}`.
- "шаблон ревью новая строка мой имейл" gives two lines; a snippet named "новая строка" does not
  break "новая строка".
- Settings saved by 0.3.0 load without losing anything.
- `swift test` passes and covers matching, placement, variables, command precedence and
  settings decoding; the app builds without new warnings.
