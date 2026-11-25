#!/bin/zsh
# Turns the raw window recordings (variable frame rate, 2560x1600) into 30 fps 1600x1000 clips for Remotion.
set -e
HERE="${0:A:h}"; SRC="${HERE:h:h}/build/rec"; DST="${HERE:h}/public/rec"
mkdir -p "$DST"
for f in "$SRC"/*.mov; do
  out="$DST/$(basename "${f%.mov}").mp4"
  [ "$out" -nt "$f" ] && continue
  ffmpeg -loglevel error -y -i "$f" -vf "fps=30,scale=1600:-2:flags=lanczos,format=yuv420p" -c:v libx264 -preset slow -crf 16 -movflags +faststart -an "$out"
  echo "  $(basename "$out") $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out")s"
done
