# 005 · Reliable recognition — Request

**Review:** requirements taken from the owner's message of 23.09.2026.

## What is needed

The owner's words, as sent (the message was itself dictated, half of it came out in English):

> Братан, есть иногда баги, понял, я когда записываю какое-то одно слово, то оно мне пишет то,
> что ничего не услышано. Дальше иногда бывает такое, что когда я говорю какое-то предложение,
> то есть, например, там 10 предложений, So it sometimes just gives me only the last two
> sentences at the end, and what I was saying before that simply doesn't appear, isn't recorded.
> Why is that? Please fix the bugs, as well as I'll try playing around with the optimization.

## How it is read

**Bug 1: one word gives "Nothing heard".** A short press with a single word ("да", "окей",
"отправь") ends in the notice instead of the word.

**Bug 2: a long dictation loses most of its text.** Ten sentences go in, the last two come out;
what came before is gone. The history shows the other shape as well: the first words come
out and the rest is gone ("Также сделай так, чтобы..." from 16.5 s of speech).

**"Play around with the optimization".** Make the final pass faster where the fix allows it,
without trading away accuracy.

## Evidence from the owner's history

257 dictations, read on the owner's Mac for word counts and durations only:

- Normal speech lands at 1.6–1.8 words per second in every length bucket.
- 26 dictations longer than 8 s came out under 1 word per second: 16.5 s → 4 words,
  19.6 s → 5 words, 94.6 s → 19 words, 169.9 s → 49 words. They occur both under and over the
  30 s mark, so it is not only the long-audio path.
- The text inserted matches the raw transcript in those records, so the words were lost in
  recognition, not in formatting or the language model.
- No dictation shorter than 1 s was ever saved, and only 2 under 2 s.

## Scope

- Recognition of what was recorded: short recordings, long recordings, pauses inside them.
- The edges of a recording: the first and last fraction of a second around the key press.
- Speed of the final pass, measured from key release to inserted text.
- Out of scope: the language model steps (rewrite, translation, structure), the overlay's look.

## How we will know it worked

- A single word held for any length from 0.4 s up gives the word, not "Nothing heard".
- Ten sentences with natural pauses, one of them a long thinking pause, come out as ten
  sentences, at 20 s, 45 s and 70 s, with the owner's dictionary in the prompt.
- The last word said right before the key is released makes it into the text.
- The final pass of a long dictation is no slower than today on the same audio, and faster
  where the fix removes work.
