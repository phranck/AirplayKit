#!/usr/bin/env python3
"""
Lifts one function out of a Swift file and prints it as highlighted HTML.

The page shows code that has to work, and the only code known to work is the
code the compiler saw. So the page does not hold a copy: the build takes the
function out of the example, which CI builds on both platforms, and puts it in.

Usage: render-snippet.py <swift file> <function name>
"""

import html
import re
import sys

KEYWORDS = {
    "as", "break", "case", "catch", "continue", "default", "do", "else", "enum",
    "extension", "false", "final", "for", "func", "guard", "if", "import", "in",
    "init", "let", "nil", "private", "public", "return", "self", "static",
    "struct", "switch", "throw", "throws", "true", "try", "var", "where", "while",
}

# Anything that starts with a capital is a type in Swift by convention, and the
# convention holds throughout this project.
TYPE = re.compile(r"\b[A-Z][A-Za-z0-9_]*\b")
NUMBER = re.compile(r"\b\d+(?:\.\d+)?\b")
WORD = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")


def extract(source: str, name: str) -> str:
    """The function, with the documentation comment above it, to its closing brace."""
    start = source.index(f"func {name}(")

    # Walk back over the documentation comment that introduces it.
    lines = source[:start].split("\n")
    while lines and lines[-1].lstrip().startswith("///"):
        lines.pop()
        start -= len(lines[-1]) + 1 if lines else 0

    head = source.rindex("\n", 0, source.index(f"func {name}("))
    comment_start = head
    for line in reversed(source[:head].split("\n")):
        if not line.lstrip().startswith("///"):
            break
        comment_start -= len(line) + 1

    depth = 0
    index = source.index("{", start)
    end = index
    while index < len(source):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                break
        index += 1

    return source[comment_start:end].strip("\n")


def highlight(code: str) -> str:
    """Wraps keywords, types, strings, numbers and comments in the page's classes."""
    out = []

    for line in code.split("\n"):
        comment = ""
        position = line.find("//")
        if position >= 0 and line.count('"', 0, position) % 2 == 0:
            comment = line[position:]
            line = line[:position]

        pieces = []
        rest = line
        while rest:
            quote = rest.find('"')
            if quote < 0:
                pieces.append(("code", rest))
                break
            pieces.append(("code", rest[:quote]))
            closing = rest.find('"', quote + 1)
            if closing < 0:
                pieces.append(("string", rest[quote:]))
                break
            pieces.append(("string", rest[quote:closing + 1]))
            rest = rest[closing + 1:]

        rendered = []
        for kind, piece in pieces:
            if kind == "string":
                rendered.append(f'<span class="s">{html.escape(piece)}</span>')
                continue

            def mark(match):
                word = match.group(0)
                if word in KEYWORDS:
                    return f'<span class="k">{word}</span>'
                if TYPE.fullmatch(word):
                    return f'<span class="t">{word}</span>'
                return word

            piece = html.escape(piece)
            piece = WORD.sub(mark, piece)
            piece = NUMBER.sub(lambda m: f'<span class="n">{m.group(0)}</span>', piece)
            rendered.append(piece)

        if comment:
            rendered.append(f'<span class="c">{html.escape(comment)}</span>')

        out.append("".join(rendered))

    return "\n".join(out)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    source = open(sys.argv[1], encoding="utf-8").read()
    print(highlight(extract(source, sys.argv[2])), end="")

    return 0


if __name__ == "__main__":
    sys.exit(main())
