#!/usr/bin/env bash
# shipping-work/scripts/preflight.sh
#
# Gate checks that must pass before a commit is created. Prints one line per
# check and exits non-zero if any FAIL, so the caller can stop cleanly.
#
# The checks exist because each one is a way to ship something wrong that is
# expensive to undo after a push:
#
#   branch        committing straight onto the default branch
#   account       pushing as the wrong authenticated account, on a machine
#                 where more than one is logged in
#   email         committing under whatever global identity happens to be set,
#                 rather than the one this repo should use
#   secrets       staging a .env or key file
#   worktree      a rebase/merge left half-finished
#
# Usage:
#   ./preflight.sh              # check, print, exit 0/1
#   ./preflight.sh --json
#
# Requires git. `gh` is optional: the account check is reported as SKIP when
# gh is absent or the remote is not GitHub.

set -uo pipefail

JSON=0
[ "${1:-}" = "--json" ] && JSON=1

FAILED=0
ROWS=""

record() { # status | check | message
    ROWS="${ROWS}$1|$2|$3
"
    [ "$1" = "FAIL" ] && FAILED=1
    return 0
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "not a git work tree" >&2
    exit 2
}

# --- branch -----------------------------------------------------------------
BRANCH="$(git branch --show-current 2>/dev/null || true)"
DEFAULT="$(git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's@^origin/@@' || true)"
[ -n "$DEFAULT" ] || DEFAULT=main

if [ -z "$BRANCH" ]; then
    record FAIL branch "detached HEAD - check out a branch first"
elif [ "$BRANCH" = "$DEFAULT" ]; then
    record FAIL branch "on the default branch ($DEFAULT) - create a topic branch first"
else
    record PASS branch "on '$BRANCH' (default is '$DEFAULT')"
fi

# --- in-progress operation --------------------------------------------------
GITDIR="$(git rev-parse --git-dir)"
if [ -d "$GITDIR/rebase-merge" ] || [ -d "$GITDIR/rebase-apply" ]; then
    record FAIL worktree "a rebase is in progress - finish or abort it first"
elif [ -f "$GITDIR/MERGE_HEAD" ]; then
    record FAIL worktree "a merge is in progress - finish or abort it first"
elif [ -f "$GITDIR/CHERRY_PICK_HEAD" ]; then
    record FAIL worktree "a cherry-pick is in progress - finish or abort it first"
else
    record PASS worktree "no in-progress rebase/merge/cherry-pick"
fi

# --- commit identity --------------------------------------------------------
# A repo-local address is required, not inherited. On a machine that hosts
# repos belonging to more than one identity, the global value is wrong for at
# least one of them, and the mistake is only visible after the push.
LOCAL_EMAIL="$(git config --local user.email 2>/dev/null || true)"
if [ -z "$LOCAL_EMAIL" ]; then
    GLOBAL_EMAIL="$(git config --global user.email 2>/dev/null || echo "(none)")"
    record FAIL email "no repo-local user.email; would commit as '$GLOBAL_EMAIL'. Set: git config user.email <addr>"
else
    record PASS email "repo-local user.email is $LOCAL_EMAIL"
fi

# --- pushing account --------------------------------------------------------
# Asking gh what the ACTIVE account may do on THIS repo is account-agnostic:
# it needs no mapping table of accounts to owners, and it catches the case
# where a previous task left a different account active.
REMOTE="$(git remote get-url origin 2>/dev/null || true)"
if [ -z "$REMOTE" ]; then
    record SKIP account "no origin remote"
elif ! printf '%s' "$REMOTE" | grep -qi 'github\.com'; then
    record SKIP account "origin is not GitHub ($REMOTE)"
elif ! command -v gh >/dev/null 2>&1; then
    record SKIP account "gh not on PATH"
else
    PERM="$(gh repo view --json viewerPermission -q .viewerPermission 2>&1 | head -1)"
    ACTIVE="$(gh auth status 2>&1 | grep -B1 'Active account: true' | grep -oE 'account [A-Za-z0-9_-]+' | head -1 | sed 's/^account //')"
    case "$PERM" in
        ADMIN|WRITE|MAINTAIN)
            record PASS account "'$ACTIVE' has $PERM on this repo"
            ;;
        READ|TRIAGE|NONE)
            record FAIL account "'$ACTIVE' only has $PERM here - switch accounts (gh auth switch)"
            ;;
        *)
            # Includes "Could not resolve to a Repository", which is what a
            # private repo looks like to an account that cannot see it.
            record FAIL account "'$ACTIVE' cannot resolve this repo - wrong account? (gh auth switch)"
            ;;
    esac
fi

# --- secrets in the staged set ----------------------------------------------
STAGED="$(git diff --cached --name-only 2>/dev/null || true)"
if [ -z "$STAGED" ]; then
    record SKIP secrets "nothing staged yet - re-run after staging"
else
    BAD="$(printf '%s\n' "$STAGED" | grep -iE '(^|/)\.env($|\.)|\.(pem|p12|pfx|keystore|jks)$|(^|/)id_(rsa|dsa|ecdsa|ed25519)$|(^|/)\.npmrc$|(^|/)\.pypirc$' || true)"
    if [ -n "$BAD" ]; then
        record FAIL secrets "staged files look like secrets: $(printf '%s' "$BAD" | tr '\n' ' ')"
    else
        record PASS secrets "$(printf '%s\n' "$STAGED" | grep -c . ) staged file(s), none matching secret patterns"
    fi
fi

# --- output -----------------------------------------------------------------
if [ "$JSON" -eq 1 ]; then
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$ROWS" | jq -R -s '
            split("\n") | map(select(length > 0)) | map(split("|"))
            | map({status: .[0], check: .[1], message: .[2]})
            | {ok: (map(select(.status == "FAIL")) | length == 0), checks: .}'
        exit $FAILED
    fi
    echo '{"error":"jq required for --json"}' >&2
    exit 2
fi

printf '%s' "$ROWS" | while IFS='|' read -r st ck msg; do
    [ -n "$st" ] || continue
    printf '%-5s %-9s %s\n' "$st" "$ck" "$msg"
done

echo
if [ "$FAILED" -ne 0 ]; then
    echo "PREFLIGHT FAILED - fix the FAIL rows above before committing."
else
    echo "Preflight clean."
fi
exit $FAILED
