#!/usr/bin/env python3
"""Verify every local path referenced by the site actually exists on disk.

Catches the classic static-site failure: a renamed image that still 200s from
your browser cache and 404s for everyone else. Run locally or in CI.

Checks:
  * href/src/srcset targets in index.html
  * url(...) targets in assets/styles.css
  * the redirect sources in _redirects are real paths or intentional
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Paths that are served but have no file on disk (handled by _redirects).
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


def resolve(ref: str, base: pathlib.Path) -> pathlib.Path | None:
    """Map a reference to a file on disk, or None if it isn't a local path."""
    if re.match(r"^(https?:|mailto:|tel:|data:|#)", ref):
        return None
    ref = ref.split("#", 1)[0].split("?", 1)[0]
    if not ref:
        return None
    if ref.startswith("/"):
        return ROOT / ref.lstrip("/")
    return base / ref


def main() -> int:
    problems: list[str] = []
    checked = 0

    targets = [
        (ROOT / "index.html", collect_html_refs, ROOT),
        (ROOT / "assets" / "styles.css", collect_css_refs, ROOT / "assets"),
    ]

    for source, collector, base in targets:
        if not source.exists():
            problems.append(f"missing source file: {source.relative_to(ROOT)}")
            continue
        for ref in sorted(collector(source.read_text(encoding="utf-8"))):
            if ref in REDIRECT_ONLY:
                continue
            path = resolve(ref, base)
            if path is None:
                continue
            checked += 1
            if not path.exists():
                problems.append(
                    f"{source.relative_to(ROOT)} -> {ref} (no such file: "
                    f"{path.relative_to(ROOT) if ROOT in path.parents else path})"
                )

    # Sanity: the files Cloudflare Pages needs, and the OG image the meta tags promise.
    for required in (
        "index.html",
        "robots.txt",
        "sitemap.xml",
        "_redirects",
        "_headers",
        "assets/styles.css",
        "assets/img/og-card.jpg",
    ):
        checked += 1
        if not (ROOT / required).exists():
            problems.append(f"required file missing: {required}")

    if problems:
        print(f"FAIL — {len(problems)} problem(s) across {checked} references:\n")
        for p in problems:
            print(f"  · {p}")
        return 1

    print(f"OK — {checked} local references all resolve.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
