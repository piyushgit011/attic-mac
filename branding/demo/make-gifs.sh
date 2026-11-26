#!/bin/zsh
# README GIFs from the tour recordings in build/rec (made by run-tour.sh). Needs ffmpeg.
# Usage: branding/demo/make-gifs.sh
set -e
HERE="${0:A:h}"; REPO="${HERE:h:h}"; SRC="$REPO/build/rec"; DST="$REPO/docs/gifs"
mkdir -p "$DST"
gif() { # gif <recording> <out name> <width> <fps>
  local in="$SRC/$1.mov" out="$DST/$2.gif" pal="$(mktemp -t attic).png"
  [ -f "$in" ] || { echo "  skip $1 (no recording)"; return; }
  ffmpeg -loglevel error -y -i "$in" -vf "fps=$4,scale=$3:-1:flags=lanczos,palettegen=max_colors=192:stats_mode=diff" "$pal"
  ffmpeg -loglevel error -y -i "$in" -i "$pal" -lavfi "fps=$4,scale=$3:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=sierra2_4a:diff_mode=rectangle" "$out"
  rm -f "$pal"
  echo "  docs/gifs/$2.gif $(du -h "$out" | cut -f1)"
}
gif folders folders 960 12
gif search search 960 12
gif looks looks 960 10
gif cleanup cleanup 960 10
gif offload offload 960 10
gif quicksearch quicksearch 860 12
