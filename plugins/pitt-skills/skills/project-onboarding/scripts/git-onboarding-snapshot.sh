#!/usr/bin/env bash
# project-onboarding/scripts/git-onboarding-snapshot.sh
#
# Bundle the standard git-state quad the project-onboarding flow always
# captures: current branch, working tree status, recent log, branches with
# upstream-tracking. One labeled section per command.
#
# Usage:
#   ./git-onboarding-snapshot.sh        # default (10 commits, 20 branches)
#   ./git-onboarding-snapshot.sh -n 20  # tweak commit count
#   ./git-onboarding-snapshot.sh --json # JSON envelope (requires jq)
#
# Exits non-zero if not in a git work tree.

set -euo pipefail

LOG_LINES=10
BRANCH_LINES=20
JSON=0

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--log-lines) LOG_LINES="$2"; shift 2 ;;
        --branch-lines) BRANCH_LINES="$2"; shift 2 ;;
        --json) JSON=1; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "not a git work tree" >&2
    exit 1
fi

CURRENT="$(git branch --show-current 2>/dev/null || true)"
STATUS="$(git status --porcelain 2>/dev/null || true)"
LOG="$(git log --oneline -"$LOG_LINES" 2>/dev/null || true)"
BRANCHES="$(git branch -vv 2>/dev/null | head -"$BRANCH_LINES" || true)"

if [ "$JSON" -eq 1 ]; then
    if ! command -v jq >/dev/null 2>&1; then
        echo "jq required for --json" >&2
        exit 1
    fi
    jq -n \
      --arg current "$CURRENT" \
      --arg status "$STATUS" \
      --arg log "$LOG" \
      --arg branches "$BRANCHES" \
      '{current_branch: $current, status_porcelain: $status, recent_log: $log, branches_vv_truncated: $branches}'
    exit 0
fi

echo "## current branch"
echo "${CURRENT:-(detached HEAD)}"
echo
echo "## working tree (porcelain — empty means clean)"
echo "$STATUS"
echo
echo "## recent commits (last $LOG_LINES)"
echo "$LOG"
echo
echo "## branches with upstream tracking (first $BRANCH_LINES)"
echo "$BRANCHES"
