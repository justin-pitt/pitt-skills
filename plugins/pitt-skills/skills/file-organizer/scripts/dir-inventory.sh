#!/usr/bin/env bash
# file-organizer/scripts/dir-inventory.sh
#
# Quick inventory of a directory tree the file-organizer skill needs before
# proposing structure changes:
#   - Total file/dir counts
#   - Type breakdown via `file` (groups: image / video / audio / text / archive / binary)
#   - Top 20 largest files
#   - Most-recently and least-recently modified files
#
# Usage:
#   ./dir-inventory.sh [path]            # default cwd
#   ./dir-inventory.sh --top 30 [path]   # tweak top-N for largest files

set -euo pipefail

TOP=20
PATH_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --top) TOP="$2"; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) PATH_ARG="$1"; shift ;;
    esac
done
ROOT="${PATH_ARG:-.}"

if [ ! -d "$ROOT" ]; then
    echo "not a directory: $ROOT" >&2
    exit 1
fi

ROOT_ABS="$(cd "$ROOT" && pwd)"

echo "## inventory — $ROOT_ABS"
echo

FILE_COUNT="$(find "$ROOT" -type f 2>/dev/null | wc -l | tr -d ' ')"
DIR_COUNT="$(find "$ROOT" -type d 2>/dev/null | wc -l | tr -d ' ')"
TOTAL_BYTES="$(du -sb "$ROOT" 2>/dev/null | awk '{print $1}' || echo unknown)"
echo "files: $FILE_COUNT"
echo "directories: $DIR_COUNT"
echo "total bytes: $TOTAL_BYTES"
echo

echo "## type breakdown (file(1) primary type)"
find "$ROOT" -type f -print0 2>/dev/null \
  | xargs -0 -n 50 file -b 2>/dev/null \
  | awk '{
      lc = tolower($0);
      if (lc ~ /image|jpeg|jpg|png|gif|bitmap|webp|tiff|svg/) { c["image"]++ }
      else if (lc ~ /video|mpeg|matroska|quicktime|mp4/) { c["video"]++ }
      else if (lc ~ /audio|mpeg audio|wave|aiff|flac|ogg/) { c["audio"]++ }
      else if (lc ~ /ascii text|utf-8 text|unicode text|ascii english text/) { c["text"]++ }
      else if (lc ~ /archive|zip|tar|gzip|compressed|rar|7-zip/) { c["archive"]++ }
      else if (lc ~ /executable|elf|pe32|mach-o/) { c["executable"]++ }
      else { c["other"]++ }
  } END { for (k in c) printf "  %-12s %d\n", k, c[k] }' \
  | sort -k2 -nr
echo

echo "## top $TOP largest files"
find "$ROOT" -type f -print0 2>/dev/null \
  | xargs -0 du -h 2>/dev/null \
  | sort -rh \
  | head -n "$TOP"
echo

echo "## 5 most recently modified"
find "$ROOT" -type f -printf '%T@ %p\n' 2>/dev/null \
  | sort -rn | head -5 \
  | awk '{ sub(/^[0-9.]+\s/,"",$0); print "  " $0 }'
echo

echo "## 5 least recently modified"
find "$ROOT" -type f -printf '%T@ %p\n' 2>/dev/null \
  | sort -n | head -5 \
  | awk '{ sub(/^[0-9.]+\s/,"",$0); print "  " $0 }'
