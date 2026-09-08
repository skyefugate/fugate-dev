#!/usr/bin/env python3
"""Verify every local path referenced by the site actually exists on disk.

Catches the classic static-site failure: a renamed image that still 200s from
your browser cache and 404s for everyone else. Run locally or in CI.

The site root is ./public/ — that is what wrangler.jsonc uploads as assets, so
root-relative paths like "/assets/x.webp" resolve against it, not the repo root.

Checks:
  * href/src/srcset targets in every HTML file under public/
  * url(...) targets in public/assets/styles.css
  * the files Cloudflare needs in order to serve this thing at all
"""

from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
SITE = REPO / "public"

# Served, but with no file on disk — handled by public/_redirects.
REDIRECT_ONLY = {"/skye", "/carl", "/skye/", "/carl/"}


def collect_html_refs(html: str) -> set[str]:
    refs: set[str] = set()
    for attr in ("href", "src"):
        refs.update(re.findall(rf'{attr}="([^"]+)"', html))
    for srcset in re.findall(r'srcset="([^"]+)"', html, re.S):
        for candidate in srcset.split(","):
            token = candidate.strip().split()
            if token:
                refs.add(token[0])
    return refs


def collect_css_refs(css: str) -> set[str]:
    # Drop inline data: URIs first. The SVG grain texture contains its own
    # url(#filter) reference, which is not a file and must not be checked.
    css = re.sub(r"url\(\s*[\"']?data:[^)]*\)", "url(data:stripped)", css)
    return {
        m
        for m in re.findall(r"url\(['\"]?([^'\")]+)['\"]?\)", css)
        if not m.startswith(("data:", "#", "%23"))
    }


def resolve(ref: str, relative_to: pathlib.Path) -> pathlib.Path | None:
    """Map a reference to a file on disk, or None if it isn't a local path."""
    if re.match(r"^(https?:|mailto:|tel:|data:|#)", ref):
        return None
    ref = ref.split("#", 1)[0].split("?", 1)[0]
    if not ref:
        return None
    if ref.startswith("/"):
        return SITE / ref.lstrip("/")
    return relative_to / ref


def rel(path: pathlib.Path) -> str:
    try:
        return str(path.relative_to(REPO))
    except ValueError:
        return str(path)


def main() -> int:
    problems: list[str] = []
    checked = 0

    if not SITE.is_dir():
        print(f"FAIL — assets directory missing: {rel(SITE)}")
        return 1

    targets: list[tuple[pathlib.Path, object, pathlib.Path]] = [
        (html, collect_html_refs, html.parent) for html in sorted(SITE.rglob("*.html"))
    ]
    css = SITE / "assets" / "styles.css"
    targets.append((css, collect_css_refs, css.parent))

    for source, collector, base in targets:
        if not source.exists():
            problems.append(f"missing source file: {rel(source)}")
            continue
        for ref in sorted(collector(source.read_text(encoding="utf-8"))):
            if ref in REDIRECT_ONLY:
                continue
            path = resolve(ref, base)
            if path is None:
                continue
            checked += 1
            if not path.exists():
                problems.append(f"{rel(source)} -> {ref} (no such file: {rel(path)})")

    required = [
        "wrangler.jsonc",
        "public/index.html",
        "public/404.html",
        "public/robots.txt",
        "public/sitemap.xml",
        "public/_redirects",
        "public/_headers",
        "public/assets/styles.css",
        "public/assets/img/og-card.jpg",
    ]
    for name in required:
        checked += 1
        if not (REPO / name).exists():
            problems.append(f"required file missing: {name}")

    # The assets directory in wrangler.jsonc must match where the files are.
    wrangler = (REPO / "wrangler.jsonc").read_text(encoding="utf-8")
    if '"directory": "./public/"' not in wrangler:
        problems.append('wrangler.jsonc assets.directory is not "./public/"')

    if problems:
        print(f"FAIL — {len(problems)} problem(s) across {checked} references:\n")
        for p in problems:
            print(f"  · {p}")
        return 1

    print(f"OK — {checked} local references all resolve.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
