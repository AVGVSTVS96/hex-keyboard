#!/bin/sh
# Crops the keyboard out of scripts/shots' frames into brand/og/frames: run after
#   scripts/mac "scripts/shots 'iPhone 17' iPhone-17 hex dark 's00:|s01:o|s02:n|…'"   (one step per key of the phrase)
# TOP is where the keyboard's backdrop starts and BOTTOM where its keys end, in the 1206×2622 screenshot.
set -e
cd "$(dirname "$0")/../.."
top=${TOP:?} bottom=${BOTTOM:?}
mkdir -p brand/og/frames
for f in shots/raw/suggestions/iphone-17-hex-dark-s[0-9][0-9].png; do
  n=$(basename "$f" .png | sed 's/.*-//')
  magick "$f" -crop "1206x$((bottom - top))+0+$top" +repage -resize 1120x -strip -define png:compression-level=9 "brand/og/frames/$n.png"
done
