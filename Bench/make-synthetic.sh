#!/bin/zsh
# Speaks Bench/phrases.txt with the Russian system voice into Bench/synthetic/NN.wav.
# Synthetic speech is cleaner than a person; use it for smoke tests, not for choosing models.
here=${0:A:h}
mkdir -p "$here/synthetic"
n=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  n=$((n + 1))
  say -v Milena -o "$here/synthetic/$(printf %02d $n).wav" --data-format=LEF32@16000 "$line"
done < "$here/phrases.txt"
ls "$here/synthetic" | wc -l
