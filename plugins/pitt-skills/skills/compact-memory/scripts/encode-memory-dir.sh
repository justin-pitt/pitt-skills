#!/usr/bin/env bash
# compact-memory/scripts/encode-memory-dir.sh
#
# Encode a workspace path into the directory name Claude Code uses under
# ~/.claude/projects/. The rule: drop the drive letter, then replace `:`,
# `/`, and `\` with `-`.
#
# Usage:
#   ./encode-memory-dir.sh "C:\Code\pitt-skills"
#   ./encode-memory-dir.sh --validate    # also `jq empty ~/.claude/settings.json`
#   ./encode-memory-dir.sh "$PWD"        # default to cwd
#
# Prints two lines: the encoded segment, and the full memory dir path.

set -euo pipefail

VALIDATE=0
P=""
while [ $# -gt 0 ]; do
    case "$1" in
        --validate) VALIDATE=1; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) P="$1"; shift ;;
    esac
done
P="${P:-$PWD}"

# Strip a drive letter at the start (e.g., "C:" or "c:"). On unix paths this no-ops.
if [[ "$P" =~ ^([A-Za-z]): ]]; then
    P="${P:2}"
fi
# Replace : / \ with -
ENC="${P//:/-}"
ENC="${ENC//\//-}"
ENC="${ENC//\\/-}"
# Collapse leading dashes that came from absolute paths starting with /
ENC="${ENC#-}"

CLAUDE_HOME_DIR="${CLAUDE_HOME:-$HOME/.claude}"
MEMORY_DIR="$CLAUDE_HOME_DIR/projects/$ENC/memory"

echo "$ENC"
echo "$MEMORY_DIR"

if [ "$VALIDATE" -eq 1 ]; then
    SETTINGS="$CLAUDE_HOME_DIR/settings.json"
    if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
        if jq empty "$SETTINGS" 2>/dev/null; then
            echo "settings.json: ok"
        else
            echo "settings.json: invalid JSON" >&2
            exit 1
        fi
    else
        echo "settings.json: skipped (jq missing or settings absent)"
    fi
fi
