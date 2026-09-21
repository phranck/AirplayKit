#!/usr/bin/env python3
"""
Adds a stylesheet link to every page of a generated site.

Swift-DocC-Render writes one shell per page, so a stylesheet that is to apply
everywhere has to be named in each of them. There is no hook for this in docc.

Usage: inject-stylesheet.py <directory> <href>
"""

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    root = Path(sys.argv[1])
    link = f'<link rel="stylesheet" href="{sys.argv[2]}">'
    touched = 0

    for page in root.rglob("index.html"):
        text = page.read_text(encoding="utf-8")
        if link in text or "</head>" not in text:
            continue

        page.write_text(text.replace("</head>", f"{link}</head>", 1), encoding="utf-8")
        touched += 1

    print(f"stylesheet added to {touched} page(s)")

    return 0 if touched else 1


if __name__ == "__main__":
    sys.exit(main())
