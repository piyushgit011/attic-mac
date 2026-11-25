#!/bin/zsh
# Runs one scripted tour of Attic on the demo library and films it.
# Usage: run-tour.sh <tour> <out.mov>     (tour "stills" saves screenshots into <out dir> instead)
set -e
HERE="${0:A:h}"; REPO="${HERE:h:h}"
APP="$REPO/build/dd/Build/Products/Release/Attic.app"
DEMO="$HOME/Attic Demo"
T="$HOME/Library/Caches/studio.versely.attic/tour"
BIN="${ATTIC_TOOLS:-$REPO/build/tools}"
mkdir -p "$BIN"
[ -x "$BIN/record" ] || swiftc -O "$HERE/record.swift" -o "$BIN/record"
[ -x "$BIN/shot" ] || swiftc -O "$HERE/shot.swift" -o "$BIN/shot"
osascript -e 'tell application id "studio.versely.attic" to quit' 2>/dev/null || true
sleep 1.5; rm -rf "$T"
open "$APP" --args -AtticDemo "$DEMO" -AtticTour "$1" \
  -sort.junk Size -sort.junk.reversed NO -sort.sources "Most files" -sort.sources.reversed NO -sort.cleanup Size \
  -sort.cleanup.reversed NO -sort.dupes "Space to free" -sort.dupes.reversed NO -sort.apps Memory -sort.apps.reversed NO
for i in {1..600}; do [ -f "$T/ready" ] && break; sleep 0.2; done
if [ "$1" = "stills" ]; then
  OUT="$2"; mkdir -p "$OUT"; touch "$T/go"; n=1
  while [ ! -f "$T/done" ]; do
    f=$(ls "$T" | grep "^shot-$n-" || true)
    if [ -n "$f" ]; then
      label=${f#shot-$n-}
      for try in 1 2 3 4 5 6; do "$BIN/shot" studio.versely.attic "$OUT/$(printf %02d $n)-$label.png" | grep -v "^window" && break || sleep 0.5; done
      touch "$T/next-$n"; n=$((n+1))
    fi
    sleep 0.2
  done
else
  "$BIN/record" studio.versely.attic "$2" "$T/go" "$T/done" 300
fi
osascript -e 'tell application id "studio.versely.attic" to quit' 2>/dev/null || true
