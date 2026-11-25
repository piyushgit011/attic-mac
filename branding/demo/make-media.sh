#!/bin/zsh
# Videos and audio for the demo library (needs ffmpeg). Run after make-demo.swift.
set -e
ROOT="$1"
F="$ROOT/.frames"
kb() { # kb <frame> <seconds> <bitrate> <out>
  ffmpeg -loglevel error -y -loop 1 -i "$F/$1.jpg" -t "$2" \
    -vf "scale=3840:-2,zoompan=z='min(zoom+0.0009,1.25)':d=1:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1920x1080:fps=30,format=yuv420p" \
    -c:v libx264 -preset veryfast -b:v "$3" -maxrate "$3" -bufsize 20M -movflags +faststart "$4"
}
# Real-size clips (~50 MB) used for the live R2 offload demo: film grain + constant bitrate keeps them big
real() {
  ffmpeg -loglevel error -y -loop 1 -i "$F/$1.jpg" -t "$2" \
    -vf "scale=3840:-2,zoompan=z='min(zoom+0.0009,1.25)':d=1:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1920x1080:fps=30,noise=alls=14:allf=t,format=yuv420p" \
    -c:v libx264 -preset veryfast -b:v 30M -minrate 30M -maxrate 30M -bufsize 30M -x264-params nal-hrd=cbr -movflags +faststart "$3"
}
real coast 14 "$ROOT/Movies/Lisbon trip.mp4"
real night 11 "$ROOT/Movies/Studio session raw.mov"
# Small clips whose sizes come from demo.json
kb alpine 4 2M "$ROOT/Movies/Drone - Coast 4K.mov"
kb dawn 4 2M "$ROOT/Movies/Kyoto timelapse.mov"
kb sunset 4 2M "$ROOT/Movies/Wedding film final.mov"
cat "$ROOT/Movies/Wedding film final.mov" > "$ROOT/Movies/Wedding film final copy.mov"
kb forest 4 2M "$ROOT/Movies/Product demo v3.mp4"
kb desert 4 2M "$ROOT/Movies/Screen Recording 2026-11-18 at 14.22.05.mov"
# Audio
tone() { ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=$1:duration=4" -af "volume=0.2" "$2"; }
tone 220 "$ROOT/Music/Late night demo v3.mp3"
tone 330 "$ROOT/Music/Podcast ep 12 - final.m4a"
tone 440 "$ROOT/Music/Field recording - Lisbon tram.wav"
tone 262 "$ROOT/Music/Voice memo - melody idea.m4a"
ls -la "$ROOT/Movies" | tail -n +2
