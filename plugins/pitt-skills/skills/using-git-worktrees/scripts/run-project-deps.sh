#!/usr/bin/env bash
# using-git-worktrees/scripts/run-project-deps.sh
#
# Detect the project's stack and run the matching install command. Used after
# a fresh worktree checkout to bring deps online without prompting the model
# to remember every stack's incantation.
#
# Detection order (first match wins):
#   - package.json + pnpm-lock.yaml → pnpm install --frozen-lockfile
#   - package.json + yarn.lock      → yarn install --frozen-lockfile
#   - package.json                  → npm install
#   - pyproject.toml + uv.lock      → uv sync
#   - pyproject.toml                → pip install -e .
#   - requirements.txt              → pip install -r requirements.txt
#   - Cargo.toml                    → cargo fetch
#   - go.mod                        → go mod download
#   - Gemfile                       → bundle install
#
# Usage:
#   ./run-project-deps.sh             # auto-detect and run
#   ./run-project-deps.sh --dry-run   # print what would run
#   ./run-project-deps.sh --json      # detect only, no run, JSON output

set -euo pipefail

DRY=0
JSON=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1; shift ;;
        --json) JSON=1; shift ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

STACK=""
CMD=""

if [ -f package.json ] && [ -f pnpm-lock.yaml ]; then
    STACK="node-pnpm"; CMD="pnpm install --frozen-lockfile"
elif [ -f package.json ] && [ -f yarn.lock ]; then
    STACK="node-yarn"; CMD="yarn install --frozen-lockfile"
elif [ -f package.json ]; then
    STACK="node-npm"; CMD="npm install"
elif [ -f pyproject.toml ] && [ -f uv.lock ]; then
    STACK="python-uv"; CMD="uv sync"
elif [ -f pyproject.toml ]; then
    STACK="python-pip-editable"; CMD="pip install -e ."
elif [ -f requirements.txt ]; then
    STACK="python-pip-requirements"; CMD="pip install -r requirements.txt"
elif [ -f Cargo.toml ]; then
    STACK="rust"; CMD="cargo fetch"
elif [ -f go.mod ]; then
    STACK="go"; CMD="go mod download"
elif [ -f Gemfile ]; then
    STACK="ruby"; CMD="bundle install"
fi

if [ "$JSON" -eq 1 ]; then
    printf '{"stack": "%s", "command": "%s"}\n' "${STACK:-unknown}" "${CMD:-}"
    exit 0
fi

if [ -z "$CMD" ]; then
    echo "no recognized stack in $(pwd)"
    exit 1
fi

echo "stack: $STACK"
echo "command: $CMD"

if [ "$DRY" -eq 1 ]; then
    echo "(dry run — not executing)"
    exit 0
fi

eval "$CMD"
