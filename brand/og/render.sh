#!/bin/sh
# Renders brand/og/index.html into the link preview: og.png (the still) and og.mp4 (the loop iMessage and Telegram
# play), in web/site and brand/og/out. The loop starts on the still so the hand-off from og.png to the video doesn't
# jump. Needs Chrome, ffmpeg and brand/og/frames (frames.sh).
set -e
cd "$(dirname "$0")/../.."
chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
root=$(mktemp -d) out=$(mktemp -d)
trap 'kill $server 2>/dev/null; rm -rf "$root" "$out"' EXIT
cp -R web/site/fonts brand/og/frames brand/og/index.html brand/logo/out/wordmark-paper.svg "$root/"
python3 -m http.server 4871 -d "$root" >/dev/null 2>&1 & server=$!
until curl -sf -o /dev/null localhost:4871/; do sleep 0.2; done
shoot() { "$chrome" --headless --hide-scrollbars --force-device-scale-factor=1 --window-size=1200,630 --screenshot="$out/$1.png" "http://localhost:4871/$2" 2>/dev/null || [ -s "$out/$1.png" ]; }

keys=$(ls brand/og/frames | wc -l | tr -d ' ')
shoot still ''
: >"$out/list"
step() { echo "file '$out/$1.png'" >>"$out/list"; echo "duration $2" >>"$out/list"; }
step still 2.6
n=0
while [ $n -lt "$keys" ]; do
  shoot "n$n" "?n=$n"
  if [ $n -eq 0 ]; then step n0 0.5; elif [ $n -eq $((keys - 1)) ]; then step "n$n" 0.6; else step "n$n" 0.09; fi
  n=$((n + 1))
done
echo "file '$out/still.png'" >>"$out/list"

cp "$out/still.png" web/site/og.png
ffmpeg -v error -y -f concat -safe 0 -i "$out/list" -vf "fps=30,format=yuv420p" -c:v libx264 -profile:v high -crf 22 \
  -an -movflags +faststart web/site/og.mp4
cp web/site/og.png web/site/og.mp4 brand/og/out/
