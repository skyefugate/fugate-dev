#!/usr/bin/env bash
#
# Runs the accessibility/contrast audit and the responsive harness against the
# real site.
#
#   scripts/verify.sh            # asset check + a11y audit
#   scripts/verify.sh shots      # ...and write screenshots to /tmp/fugate-shots
#
# Both the audit script and the harness need to be reachable from the same
# origin as the site, but neither should ever be deployed. So they are copied
# into a throwaway docroot alongside public/ rather than living inside it.

set -euo pipefail

cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PORT="${PORT:-8871}"
WORK="$(mktemp -d)"
SHOTS="${SHOTS:-/tmp/fugate-shots}"

cleanup() {
  [ -n "${SRV:-}" ] && kill "$SRV" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> asset integrity"
python3 scripts/check-assets.py

cp -R public/. "$WORK/"
cp scripts/audit.js "$WORK/_audit.js"
cp scripts/responsive-harness.html "$WORK/_harness.html"
# index.html plus the audit script, as a separate page so index stays untouched.
python3 - "$WORK" <<'PY'
import pathlib, sys
w = pathlib.Path(sys.argv[1])
s = (w / "index.html").read_text()
(w / "_audit.html").write_text(s.replace("</body>", '  <script src="/_audit.js"></script>\n</body>'))
PY

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK" >/dev/null 2>&1 &
SRV=$!

# Poll rather than sleep. Guessing at a sleep is how you screenshot Chrome's
# own error page and then spend twenty minutes debugging your CSS.
for _ in $(seq 1 60); do
  curl -fsS -m 1 -o /dev/null "http://127.0.0.1:$PORT/index.html" 2>/dev/null && break
  sleep 0.25
done
curl -fsS -m 3 -o /dev/null "http://127.0.0.1:$PORT/index.html" || {
  echo "server never came up on $PORT" >&2
  exit 1
}

echo
echo "==> accessibility + contrast audit"
"$CHROME" --headless=new --disable-gpu --window-size=1440,900 --virtual-time-budget=6000 \
  --dump-dom "http://127.0.0.1:$PORT/_audit.html" 2>/dev/null |
  python3 -c "
import sys, re, html
s = sys.stdin.read()
m = re.search(r'<pre id=\"audit\">(.*?)</pre>', s, re.S)
print(html.unescape(m.group(1)) if m else 'AUDIT DID NOT RUN')
"

if [ "${1:-}" = "shots" ]; then
  mkdir -p "$SHOTS"
  echo
  echo "==> screenshots -> $SHOTS"
  for wh in "1440 900" "1280 800"; do
    set -- $wh
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
      --window-size="$1,$2" --virtual-time-budget=6000 \
      --screenshot="$SHOTS/desktop-$1.png" "http://127.0.0.1:$PORT/" 2>/dev/null
    echo "   desktop-$1.png"
  done
  # Narrow viewports must go through the iframe harness: headless Chrome will
  # not size its own window below ~500px and silently crops instead.
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size=2000,1560 --virtual-time-budget=7000 \
    --screenshot="$SHOTS/responsive.png" "http://127.0.0.1:$PORT/_harness.html" 2>/dev/null
  echo "   responsive.png (320 / 390 / 430 / 768)"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size=1280,800 --virtual-time-budget=6000 \
    --screenshot="$SHOTS/404.png" "http://127.0.0.1:$PORT/404.html" 2>/dev/null
  echo "   404.png"
fi
