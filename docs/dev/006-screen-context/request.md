# 006 · Screen context — Request

**Review:** the owner approved the feature on 23.09.2026; this is how it was read, written down
before any code.

## The ask

When the record key is pressed, saytype reads the text of the active window through
Accessibility: the window title, the focused input field, file names, nicknames in a chat. Rare
words are pulled out of it (identifiers, names, titles) and used for this one dictation, so
"поправь DictationController" comes out spelled exactly as it is on the screen.

The owner accepted one limit up front: Electron apps and terminals expose little text.

The owner is a developer. They dictate mostly Russian with English terms, into iTerm (Claude
Code), Cursor and VS Code, Telegram and browsers.

## How it is read

**What is read.** The window in front at the moment the key goes down, and only its text:

- the window title, which in editors carries the file and project name;
- the focused field, around the caret: what the user is typing into or working on;
- the text visible in the window: file lists, tabs, chat messages, page text.

**What is taken from it.** Words Whisper is likely to get wrong and a developer is likely to say:

- identifiers in camelCase, PascalCase, snake_case, kebab-case and CONSTANT_CASE;
- file names with an extension, and paths;
- @handles;
- Latin proper names that are not ordinary English words, and Russian names if that can be done
  reliably.

Everyday words in either language are not terms and are left out.

**How it is used.** For this dictation only, in the same places the dictionary and the project
folders already work:

- after recognition, what Whisper heard is rewritten to the spelling on the screen: "диктейшн
  контроллер" or "Dictation Controller" becomes `DictationController`;
- maybe in the Whisper prompt, if a measurement shows it helps. Update 005 capped the prompt at
  40 tokens because a longer one cut off fast speech, and the owner's dictionary fills most of
  it. The cap stays.

**When.** The text is read when the key goes down, because that is when the target app is known.
Reading must never delay the start of a recording, and the terms are needed only when the final
pass runs.

**Privacy.** The screen text stays on the Mac and in memory for one dictation. It is never
written to disk, to the history or to a log, and it is never sent anywhere. Password fields are
never read.

**Settings.** One switch, on by default. If it is cheap, a small readout of the terms the last
dictation used.

## Scope

In:

- reading the active window's text with a hard time limit and a limit on how much of the window
  is walked;
- extracting and ranking terms from it, as pure logic with unit tests;
- using the terms in the text formatter, and in the prompt if the bench shows it helps;
- the switch, the readout, README sections in English and Russian, a line in Privacy;
- a debug path to check the reader against windows opened for the test.

Out:

- reading windows other than the one in front, or reading anything while no dictation starts;
- screenshots and text recognition (OCR) of pixels;
- turning on accessibility trees in apps that keep them off, if doing so changes how the app
  behaves;
- storing screen terms between dictations.

## How we will know it works

- Dictating a name that is on the screen ("поправь диктейшн контроллер", "открой проджект термс
  сервис точка свифт") gives the on-screen spelling, measured on synthetic speech through the
  real engine and formatter.
- Ordinary Russian and English words are never rewritten into screen terms: the same dictations
  with a screen full of unrelated terms come out unchanged.
- Reading a window takes tens of milliseconds at most and never blocks the key press. Timings and
  what each app exposes are measured on TextEdit, Terminal, Safari and an Electron app.
- A password field in focus gives no text at all.
- With the switch off, nothing is read.
