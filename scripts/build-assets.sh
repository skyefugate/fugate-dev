#!/usr/bin/env bash
#
# Regenerates every derived asset in assets/img from the upstream headshots.
#
# The committed assets are already built; you only need this if a headshot
# changes. Requires ImageMagick 7 (magick) and cwebp:
#   brew install imagemagick webp
#
# Why grayscale: Skye's headshot is black and white and Carl's was colour.
# Side by side that looked like an accident, so both are normalised to
# grayscale and the accent colour is applied in CSS as a duotone tint.

set -euo pipefail

cd "$(dirname "$0")/.."

SRC="_src"
OUT="public/assets/img"
mkdir -p "$SRC" "$OUT"

MARKER="/System/Library/Fonts/Supplemental/Bradley Hand Bold.ttf"
MONO="/System/Library/Fonts/Monaco.ttf"
# callisto theme tokens, matching the two personal sites
BG="#020617"
FG="#dcdcdc"
DIM="#8892b0"
TEAL="#00ccb4"
SKYE="#01c0f0"
CARL="#b45eff"

echo "==> fetching source headshots"
curl -fsS --max-time 60 https://skye.fugate.dev/headshot.jpg -o "$SRC/skye-src.jpg"
curl -fsS --max-time 60 https://carl.fugate.dev/headshot.jpg -o "$SRC/carl-src.jpg"

echo "==> square crop, grayscale, downscale"
# Square crop from the top of the frame: faces sit high in both originals.
magick "$SRC/skye-src.jpg" -auto-orient -gravity north -crop '3283x3283+0+0' +repage \
  -colorspace Gray -resize 640x640 -level 2%,98% -unsharp 0x0.75+0.6+0.008 "$SRC/skye-640.png"
magick "$SRC/carl-src.jpg" -auto-orient -gravity north -crop '936x936+0+0' +repage \
  -colorspace Gray -resize 640x640 -level 2%,98% -unsharp 0x0.75+0.6+0.008 "$SRC/carl-640.png"

for p in skye carl; do
  magick "$SRC/$p-640.png" -resize 320x320 "$SRC/$p-320.png"
  for w in 320 640; do
    cwebp -quiet -q 84 -metadata none "$SRC/$p-$w.png" -o "$OUT/$p-$w.webp"
    magick "$SRC/$p-$w.png" -strip -interlace Plane -quality 84 "$OUT/$p-$w.jpg"
  done
done

echo "==> favicon: F monogram"
magick -size 512x512 xc:none \
  -fill "$BG" -draw 'roundrectangle 0,0 511,511 96,96' \
  -font "$MONO" -pointsize 330 -fill "$FG" -gravity center -annotate +0+6 'F' \
  "$SRC/monogram-512.png"
magick "$SRC/monogram-512.png" -resize 32x32 "$OUT/favicon-32.png"
magick "$SRC/monogram-512.png" -resize 192x192 "$OUT/favicon-192.png"
magick "$SRC/monogram-512.png" -resize 180x180 -background "$BG" -alpha remove -alpha off \
  "$OUT/apple-touch-icon.png"

echo "==> open graph card"
# Square portraits with a hairline border, matching the cards on the page.
for p in skye carl; do
  magick "$SRC/$p-640.png" -resize 240x240 -bordercolor '#2a3350' -border 1 "$SRC/$p-sq.png"
done

magick -size 1200x630 "xc:$BG" \
  "$SRC/skye-sq.png" -geometry +249+180 -composite \
  "$SRC/carl-sq.png" -geometry +709+180 -composite \
  -font "$MARKER" -pointsize 86 -fill "$FG" -gravity north -annotate +0+44 'Fugate' \
  -font "$MONO" -pointsize 22 -fill "$TEAL" -gravity north -annotate -242+148 '>' \
  -fill "$FG" -gravity north -annotate +14+148 'Which one of us are you looking for?' \
  -font "$MONO" -pointsize 30 -fill "$FG" -gravity north \
    -annotate -230+456 'Skye Fugate' -annotate +230+456 'Carl Fugate' \
  -font "$MONO" -pointsize 19 -gravity north \
    -fill "$SKYE" -annotate -230+503 'skye.fugate.dev' \
    -fill "$CARL" -annotate +230+503 'carl.fugate.dev' \
  -font "$MONO" -pointsize 17 -fill "$DIM" -gravity south -annotate +0+40 'TWO FUGATES. TWO SITES.' \
  -strip -quality 90 "$OUT/og-card.jpg"

echo "==> done"
ls -l "$OUT" | awk 'NR>1 {printf "%9s  %s\n", $5, $9}'
