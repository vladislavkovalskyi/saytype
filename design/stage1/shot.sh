#!/bin/zsh
# Screenshots built artboards with headless Chrome.
#   ./shot.sh <out_dir> "Name W H" ...
out=$1; shift
mkdir -p "$out"
here=${0:A:h}
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for spec in "$@"; do
  set -- ${=spec}
  rm -f "$out/$1.png"
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --no-first-run --user-data-dir="$out/profile-$1" --window-size=$2,$3 --virtual-time-budget=5000 --screenshot="$out/$1.png" "file://$here/artboards/$1.dc.html" >/dev/null 2>&1 &
  pid=$!
  for k in {1..40}; do [ -s "$out/$1.png" ] && break; sleep 1; done
  sleep 1; kill $pid 2>/dev/null
done
pkill -f "$out/profile-" 2>/dev/null
rm -rf "$out"/profile-*
ls "$out"
