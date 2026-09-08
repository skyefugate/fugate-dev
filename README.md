# fugate.dev

The landing page at **https://fugate.dev** — a signpost that points visitors at
either [skye.fugate.dev](https://skye.fugate.dev) or
[carl.fugate.dev](https://carl.fugate.dev).

Deliberately dumb: two HTML files, one stylesheet, three fonts, a handful of
images. No framework, no bundler, no runtime JavaScript, no third-party
requests. Deployed as a Cloudflare Worker with static assets — the asset router
serves `public/` and there is nothing to build.

## Layout

```
wrangler.jsonc           Worker config; assets.directory = ./public/
package.json             pins wrangler for the deploy; no app dependencies
public/                  <- everything in here is uploaded and served
  index.html             the page
  404.html               the unmatched-path page
  _headers               CSP, security headers, cache policy
  _redirects             /skye and /carl shortlinks
  robots.txt sitemap.xml
  assets/styles.css      the whole design, including @font-face
  assets/fonts/*.woff2   self-hosted latin subsets (Fraunces var, Plex Mono)
  assets/img/*           portraits (webp + jpg, 320/640), favicons, OG card
scripts/                 asset generation and verification; never deployed
```

Anything outside `public/` is not in the assets directory, so it is never
uploaded. That is the entire reason the site sits in a subdirectory instead of
at the repo root.

## Running it locally

```bash
npm install
npm run dev        # wrangler dev — the real asset router
```

`wrangler dev` is worth preferring over a plain static server because it
actually applies `_headers`, `_redirects`, and the 404 handling. A plain server
will happily tell you the page is fine while the redirects are broken.

If you only want to eyeball the markup:

```bash
python3 -m http.server 8000 --directory public
```

Either way, use a server. Opening `public/index.html` as a `file://` URL will
not work — every path is root-relative and the fonts will 404.

## Verifying it

```bash
npm run check              # every local href/src/url() exists on disk
npm run verify             # the above, plus accessibility and contrast audit
bash scripts/verify.sh shots   # ...and write screenshots to /tmp/fugate-shots
npx wrangler deploy --dry-run  # validates wrangler.jsonc and parses _headers/_redirects
```

The audit covers headings, alt text, link names, duplicate ids, WCAG 2.2 target
sizes, and real computed contrast ratios.

Two traps worth knowing about, both of which will waste your afternoon:

- **Headless Chrome will not size its window below ~500px.** Ask for a 390px
  screenshot and you get a 500px layout cropped to 390px, which looks exactly
  like a horizontal overflow bug. Narrow viewports must go through
  `scripts/responsive-harness.html`, where media queries resolve against an
  iframe width instead. `scripts/verify.sh shots` does this for you.
- **Poll for the local server, never sleep.** Otherwise you screenshot Chrome's
  own error page and start debugging CSS that was never loaded.

CI (`.github/workflows/verify.yml`) runs the asset check, a `wrangler deploy
--dry-run`, and a link check — the last one weekly as well as on push, since
outbound links rot on their own schedule. LinkedIn is excluded because it
answers CI runners with HTTP 999.

## Changing things

**Copy, links, roles** — inline in `public/index.html`. There are two `<article
class="card">` blocks; they are intentionally near-identical. Keep the JSON-LD
block in `<head>` in sync if you change a name, title, or profile URL.

**Portraits** — `scripts/build-assets.sh` pulls the headshots from the two
personal sites, squares them, converts to grayscale, and emits webp + jpg at
320/640 plus the favicon and OG card. Needs `brew install imagemagick webp`.
Both photos are forced to grayscale on purpose: one source is black and white
and the other was colour, and side by side that read as a mistake. The
per-person accent is applied over the top in CSS as a duotone.

**Type** — `scripts/fetch-fonts.py` re-pulls the latin subsets. If you change
families, update the `unicode-range` in `public/assets/styles.css` to match.

**Accent colours** — `--skye` and `--carl` in `:root`. Everything per-person
derives from `--accent`, which each card sets once.

## Deploying

Cloudflare **Workers** (not Pages), connected to this repo via Workers Builds.

| Setting | Value |
|---|---|
| Build command | *leave empty* |
| Deploy command | `npx wrangler deploy` |
| Non-production branch builds | on, if you want per-branch previews |
| Protect with Cloudflare Access | off |

There is no build step, so a build command would only give you something new to
break. `npx wrangler deploy` picks up the wrangler version pinned in
`package.json`, so a future wrangler release cannot silently change the deploy.

On Cloudflare Access: leave it off for production. This is a public landing
page; putting a login screen in front of it defeats the point. Access offers
*Previews only* and *All traffic* scopes — if you ever want it, previews-only is
the only sane choice here, and it needs Zero Trust enabled on the account.

### Moving the apex over

`fugate.dev` is currently a custom domain on the **skyefugate-website** project.
A hostname can only belong to one Cloudflare project at a time, so:

1. skyefugate-website → Custom domains → remove `fugate.dev` (and `www` if set).
2. This Worker → Settings → Domains & Routes → add `fugate.dev`, then
   `www.fugate.dev`.
3. Cloudflare updates the zone records itself. Nothing to edit in DNS by hand.

Expect a couple of minutes of errors on the apex between steps 1 and 2. Verify
the `*.workers.dev` URL renders before you start. Everything else is untouched:
`skye.fugate.dev`, `carl.fugate.dev`, and `hotgarbage.net` are separate
hostnames on separate projects.

### One thing not to do

**Do not add a redirect from `fugate.dev` to `skye.fugate.dev`.** It is the only
address this page has; redirecting the apex deletes it. Duplicate content
between `skye.fugate.dev` and `hotgarbage.net` is handled by `rel=canonical` on
those sites, not by a redirect here.

Related: `skyefugate-website` shipped `baseUrl = https://fugate.dev`, so its
canonical, `og:url`, sitemap, and robots all pointed at this apex. That needs to
be `https://skye.fugate.dev` before or alongside this cutover, or Google will be
told that Skye's content lives at an address that now serves a directory page.
