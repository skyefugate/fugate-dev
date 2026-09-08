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

SERIF="/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
MONO="/System/Library/Fonts/Supplemental/Courier New Bold.ttf"
INK="#100e0c"
CREAM="#f2ece1"
DIM="#a1988c"
SKYE="#7fc6d4"
CARL="#d99b4e"

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
  -fill "$INK" -draw 'roundrectangle 0,0 511,511 96,96' \
  -font "$SERIF" -pointsize 340 -fill "$CREAM" -gravity center -annotate +0+14 'F' \
  "$SRC/monogram-512.png"
magick "$SRC/monogram-512.png" -resize 32x32 "$OUT/favicon-32.png"
magick "$SRC/monogram-512.png" -resize 192x192 "$OUT/favicon-192.png"
magick "$SRC/monogram-512.png" -resize 180x180 -background "$INK" -alpha remove -alpha off \
  "$OUT/apple-touch-icon.png"

echo "==> open graph card"
for p in skye carl; do
  magick "$SRC/$p-640.png" -resize 240x240 \
    \( +clone -alpha extract -threshold -1 -negate -fill white -draw 'circle 120,120 120,0' \) \
    -alpha off -compose copy_opacity -composite "$SRC/$p-circle.png"
done

magick -size 1200x630 "xc:$INK" \
  -fill 'rgba(242,236,225,0.10)' -draw 'rectangle 599,120 600,510' \
  "$SRC/og-base.png"

magick "$SRC/og-base.png" \
  "$SRC/skye-circle.png" -geometry +180+150 -composite \
  "$SRC/carl-circle.png" -geometry +780+150 -composite \
  -font "$MONO" -pointsize 22 -fill "$DIM" -gravity northwest -annotate +70+56 'F U G A T E . D E V' \
  -font "$SERIF" -pointsize 46 -fill "$CREAM" -gravity northwest \
  -annotate +180+430 'Skye Fugate' -annotate +780+430 'Carl Fugate' \
  -font "$MONO" -pointsize 19 -fill "$SKYE" -gravity northwest -annotate +180+495 'skye.fugate.dev' \
  -fill "$CARL" -annotate +780+495 'carl.fugate.dev' \
  -font "$MONO" -pointsize 18 -fill "$DIM" -gravity south \
  -annotate +0+42 'TWO PEOPLE. TWO SITES. ONE SURNAME.' \
  -strip -quality 90 "$OUT/og-card.jpg"

echo "==> done"
ls -l "$OUT" | awk 'NR>1 {printf "%9s  %s\n", $5, $9}'
