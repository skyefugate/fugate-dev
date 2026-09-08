#!/usr/bin/env python3
"""Re-download the self-hosted latin font subsets from Google Fonts.

The .woff2 files in assets/fonts are committed, so this is only needed if you
change the type. Fonts are self-hosted on purpose: no third-party request, no
privacy footnote, and the CSP in _headers can stay at font-src 'self'.
"""

import pathlib
import re
import urllib.request

UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0 Safari/537.36"
)

# family spec -> output filename. Fraunces is requested as a weight *range* so
# Google serves one variable file instead of a static file per weight.
WANTED = [
    ("Fraunces:opsz,wght@9..144,300..700", "fraunces-var-latin.woff2"),
    ("IBM+Plex+Mono:wght@400", "ibm-plex-mono-400-latin.woff2"),
    ("IBM+Plex+Mono:wght@500", "ibm-plex-mono-500-latin.woff2"),
]

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "fonts"


def latin_woff2(family_spec: str) -> str:
    url = f"https://fonts.googleapis.com/css2?family={family_spec}&display=swap"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    css = urllib.request.urlopen(req, timeout=40).read().decode()

    for block in re.findall(r"@font-face\s*\{(.*?)\}", css, re.S):
        unicode_range = re.search(r"unicode-range:\s*([^;]+);", block)
        # The latin subset is the one containing basic latin + latin-1.
        if not unicode_range or "U+0000-00FF" not in unicode_range.group(1):
            continue
        return re.search(r"url\((https://[^)]+\.woff2)\)", block).group(1)

    raise SystemExit(f"no latin subset found for {family_spec}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for spec, filename in WANTED:
        dest = OUT / filename
        urllib.request.urlretrieve(latin_woff2(spec), dest)
        print(f"{dest.stat().st_size / 1024:7.1f} KB  {filename}")
    print(
        "\nReminder: the unicode-range in assets/styles.css must match what "
        "Google served. Check it if you change families."
    )


if __name__ == "__main__":
    main()
