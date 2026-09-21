#!/usr/bin/env python3
"""
Replaces every <!--@snippet name--> in a page with that function, highlighted.

Usage: fill-snippets.py <html file> <swift file>
"""

import re
import subprocess
import sys
from pathlib import Path

MARKER = re.compile(r"<!--@snippet ([A-Za-z_][A-Za-z0-9_]*)-->")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    page = Path(sys.argv[1])
    swift = sys.argv[2]
    renderer = Path(__file__).with_name("render-snippet.py")

    text = page.read_text(encoding="utf-8")
    names = MARKER.findall(text)
    if not names:
        print("no snippet markers in the page", file=sys.stderr)
        return 1

    for name in names:
        rendered = subprocess.run([sys.executable, str(renderer), swift, name],
                                  capture_output=True, text=True, check=True).stdout
        text = text.replace(f"<!--@snippet {name}-->", rendered)

    page.write_text(text, encoding="utf-8")
    print(f"filled {len(names)} snippet(s)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
