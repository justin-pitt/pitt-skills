#!/usr/bin/env bash
# requesting-code-review/scripts/review-range-shas.sh
#
# Pick a stable BASE_SHA / HEAD_SHA pair for code review, plus a shortlog
# count between them. Default base: merge-base with `origin/main`.
#
# Usage:
#   ./review-range-shas.sh                       # base = origin/main
#   ./review-range-shas.sh --base origin/develop
#   ./review-range-shas.sh --base HEAD~5
#   ./review-range-shas.sh --json
#
# Output (text mode):
#   BASE_REF=...
#   BASE_SHA=...
#   HEAD_SHA=...
#   COMMITS_AHEAD=N

set -euo pipefail

BASE_REF="origin/main"
JSON=0

while [ $# -gt 0 ]; do
    case "$1" in
        --base) BASE_REF="$2"; shift 2 ;;
        --json) JSON=1; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "not a git work tree" >&2
    exit 1
fi

# If origin/main isn't fetched, fall back to local main, then master.
if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
    for fallback in main master; do
        if git rev-parse --verify --quiet "$fallback" >/dev/null; then
            BASE_REF="$fallback"
            break
        fi
    done
fi

if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
    echo "could not resolve base ref: $BASE_REF" >&2
    exit 1
fi

BASE_SHA="$(git merge-base "$BASE_REF" HEAD)"
HEAD_SHA="$(git rev-parse HEAD)"
COMMITS_AHEAD="$(git rev-list --count "${BASE_SHA}..${HEAD_SHA}")"

if [ "$JSON" -eq 1 ]; then
    printf '{"base_ref":"%s","base_sha":"%s","head_sha":"%s","commits_ahead":%s}\n' \
        "$BASE_REF" "$BASE_SHA" "$HEAD_SHA" "$COMMITS_AHEAD"
    exit 0
fi

echo "BASE_REF=$BASE_REF"
echo "BASE_SHA=$BASE_SHA"
echo "HEAD_SHA=$HEAD_SHA"
echo "COMMITS_AHEAD=$COMMITS_AHEAD"
