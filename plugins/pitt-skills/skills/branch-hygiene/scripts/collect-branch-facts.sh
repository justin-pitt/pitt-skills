#!/usr/bin/env bash
# branch-hygiene/scripts/collect-branch-facts.sh
#
# Collects every input the branch-hygiene flow needs to categorize a repo's
# branches: default branch, local branches with upstream-track + last-commit
# date, remotes, worktrees, and (optionally) open PRs from `gh`.
#
# Usage:
#   ./collect-branch-facts.sh           # markdown sections
#   ./collect-branch-facts.sh --json    # one JSON object per line
#   ./collect-branch-facts.sh --sync    # also `git fetch --all --prune` first
#
# Exits non-zero if not in a git work tree. `gh pr list` failures are
# tolerated: PR data is omitted, the rest still works.

set -euo pipefail

JSON=0
SYNC=0
for arg in "$@"; do
    case "$arg" in
        --json) JSON=1 ;;
        --sync) SYNC=1 ;;
        -h|--help)
            sed -n '2,15p' "$0"
            exit 0
            ;;
        *)
            echo "unknown arg: $arg" >&2
            exit 2
            ;;
    esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "not a git work tree" >&2
    exit 1
fi

if [ "$SYNC" -eq 1 ]; then
    git fetch --all --prune >/dev/null 2>&1 || true
fi

DEFAULT_BRANCH="$(git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's@^origin/@@' || true)"
if [ -z "$DEFAULT_BRANCH" ]; then
    for fallback in main master; do
        if git show-ref --verify --quiet "refs/heads/$fallback"; then
            DEFAULT_BRANCH="$fallback"
            break
        fi
    done
fi

LOCALS="$(git branch --format='%(refname:short)|%(upstream:track)|%(committerdate:iso8601)|%(objectname:short)' || true)"
REMOTES="$(git branch -r --format='%(refname:short)' || true)"
WORKTREES="$(git worktree list --porcelain 2>/dev/null || true)"
PRS=""
if command -v gh >/dev/null 2>&1; then
    PRS="$(gh pr list --state open --json number,headRefName,baseRefName,mergeable,updatedAt 2>/dev/null || true)"
fi

if [ "$JSON" -eq 1 ]; then
    if ! command -v jq >/dev/null 2>&1; then
        echo "jq required for --json" >&2
        exit 1
    fi
    LOCALS_JSON="$(printf '%s\n' "$LOCALS" | jq -R -s '
        split("\n") | map(select(length > 0))
        | map(split("|"))
        | map({name: .[0], track: .[1], committerdate: .[2], short_sha: .[3]})')"
    REMOTES_JSON="$(printf '%s\n' "$REMOTES" | jq -R -s 'split("\n") | map(select(length > 0))')"
    PRS_JSON="${PRS:-[]}"
    jq -n \
      --arg default "$DEFAULT_BRANCH" \
      --argjson locals "$LOCALS_JSON" \
      --argjson remotes "$REMOTES_JSON" \
      --arg worktrees "$WORKTREES" \
      --argjson prs "$PRS_JSON" \
      '{default_branch: $default, locals: $locals, remotes: $remotes, worktrees_porcelain: $worktrees, prs: $prs}'
    exit 0
fi

echo "## default branch"
echo "${DEFAULT_BRANCH:-(unknown — fall back to main)}"
echo
echo "## local branches (name | upstream:track | committerdate | short-sha)"
echo "$LOCALS"
echo
echo "## remote branches"
echo "$REMOTES"
echo
echo "## worktrees (porcelain)"
echo "$WORKTREES"
echo
if [ -n "$PRS" ]; then
    echo "## open prs (gh pr list --json)"
    echo "$PRS"
else
    echo "## open prs"
    echo "(gh not on PATH or no GitHub remote — skipped)"
fi
