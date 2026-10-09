#!/usr/bin/env python3
"""subagent-driven-development/scripts/extract-plan-tasks.py

Parse a writing-plans-style plan file into a list of tasks. Each task block
starts with `### Task N:` (or `## Task N:`) and runs until the next task
heading (or end of file).

For each task we extract:
  - number (from heading)
  - title
  - status (`[ ]` / `[x]` from a checkbox in the heading or the first line)
  - body (everything after the heading until next task)
  - files (from any `**Files:**` block)

Usage:
    python extract-plan-tasks.py docs/superpowers/plans/2026-05-15-foo.md
    python extract-plan-tasks.py --status pending plan.md

Output is JSON on stdout.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

TASK_HEADING = re.compile(r"^(?P<level>#{2,3})\s+Task\s+(?P<num>\d+)\s*:?\s*(?P<title>.*?)\s*$")
CHECKBOX = re.compile(r"\[(?P<mark>[ xX])\]")
FILES_BLOCK = re.compile(r"^\*\*Files:\*\*\s*\n((?:^[-*]\s+.*\n?)+)", re.MULTILINE)


def parse(text: str) -> list[dict]:
    lines = text.splitlines()
    tasks: list[dict] = []
    current: dict | None = None
    body_buf: list[str] = []

    def finalize():
        nonlocal current, body_buf
        if current is None:
            return
        body = "\n".join(body_buf).strip()
        cb = CHECKBOX.search(current["title"]) or CHECKBOX.search(body[:200])
        status = "completed" if cb and cb.group("mark").lower() == "x" else "pending"
        files: list[str] = []
        m = FILES_BLOCK.search(body)
        if m:
            for raw in m.group(1).splitlines():
                raw = raw.strip().lstrip("-* ").strip()
                if raw:
                    files.append(raw)
        current["title"] = CHECKBOX.sub("", current["title"]).strip()
        current["status"] = status
        current["body"] = body
        current["files"] = files
        tasks.append(current)
        current = None
        body_buf = []

    for line in lines:
        m = TASK_HEADING.match(line)
        if m:
            finalize()
            current = {
                "number": int(m.group("num")),
                "title": m.group("title").strip(),
                "level": len(m.group("level")),
            }
            body_buf = []
        elif current is not None:
            body_buf.append(line)
    finalize()
    return tasks


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("path")
    p.add_argument("--status", choices=["pending", "completed"], help="filter by status")
    args = p.parse_args()

    path = Path(args.path)
    if not path.is_file():
        print(f"not a file: {path}", file=sys.stderr)
        return 2

    tasks = parse(path.read_text(encoding="utf-8"))
    if args.status:
        tasks = [t for t in tasks if t["status"] == args.status]

    print(json.dumps({"path": str(path), "task_count": len(tasks), "tasks": tasks}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
