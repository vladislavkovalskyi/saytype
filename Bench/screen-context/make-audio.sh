#!/bin/zsh
# Speaks phrases.txt with the Russian system voice into Bench/synthetic/screen-context/NN.wav, for
#   vm-bench context speech Bench/screen-context/corpus.tsv [--owner-prompt settings.json]
# Each corpus line names the audio, the screen text it is dictated over (code.txt, chat.txt) and
# the terms the text must end up with; lines with no terms are ordinary speech that must not change.
here=${0:A:h}
out="$here/../synthetic/screen-context"
mkdir -p "$out"
n=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  n=$((n + 1))
  say -v Milena -o "$out/$(printf %02d $n).wav" --data-format=LEF32@16000 "$line"
done < "$here/phrases.txt"
ls "$out" | wc -l
