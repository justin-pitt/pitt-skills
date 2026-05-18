#!/usr/bin/env python3
"""codebase-audit/scripts/project-inventory.py

Mechanical project-inventory dump for the codebase-audit skill: extension
histogram, total file count, and detected manifest files. Skips noise dirs
(.git, node_modules, dist, build, .next, target, __pycache__, .venv, venv).

Usage:
    python project-inventory.py [path]              # markdown
    python project-inventory.py --json [path]       # JSON
    python project-inventory.py --top 20 [path]     # limit ext histogram

Defaults: cwd, top 15 extensions, skips standard noise dirs.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter
from pathlib import Path

NOISE_DIRS = {
    ".git",
    "node_modules",
    "dist",
    "build",
    ".next",
    "target",
    "__pycache__",
    ".venv",
    "venv",
    ".tox",
    ".gradle",
    ".idea",
    ".vs",
    ".vscode",
}

MANIFEST_FILES = {
    "package.json",
    "pyproject.toml",
    "requirements.txt",
    "Pipfile",
    "Cargo.toml",
    "go.mod",
    "Gemfile",
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
    "composer.json",
    "Dockerfile",
    "docker-compose.yml",
    "docker-compose.yaml",
    "render.yaml",
    "vercel.json",
    "fly.toml",
    "manage.py",
    "Makefile",
}


def walk(root: Path) -> tuple[Counter, int, list[str]]:
    ext_counts: Counter = Counter()
    total = 0
    manifests: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in NOISE_DIRS]
        for fn in filenames:
            total += 1
            if fn in MANIFEST_FILES:
                manifests.append(str(Path(dirpath, fn).relative_to(root)))
            ext = Path(fn).suffix.lower()
            ext_counts[ext or "(no extension)"] += 1
    return ext_counts, total, sorted(manifests)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("path", nargs="?", default=".")
    p.add_argument("--json", action="store_true", help="machine-readable JSON")
    p.add_argument("--top", type=int, default=15, help="extensions to list (default 15)")
    args = p.parse_args()

    root = Path(args.path).resolve()
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 1

    ext_counts, total, manifests = walk(root)
    top_exts = ext_counts.most_common(args.top)

    if args.json:
        print(
            json.dumps(
                {
                    "root": str(root),
                    "total_files": total,
                    "extensions_top": [{"ext": e, "count": c} for e, c in top_exts],
                    "extensions_all_count": len(ext_counts),
                    "manifests": manifests,
                    "noise_dirs_skipped": sorted(NOISE_DIRS),
                },
                indent=2,
            )
        )
        return 0

    print(f"## project inventory — {root}")
    print()
    print(f"total files (excluding {', '.join(sorted(NOISE_DIRS))}): {total}")
    print()
    print(f"## top {args.top} extensions")
    width = max((len(e) for e, _ in top_exts), default=4)
    for ext, count in top_exts:
        print(f"  {ext:<{width}}  {count}")
    if len(ext_counts) > args.top:
        print(f"  ... and {len(ext_counts) - args.top} more extensions")
    print()
    print("## manifests detected")
    if manifests:
        for m in manifests:
            print(f"  {m}")
    else:
        print("  (none)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
