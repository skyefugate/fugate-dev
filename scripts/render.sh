#!/usr/bin/env bash
# Render the site headlessly at a given viewport and screenshot it.
#   usage: scripts/render.sh <width> <height> <out.png> [docroot]
set -euo pipefail

W="${1:?width}"
H="${2:?height}"
OUT="${3:?output png}"
ROOT="${4:-$(cd "$(dirname "$0")/../public" && pwd)}"

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PORT="${PORT:-8799}"

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT" >/dev/null 2>&1 &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' EXIT

# Wait for the server rather than guessing at a sleep. Guessing is how you get
# screenshots of Chrome's error page and waste twenty minutes.
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null "http://127.0.0.1:$PORT/"; then
    break
  fi
  sleep 0.2
done
curl -fsS -o /dev/null "http://127.0.0.1:$PORT/" || {
  echo "server never came up on $PORT" >&2
  exit 1
}

"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size="$W,$H" \
  --virtual-time-budget=6000 --screenshot="$OUT" \
  "http://127.0.0.1:$PORT/" 2>/dev/null

echo "wrote $OUT ($(magick identify -format '%wx%h' "$OUT"))"
