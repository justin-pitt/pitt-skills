#!/usr/bin/env python3
"""writing-plans/scripts/scan-plan-placeholders.py

Scan a plan or spec markdown for placeholder/red-flag patterns the
writing-plans skill considers blocking before handoff.

Patterns (case-insensitive):
    TBD, TODO, FIXME, XXX, ???
    <placeholder>, <PLACEHOLDER>, <fill-in>
    "implement later", "figure out", "decide later", "tbd later"
    bare "..." sequences in headings or task descriptions

Usage:
    python scan-plan-placeholders.py path/to/plan.md
    python scan-plan-placeholders.py --strict path/to/plan.md   # exit 1 on any hit

By default exit code 0 even with hits (informational).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

PATTERNS = [
    (re.compile(r"\bTBD\b", re.IGNORECASE), "TBD"),
    (re.compile(r"\bTODO\b", re.IGNORECASE), "TODO"),
    (re.compile(r"\bFIXME\b", re.IGNORECASE), "FIXME"),
    (re.compile(r"\bXXX\b"), "XXX"),
    (re.compile(r"\?\?\?"), "???"),
    (re.compile(r"<\s*placeholder\s*>", re.IGNORECASE), "<placeholder>"),
    (re.compile(r"<\s*fill[\s-]*in\s*>", re.IGNORECASE), "<fill-in>"),
    (re.compile(r"\bimplement\s+later\b", re.IGNORECASE), '"implement later"'),
    (re.compile(r"\bfigure\s+out\b", re.IGNORECASE), '"figure out"'),
    (re.compile(r"\bdecide\s+later\b", re.IGNORECASE), '"decide later"'),
    (re.compile(r"\btbd\s+later\b", re.IGNORECASE), '"tbd later"'),
]

HEADING_ELLIPSIS = re.compile(r"^#{1,6}\s.*\.\.\.\s*$")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("path")
    p.add_argument("--strict", action="store_true", help="exit non-zero if any pattern matches")
    args = p.parse_args()

    path = Path(args.path)
    if not path.is_file():
        print(f"not a file: {path}", file=sys.stderr)
        return 2

    hits: list[tuple[int, str, str]] = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        for regex, label in PATTERNS:
            if regex.search(line):
                hits.append((lineno, label, line.rstrip()))
        if HEADING_ELLIPSIS.match(line):
            hits.append((lineno, "trailing-ellipsis-heading", line.rstrip()))

    if not hits:
        print(f"OK — no placeholder patterns in {path}")
        return 0

    print(f"## placeholder findings — {path}")
    print(f"hits: {len(hits)}")
    print()
    for lineno, label, line in hits:
        print(f"  line {lineno}  [{label}]  {line}")
    return 1 if args.strict else 0


if __name__ == "__main__":
    sys.exit(main())
