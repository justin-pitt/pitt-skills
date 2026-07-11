#!/usr/bin/env bash
# Automated setup for the compact-memory skill.
#
# 1. Copies the hook to ~/.claude/hooks/pre-compact.sh
# 2. Merges the PreCompact entry into ~/.claude/settings.json (via jq)
# 3. Adds the _session-snapshot.md index entry to existing
#    ~/.claude/projects/*/memory/MEMORY.md files
#
# Honors $CLAUDE_HOME if set, else uses $HOME/.claude.
# Idempotent — safe to re-run.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_SRC="$SKILL_DIR/scripts/pre-compact.sh"
CLAUDE_HOME_DIR="${CLAUDE_HOME:-$HOME/.claude}"
HOOK_DST="$CLAUDE_HOME_DIR/hooks/pre-compact.sh"
SETTINGS="$CLAUDE_HOME_DIR/settings.json"
HOOK_COMMAND='~/.claude/hooks/pre-compact.sh'
INDEX_LINE='- [_session-snapshot.md](_session-snapshot.md) — Pre-compaction snapshot, check mtime for recency'

# --- 1. Install hook ---
if [ ! -f "$HOOK_SRC" ]; then
    echo "ERROR: hook source not found at $HOOK_SRC" >&2
    exit 1
fi
mkdir -p "$(dirname "$HOOK_DST")"
cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"
echo "[1/3] installed hook -> $HOOK_DST"

# --- 2. Merge settings.json ---
if ! command -v jq >/dev/null 2>&1; then
    echo "[2/3] WARN: jq not on PATH, skipping settings.json merge" >&2
    echo "       Either install jq, or add this manually to ~/.claude/settings.json:" >&2
    echo '       {"hooks":{"PreCompact":[{"hooks":[{"type":"command","command":"~/.claude/hooks/pre-compact.sh"}]}]}}' >&2
else
    if [ -f "$SETTINGS" ]; then
        cp "$SETTINGS" "$SETTINGS.bak"
        if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
            echo "[2/3] ERROR: $SETTINGS is not valid JSON. Backup saved at $SETTINGS.bak." >&2
            echo "       Fix the JSON manually and re-run, or restore from the backup." >&2
            exit 1
        fi
        EXISTS=$(jq -r --arg path "$HOOK_COMMAND" '
            [(.hooks.PreCompact // [])[] | (.hooks // [])[] | select(.command == $path)] | length
        ' "$SETTINGS")
        if [ "$EXISTS" -eq 0 ]; then
            jq --arg path "$HOOK_COMMAND" '
                .hooks = (.hooks // {})
                | .hooks.PreCompact = ((.hooks.PreCompact // []) + [{hooks: [{type: "command", command: $path}]}])
            ' "$SETTINGS" > "$SETTINGS.tmp"
            mv "$SETTINGS.tmp" "$SETTINGS"
            echo "[2/3] merged PreCompact into $SETTINGS (backup at $SETTINGS.bak)"
        else
            echo "[2/3] PreCompact already configured in $SETTINGS, no change"
        fi
    else
        mkdir -p "$(dirname "$SETTINGS")"
        jq -n --arg path "$HOOK_COMMAND" '{hooks: {PreCompact: [{hooks: [{type: "command", command: $path}]}]}}' > "$SETTINGS"
        echo "[2/3] created $SETTINGS with PreCompact"
    fi
fi

# --- 3. Add MEMORY.md index entry to existing workspace memory dirs ---
# Default Claude Code MEMORY.md is a flat bullet list with no heading. If a
# `# Memory Index` heading exists, insert under it; otherwise prepend at top.
PROJECTS_DIR="$CLAUDE_HOME_DIR/projects"
ADDED_HEADING=0
ADDED_TOP=0
SKIPPED=0

# Find python (same probe pattern as the hook itself).
PY=""
for candidate in python python3; do
    if command -v "$candidate" >/dev/null 2>&1 && \
       echo '' | "$candidate" -c "import sys" >/dev/null 2>&1; then
        PY="$candidate"
        break
    fi
done

if [ -z "$PY" ]; then
    echo "[3/3] WARN: no working python found, skipping MEMORY.md updates" >&2
else
    if [ -d "$PROJECTS_DIR" ]; then
        for memory_md in "$PROJECTS_DIR"/*/memory/MEMORY.md; do
            [ -f "$memory_md" ] || continue
            if grep -q '_session-snapshot\.md' "$memory_md"; then
                SKIPPED=$((SKIPPED+1))
                continue
            fi
            RESULT=$("$PY" -c '
import sys, re
path, line = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()
nl = "\r\n" if "\r\n" in content else "\n"
if re.search(r"(?m)^# Memory Index", content):
    new = re.sub(r"(?m)^(# Memory Index *\r?\n+)", r"\1" + line + nl, content, count=1)
    print("heading")
else:
    new = line + nl + content
    print("top")
with open(path, "w", encoding="utf-8") as f:
    f.write(new)
' "$memory_md" "$INDEX_LINE")
            case "$RESULT" in
                heading) ADDED_HEADING=$((ADDED_HEADING+1)) ;;
                top)     ADDED_TOP=$((ADDED_TOP+1)) ;;
            esac
        done
    fi
    echo "[3/3] MEMORY.md updates: $ADDED_HEADING under heading, $ADDED_TOP at top, $SKIPPED already-present"
fi

echo "Done. Run /compact in a long session to verify."
