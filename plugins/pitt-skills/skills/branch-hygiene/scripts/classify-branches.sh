#!/usr/bin/env bash
# branch-hygiene/scripts/classify-branches.sh
#
# Labels every local branch as Protected / Merged / OpenPR / SquashMerged /
# MovedSincePR / GoneNoProof / StaleUnmerged / Active, using git ancestry AND
# merged-PR data.
#
# Why this exists: `git branch --merged` only sees ancestry. A squash merge
# rewrites the commits, so the branch tip is never an ancestor of the default
# branch and the branch looks unmerged forever. On a squash-merge repo the
# ancestry check reports near-zero deletable branches while most of them have
# in fact shipped. Measured on one real repo: `--merged` found 0 of 6.
#
# The safety guard is headRefOid. A merged PR proves the NAME shipped; only a
# tip-SHA match proves THIS LOCAL BRANCH is what shipped. When they differ the
# branch has moved since the PR merged (extra local commits, or a reused name),
# so it is labelled MovedSincePR for a human to look at, never auto-deleted.
#
# Ordering matters: merge evidence is checked BEFORE a gone upstream. A branch
# whose remote was deleted is not thereby proven merged - the remote may have
# been deleted with the work unmerged. Those become GoneNoProof, not "safe".
#
# Usage:
#   ./classify-branches.sh                  # table
#   ./classify-branches.sh --json           # machine-readable
#   ./classify-branches.sh --stale-days 30  # StaleUnmerged threshold (default 30)
#   ./classify-branches.sh --protect a,b    # extra protected branches
#
# Requires jq. Tolerates a missing/failing `gh` (PR-derived labels are skipped).

set -euo pipefail

JSON=0
STALE_DAYS=30
EXTRA_PROTECT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --json) JSON=1; shift ;;
        --stale-days) STALE_DAYS="$2"; shift 2 ;;
        --protect) EXTRA_PROTECT="$2"; shift 2 ;;
        -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git work tree" >&2; exit 1; }

# jq builds on Windows emit CRLF. A trailing CR on a SHA makes both string
# equality and `git merge-base --is-ancestor` fail silently - the branch simply
# never matches anything. Strip it at the one place jq output is read.
jqr() { jq -r "$@" | tr -d '\r'; }

HERE="$(cd "$(dirname "$0")" && pwd)"
FACTS="$("$HERE/collect-branch-facts.sh" --json)"

DEFAULT_BRANCH="$(printf '%s' "$FACTS" | jqr '.default_branch')"
if [ -z "$DEFAULT_BRANCH" ] || [ "$DEFAULT_BRANCH" = "null" ]; then
    DEFAULT_BRANCH=main
fi

PROTECTED="main master develop dev staging production prod release stable"
if [ -n "$EXTRA_PROTECT" ]; then
    PROTECTED="$PROTECTED $(printf '%s' "$EXTRA_PROTECT" | tr ',' ' ')"
fi

# Compare against the remote default branch when it exists; a stale local
# default branch would under-report what has merged.
BASE="origin/$DEFAULT_BRANCH"
git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 || BASE="$DEFAULT_BRANCH"

NOW="$(date +%s)"
ROWS=""

BRANCH_LINES="$(printf '%s' "$FACTS" | jqr '.locals[] | "\(.name)|\(.track)|\(.committerdate)|\(.sha)"')"

while IFS='|' read -r name track cdate sha; do
    [ -n "$name" ] || continue

    label=""
    detail=""

    for p in $PROTECTED; do
        if [ "$name" = "$p" ]; then
            label="Protected"
            break
        fi
    done

    if [ -z "$label" ] && git merge-base --is-ancestor "$sha" "$BASE" 2>/dev/null; then
        label="Merged"
        detail="ancestor of $BASE"
    fi

    if [ -z "$label" ]; then
        open_pr="$(printf '%s' "$FACTS" | jqr --arg n "$name" '[.prs[]? | select(.headRefName == $n)] | sort_by(.number) | last | .number // empty')"
        if [ -n "$open_pr" ]; then
            label="OpenPR"
            detail="PR #$open_pr open"
        fi
    fi

    if [ -z "$label" ]; then
        # One jq call per branch, not three: the per-branch lookup dominates
        # runtime on a many-branch sweep. Tab-delimited because a branch name
        # may contain "|" but never a tab.
        pr_row="$(printf '%s' "$FACTS" | jqr --arg n "$name" '[.merged_prs[]? | select(.headRefName == $n)] | sort_by(.number) | last | if . == null then empty else [(.number|tostring), .headRefOid, .mergedAt] | @tsv end')"
        if [ -n "$pr_row" ]; then
            IFS=$'	' read -r pr_num pr_oid pr_at <<<"$pr_row"
            if [ "$pr_oid" = "$sha" ]; then
                label="SquashMerged"
                detail="PR #$pr_num merged $pr_at, tip matches"
            else
                label="MovedSincePR"
                detail="PR #$pr_num merged $pr_at, local tip differs"
            fi
        fi
    fi

    if [ -z "$label" ] && [ "$track" = "[gone]" ]; then
        # Remote branch is gone, but nothing proves it merged: not an ancestor,
        # and no merged PR under this name within the fetch limit. Could be a PR
        # older than the limit, or a branch deleted without merging. Human call.
        label="GoneNoProof"
        detail="upstream deleted, no merge evidence"
    fi

    if [ -z "$label" ]; then
        ts="$(date -d "$cdate" +%s 2>/dev/null || echo "$NOW")"
        age=$(( (NOW - ts) / 86400 ))
        if [ "$age" -gt "$STALE_DAYS" ]; then
            label="StaleUnmerged"
            detail="${age}d since last commit"
        else
            label="Active"
            detail="${age}d since last commit"
        fi
    fi

    ROWS="${ROWS}${name}|${label}|${detail}
"
done <<EOF
$BRANCH_LINES
EOF

if [ "$JSON" -eq 1 ]; then
    printf '%s' "$ROWS" | jq -R -s --arg default "$DEFAULT_BRANCH" --arg base "$BASE" '
        split("\n") | map(select(length > 0)) | map(split("|"))
        | map({branch: .[0], label: .[1], detail: .[2]})
        | {default_branch: $default, compared_against: $base, branches: .}'
    exit 0
fi

printf '%-52s %-14s %s\n' "BRANCH" "LABEL" "DETAIL"
printf '%s' "$ROWS" | while IFS='|' read -r n l d; do
    [ -n "$n" ] || continue
    printf '%-52s %-14s %s\n' "$n" "$l" "$d"
done

echo
echo "Compared against: $BASE"
echo "Safe to delete:   Merged, SquashMerged."
echo "Needs a human:    MovedSincePR (tip moved after the PR merged),"
echo "                  GoneNoProof (remote deleted, merge unproven)."
echo "Left alone:       Protected, OpenPR, StaleUnmerged, Active."
echo
echo "NOTE: run 'git branch -d' first, always. It accepts a branch merged into"
echo "its UPSTREAM or into HEAD, so on a SquashMerged branch it succeeds while"
echo "origin/<name> still points at the tip, and refuses once that ref is gone"
echo "or pruned. Escalate to -D only after -d has actually refused, and only"
echo "for SquashMerged - there the merged PR is the evidence, not git ancestry."
