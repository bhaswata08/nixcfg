#!/usr/bin/env bash
# Screenshot slides from a reveal deck, headless.
#
#   ./shoot.sh <url> <out-dir> <from> [to]
#
#   ./shoot.sh http://localhost:8000/ /tmp/shots 0 8
#   ./shoot.sh file:///abs/path/deck.html /tmp/shots 12
#
# NOTE: #/N renders slide N+1. #/0 is the first slide.
#
# Then read the PNGs. A slide you have not looked at is not done: overflow is
# silent, nothing throws, and the markup looks correct either way.

set -euo pipefail

URL="${1:?usage: shoot.sh <url> <out-dir> <from> [to]}"
OUT="${2:?usage: shoot.sh <url> <out-dir> <from> [to]}"
FROM="${3:?usage: shoot.sh <url> <out-dir> <from> [to]}"
TO="${4:-$FROM}"

# Whichever chromium this machine has.
CHROME="${CHROME:-}"
if [ -z "$CHROME" ]; then
  for c in chromium chromium-browser google-chrome google-chrome-stable; do
    if command -v "$c" >/dev/null 2>&1; then CHROME="$c"; break; fi
  done
fi
if [ -z "$CHROME" ]; then
  echo "No chromium found. On NixOS: nix-shell -p chromium --run './shoot.sh ...'" >&2
  exit 1
fi

mkdir -p "$OUT"

for i in $(seq "$FROM" "$TO"); do
  "$CHROME" --headless --disable-gpu --no-sandbox --hide-scrollbars \
    --window-size=1400,800 \
    --virtual-time-budget=9000 \
    --screenshot="$OUT/slide-$(printf '%03d' "$i").png" \
    "${URL}#/${i}" 2>/dev/null
  echo "$OUT/slide-$(printf '%03d' "$i").png  <-  ${URL}#/${i}  (slide $((i + 1)))"
done
