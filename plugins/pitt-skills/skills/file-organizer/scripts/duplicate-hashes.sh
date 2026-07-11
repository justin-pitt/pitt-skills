#!/usr/bin/env bash
# file-organizer/scripts/duplicate-hashes.sh
#
# Find duplicate-content files in a directory by SHA-256 hash, then group
# them. Skips files larger than --max-bytes (default 100 MB) to avoid
# hashing huge binaries.
#
# Usage:
#   ./duplicate-hashes.sh [path]
#   ./duplicate-hashes.sh --max-bytes 50000000 ./pics
#   ./duplicate-hashes.sh --json [path]

set -euo pipefail

MAX_BYTES=$((100 * 1024 * 1024))
JSON=0
PATH_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --max-bytes) MAX_BYTES="$2"; shift 2 ;;
        --json) JSON=1; shift ;;
        -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
        *) PATH_ARG="$1"; shift ;;
    esac
done
ROOT="${PATH_ARG:-.}"

if [ ! -d "$ROOT" ]; then
    echo "not a directory: $ROOT" >&2
    exit 1
fi

HASHER="sha256sum"
if ! command -v "$HASHER" >/dev/null 2>&1; then
    if command -v shasum >/dev/null 2>&1; then
        HASHER="shasum -a 256"
    else
        echo "neither sha256sum nor shasum available" >&2
        exit 1
    fi
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

while IFS= read -r -d '' f; do
    SIZE="$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)"
    if [ "$SIZE" -gt "$MAX_BYTES" ]; then
        continue
    fi
    H="$($HASHER "$f" 2>/dev/null | awk '{print $1}')"
    [ -n "$H" ] && printf '%s\t%s\t%s\n' "$H" "$SIZE" "$f" >> "$TMP"
done < <(find "$ROOT" -type f -print0 2>/dev/null)

if [ "$JSON" -eq 1 ]; then
    if ! command -v python3 >/dev/null 2>&1; then
        echo "python3 required for --json" >&2
        exit 1
    fi
    python3 - "$TMP" <<'PY'
import collections, json, sys
groups = collections.defaultdict(list)
sizes = {}
with open(sys.argv[1], encoding='utf-8') as f:
    for line in f:
        parts = line.rstrip('\n').split('\t', 2)
        if len(parts) != 3:
            continue
        h, size, path = parts
        groups[h].append(path)
        sizes[h] = int(size)
dupes = []
for h, paths in groups.items():
    if len(paths) > 1:
        dupes.append({"hash": h, "size_bytes": sizes[h], "wasted_bytes": sizes[h] * (len(paths) - 1), "files": sorted(paths)})
dupes.sort(key=lambda d: d["wasted_bytes"], reverse=True)
print(json.dumps({"duplicate_groups": dupes, "total_groups": len(dupes), "total_wasted_bytes": sum(d["wasted_bytes"] for d in dupes)}, indent=2))
PY
    exit 0
fi

echo "## duplicate hashes — $(cd "$ROOT" && pwd)"
sort "$TMP" \
  | awk -F'\t' '{ count[$1]++; entries[$1]=entries[$1]"\n  "$3; size[$1]=$2 } END {
        for (h in count) if (count[h] > 1) printf "## hash %s (%d copies, each %s bytes)%s\n\n", h, count[h], size[h], entries[h]
    }' \
  | sed '/^$/N;/^\n$/D'
