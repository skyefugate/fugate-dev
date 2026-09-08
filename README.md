# fugate.dev

The landing page at **https://fugate.dev** — a signpost that points visitors at
either [skye.fugate.dev](https://skye.fugate.dev) or
[carl.fugate.dev](https://carl.fugate.dev).

Deliberately dumb: one HTML file, one stylesheet, three fonts, four images. No
framework, no build step, no JavaScript at runtime, no third-party requests.
Cloudflare Pages serves the repo root as-is.

## Layout

```
index.html               the whole page
assets/styles.css        the whole design, including @font-face
assets/fonts/*.woff2     self-hosted latin subsets (Fraunces var, IBM Plex Mono)
assets/img/*             portraits (webp + jpg, 320/640), favicons, OG card
_redirects               /skye and /carl shortlinks
_headers                 CSP, security headers, cache policy
robots.txt sitemap.xml   the boring but necessary two
scripts/                 asset generation and verification (not deployed)
```

## Running it locally

```bash
python3 -m http.server 8000
open http://localhost:8000
```

Opening `index.html` as a `file://` URL will not work: every path is
root-relative, and the fonts will 404. Use the server.

## Verifying it

```bash
# every local href/src/url() actually exists on disk
python3 scripts/check-assets.py

# screenshot at a given viewport
scripts/render.sh 1280 800 /tmp/desktop.png
```

Accessibility and contrast audit — headings, alt text, link names, WCAG 2.2
target sizes, and real computed contrast ratios:

```bash
python3 -c "import pathlib; s=pathlib.Path('index.html').read_text(); \
  pathlib.Path('_audit.html').write_text(s.replace('</body>', \
  '<script src=\"/scripts/audit.js\"></script></body>'))"
python3 -m http.server 8000 &
open http://localhost:8000/_audit.html   # results render at the bottom of the page
```

For narrow viewports use `scripts/responsive-harness.html`. Headless Chrome
refuses to size its window below ~500px, so direct mobile screenshots silently
lie; the harness renders the page in iframes, where media queries resolve
against the iframe width instead.

CI (`.github/workflows/verify.yml`) runs the asset check on every push and a
link check weekly. LinkedIn is excluded from the link check because it answers
CI runners with HTTP 999.

## Changing things

**Copy, links, roles** — all inline in `index.html`. There are two `<article
class="card">` blocks; they are intentionally near-identical. Keep the JSON-LD
block in `<head>` in sync if you change a name, title, or profile URL.

**Portraits** — `scripts/build-assets.sh` pulls the headshots from the two
personal sites, squares them, converts to grayscale, and emits webp + jpg at
320/640 plus the favicon and OG card. Requires `brew install imagemagick webp`.
Both photos are forced to grayscale on purpose: one source is black and white
and the other was colour, and side by side that read as a mistake. The per-person
accent colour is applied over the top in CSS as a duotone.

**Type** — `scripts/fetch-fonts.py` re-pulls the latin subsets. If you change
families, update the `unicode-range` in `assets/styles.css` to match.

**Accent colours** — `--skye` and `--carl` in `:root`. Everything per-person
derives from `--accent`, which each card sets once.

## Deploying

Cloudflare Pages, connected to this repo. There is no build step.

1. Cloudflare dashboard → Workers & Pages → Create → Pages → Connect to Git.
2. Pick this repo, production branch `main`.
3. Framework preset: **None**. Build command: **empty**. Output directory: `/`.
4. Deploy. Confirm the `*.pages.dev` URL renders before touching DNS.

### Moving the apex over

`fugate.dev` is currently a custom domain on the **skyefugate-website** Pages
project. A hostname can only belong to one Pages project at a time, so:

1. skyefugate-website → Custom domains → remove `fugate.dev` (and `www` if set).
2. This project → Custom domains → add `fugate.dev`, then `www.fugate.dev`.
3. Cloudflare updates the zone records itself. Nothing to edit in DNS by hand.

Expect a couple of minutes of 404s on the apex between steps 1 and 2. Everything
else is untouched: `skye.fugate.dev`, `carl.fugate.dev`, and `hotgarbage.net`
are separate hostnames on separate projects.

### One thing not to do

**Do not add a redirect from `fugate.dev` to `skye.fugate.dev`.** It is the only
address this page has; redirecting the apex deletes it. Duplicate content
between `skye.fugate.dev` and `hotgarbage.net` is handled by `rel=canonical` on
those sites, not by a redirect here.

Related: `skyefugate-website` shipped `baseUrl = https://fugate.dev`, so its
canonical, `og:url`, sitemap, and robots all pointed at this apex. That needs to
be `https://skye.fugate.dev` before or alongside this cutover, or Google will be
told that Skye's content lives at an address that now serves a directory page.
