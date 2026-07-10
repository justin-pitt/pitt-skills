#!/usr/bin/env python3
"""writing-skills/scripts/validate-skill-frontmatter.py

Mechanical frontmatter validation for SKILL.md files per agentskills.io spec
plus Claude Code extensions.

Checks:
  - File starts with `---\\n` and has a closing `---\\n` line
  - `name` present, 1-64 chars, regex ^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$, no `--`
  - `name` matches parent directory name
  - `description` present, 1-1024 chars
  - Description starts with "Use when" (warning, not error)
  - Total frontmatter ≤ 1024 chars (warning, soft)
  - `disable-model-invocation` and `user-invocable` are valid booleans if present

Usage:
    python validate-skill-frontmatter.py path/to/SKILL.md [path/to/another/SKILL.md ...]
    python validate-skill-frontmatter.py --glob 'plugins/pitt-skills/skills/*/SKILL.md'

Exit code 0 = all valid; 1 = at least one violation; 2 = bad invocation.
"""

from __future__ import annotations

import argparse
import glob as globlib
import re
import sys
from pathlib import Path

NAME_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$")


def parse_frontmatter(text: str) -> tuple[dict[str, str], int] | None:
    if not text.startswith("---\n") and not text.startswith("---\r\n"):
        return None
    nl = "\r\n" if "\r\n" in text[:200] else "\n"
    body = text[len("---" + nl) :]
    end = body.find(nl + "---" + nl)
    if end < 0:
        return None
    yaml_block = body[:end]
    fm: dict[str, str] = {}
    current_key = None
    folded_key: str | None = None
    folded_lines: list[str] = []
    for line in yaml_block.split(nl):
        if folded_key is not None:
            m = re.match(r"^\s+(\S.*)$", line)
            if m:
                folded_lines.append(m.group(1).strip())
                continue
            fm[folded_key] = " ".join(folded_lines)
            folded_key = None
            folded_lines = []
        m = re.match(r"^([A-Za-z][\w-]*):\s*(.*)$", line)
        if m:
            key, val = m.group(1), m.group(2)
            if val == ">" or val == "|":
                folded_key = key
                folded_lines = []
            elif val == "":
                fm[key] = ""
                current_key = key
            else:
                fm[key] = val.strip().strip('"').strip("'")
                current_key = None
        elif current_key and re.match(r"^\s\s\S", line):
            pass
    if folded_key is not None:
        fm[folded_key] = " ".join(folded_lines)
    return fm, len(yaml_block)


def validate_one(path: Path) -> list[str]:
    errors: list[str] = []
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        return [f"{path}: cannot read ({exc})"]

    parsed = parse_frontmatter(text)
    if parsed is None:
        return [f"{path}: missing or unterminated YAML frontmatter"]
    fm, fm_len = parsed

    name = fm.get("name", "").strip()
    desc = fm.get("description", "").strip()

    if not name:
        errors.append(f"{path}: missing `name`")
    else:
        if not NAME_RE.match(name):
            errors.append(
                f"{path}: name `{name}` violates spec (lowercase a-z0-9 + hyphens, 1-64 chars, no leading/trailing/consecutive hyphens)"
            )
        parent_name = path.parent.name
        if parent_name != name:
            errors.append(f"{path}: name `{name}` does not match parent dir `{parent_name}`")

    if not desc:
        errors.append(f"{path}: missing `description`")
    elif len(desc) > 1024:
        errors.append(f"{path}: description is {len(desc)} chars (max 1024)")

    if fm_len > 1024:
        errors.append(f"{path}: frontmatter body is {fm_len} chars; spec says max 1024 (warning)")

    if not desc.lower().startswith("use when"):
        errors.append(f"{path}: description should start with 'Use when ...' (warning)")

    for boolfield in ("disable-model-invocation", "user-invocable"):
        if boolfield in fm:
            v = fm[boolfield].strip().lower()
            if v not in {"true", "false"}:
                errors.append(f"{path}: `{boolfield}` must be true or false (got `{fm[boolfield]}`)")

    return errors


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("paths", nargs="*", help="SKILL.md files to validate")
    p.add_argument("--glob", help="glob pattern (recursive ** allowed)")
    args = p.parse_args()

    targets: list[Path] = [Path(p_) for p_ in args.paths]
    if args.glob:
        targets.extend(Path(p_) for p_ in globlib.glob(args.glob, recursive=True))
    if not targets:
        print("no paths provided", file=sys.stderr)
        return 2

    all_errors: list[str] = []
    for t in targets:
        all_errors.extend(validate_one(t))

    if not all_errors:
        print(f"OK — {len(targets)} skill(s) validated")
        return 0
    for e in all_errors:
        print(e)
    return 1


if __name__ == "__main__":
    sys.exit(main())
