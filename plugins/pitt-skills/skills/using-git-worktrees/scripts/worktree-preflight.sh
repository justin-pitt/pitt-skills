#!/usr/bin/env bash
# using-git-worktrees/scripts/worktree-preflight.sh
#
# Pick a worktree root location per the skill's priority ladder, then verify
# safety:
#   1. If $WORKTREES_DIR is set, use it.
#   2. Else if a sibling `<repo>-worktrees/` exists, use that.
#   3. Else propose `.worktrees/` inside the repo (and check that it's gitignored).
#
# Output (5 lines, last line is "OK" or "WARN: ..."):
#   chosen_strategy=...
#   chosen_path=...
#   in_repo=true|false
#   gitignored=true|false|n/a
#   status=OK|WARN
#
# Exit code: 0 on safe choice, 1 on unsafe (project-local but not gitignored).

set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "not a git work tree" >&2
    exit 2
fi

REPO_TOPLEVEL="$(git rev-parse --show-toplevel)"
REPO_NAME="$(basename "$REPO_TOPLEVEL")"

CHOSEN=""
STRATEGY=""

if [ -n "${WORKTREES_DIR:-}" ]; then
    CHOSEN="$WORKTREES_DIR"
    STRATEGY="env:WORKTREES_DIR"
elif [ -d "$(dirname "$REPO_TOPLEVEL")/${REPO_NAME}-worktrees" ]; then
    CHOSEN="$(dirname "$REPO_TOPLEVEL")/${REPO_NAME}-worktrees"
    STRATEGY="sibling-folder"
else
    CHOSEN="$REPO_TOPLEVEL/.worktrees"
    STRATEGY="project-local-default"
fi

IN_REPO=false
case "$CHOSEN" in
    "$REPO_TOPLEVEL"/*) IN_REPO=true ;;
esac

GITIGNORED="n/a"
STATUS="OK"
if [ "$IN_REPO" = "true" ]; then
    REL="${CHOSEN#$REPO_TOPLEVEL/}"
    if (cd "$REPO_TOPLEVEL" && git check-ignore -q "$REL"); then
        GITIGNORED="true"
    else
        GITIGNORED="false"
        STATUS="WARN: project-local but not gitignored — add `.worktrees/` to .gitignore before creating worktrees here"
    fi
fi

echo "chosen_strategy=$STRATEGY"
echo "chosen_path=$CHOSEN"
echo "in_repo=$IN_REPO"
echo "gitignored=$GITIGNORED"
echo "status=$STATUS"

[ "$STATUS" = "OK" ] || exit 1
