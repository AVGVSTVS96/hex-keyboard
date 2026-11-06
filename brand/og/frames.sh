#!/bin/sh
# Crops the keyboard out of scripts/shots' frames into brand/og/frames, as web/site/shots/iphone-dark.webp is cropped
# (the bottom 997 px of the 1206×2622 screenshot). Run after typing the headline one key per step:
#   scripts/mac "scripts/shots 'iPhone 17' iPhone-17 iikb dark 's00:|s01:t|s02:h|…'"
set -e
cd "$(dirname "$0")/../.."
mkdir -p brand/og/frames
for f in shots/raw/suggestions/iphone-17-iikb-dark-s[0-9][0-9].png; do
  n=$(basename "$f" .png | sed 's/.*-//')
  magick "$f" -gravity south -crop 1206x997+0+0 +repage -strip -quality 90 "brand/og/frames/$n.webp"
done
