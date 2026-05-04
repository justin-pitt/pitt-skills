#!/bin/bash
# Pre-compact session-snapshot hook.
# Saves an LLM summary + raw transcript backup into the auto-memory dir
# so detail survives compaction. Never breaks compaction itself —
# any failure is silent (exit 0) so the harness keeps going.
#
# Recursion guards (the previous version recursed because `claude -p`
# spawns a fresh Claude Code session in the same project dir, which
# inherits the same hooks):
#   1. Skip if transcript is < 1 MB — subprocess sessions start tiny.
#   2. Lockfile in memory dir — skip if already running (stale after 5 min).
#   3. timeout 60s on `claude -p` — bound runtime so a hang can't poison things.
#   4. Write raw-tail snapshot BEFORE `claude -p` so the file is always useful.

set -uo pipefail

INPUT=$(cat)

# Pick a working Python: prefer `python` then `python3`. On Windows,
# `python3` is often a Microsoft Store stub that prints an install prompt
# to stderr and exits non-zero, so probing real interpreters first matters.
PY=""
for candidate in python python3; do
    if command -v "$candidate" >/dev/null 2>&1 && \
       echo '' | "$candidate" -c "import sys" >/dev/null 2>&1; then
        PY="$candidate"
        break
    fi
done

if [ -z "$PY" ]; then
    exit 0
fi

TRANSCRIPT=$(echo "$INPUT" | "$PY" -c "import sys, json; print(json.load(sys.stdin).get('transcript_path', ''))" 2>/dev/null)
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    exit 0
fi

# Recursion guard 1: skip tiny transcripts. A real long-running session
# is many MB by the time it compacts. A `claude -p` subprocess session
# is < 1 MB until it loads heavy attachments — well below this threshold
# at the moment its own PreCompact would fire.
TRANSCRIPT_SIZE=$(stat -c%s "$TRANSCRIPT" 2>/dev/null || stat -f%z "$TRANSCRIPT" 2>/dev/null || echo 0)
if [ "$TRANSCRIPT_SIZE" -lt 1048576 ]; then
    exit 0
fi

# Encode the workspace path the same way Claude Code's auto-memory does:
# replace `:` and path separators with `-`, preserve case. On Windows
# `C:\Code` -> `C--Code` (the colon and the leading backslash both become
# dashes, producing the doubled `--`). On POSIX `/home/x` -> `-home-x`.
# Also accept a Git-Bash style `/c/Code` and normalize it to `C--Code`.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_ENC=$(echo "$PROJECT_DIR" | sed -E 's|^/([a-zA-Z])/|\1:/|; s|:|-|g; s|[\/]|-|g')
MEMORY_DIR="$HOME/.claude/projects/${PROJECT_ENC}/memory"
SNAPSHOT_FILE="$MEMORY_DIR/_session-snapshot.md"
ARCHIVE="$MEMORY_DIR/snapshots"
LOCK_FILE="$MEMORY_DIR/_session-snapshot.lock"

mkdir -p "$MEMORY_DIR" "$ARCHIVE" 2>/dev/null || exit 0

# Recursion guard 2: lockfile. If another instance is running, bail.
# Treat locks older than 5 minutes as stale (process likely died).
if [ -f "$LOCK_FILE" ]; then
    LOCK_MTIME=$(stat -c%Y "$LOCK_FILE" 2>/dev/null || stat -f%m "$LOCK_FILE" 2>/dev/null || echo 0)
    LOCK_AGE=$(( $(date +%s) - LOCK_MTIME ))
    if [ "$LOCK_AGE" -lt 300 ]; then
        exit 0
    fi
fi
echo "$$" > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

TS=$(date -u +"%Y%m%d-%H%M%S")
TS_HUMAN=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
BACKUP="$ARCHIVE/transcript-${TS}.jsonl"
cp "$TRANSCRIPT" "$BACKUP" 2>/dev/null || true

# Bounds: keep snapshot well under the auto-memory read limit (256KB) even
# in pathological cases. Claude Code transcripts can have multi-MB JSONL
# lines (full message bodies, tool listings), so byte-based caps are
# essential — line-based tail blows up.
LLM_INPUT_BYTES=200000   # ~200KB of recent transcript fed to claude -p
RAW_TAIL_BYTES=30000     # ~30KB of recent transcript embedded in snapshot
SUMMARY_MAX_BYTES=20000  # cap LLM output in case it goes long

# Capture branch + raw tail BEFORE the LLM call so write_snapshot() can use
# them either way. Byte-based tail so a single multi-MB JSONL line can't
# blow up the snapshot.
BRANCH=$(cd "$PROJECT_DIR" 2>/dev/null && git branch --show-current 2>/dev/null || echo "(unknown)")
RAW_TAIL=$(tail -c "$RAW_TAIL_BYTES" "$TRANSCRIPT" 2>/dev/null || echo "(transcript tail unavailable)")

write_snapshot() {
    local summary="$1"
    cat > "$SNAPSHOT_FILE" <<EOF
# Pre-compaction session snapshot

**Compacted at:** ${TS_HUMAN}
**Workspace:** ${PROJECT_DIR}
**Branch:** ${BRANCH}
**Full transcript backup:** snapshots/transcript-${TS}.jsonl

## Summary (LLM-generated)

${summary}

## Raw turns (last ~${RAW_TAIL_BYTES} bytes of transcript JSONL)

\`\`\`jsonl
${RAW_TAIL}
\`\`\`
EOF
}

# Recursion guard 4: write the snapshot with raw tail BEFORE invoking
# claude -p. If the LLM call hangs/dies/recurses, the file on disk is
# still useful (raw tail + workspace metadata + transcript backup pointer).
write_snapshot "*Summary pending — claude -p call in progress.*"

# LLM summary — best effort, bounded input + bounded runtime.
# Recursion guard 3: timeout 60s on the claude -p call.
SUMMARY=""
if command -v claude >/dev/null 2>&1; then
    PROMPT='You are summarizing the recent tail of a Claude Code transcript that just hit context limits. The text below may start mid-JSON-line — that is expected. Future-you needs to recover what was in flight. Write a concise markdown brief covering: (1) decisions made with rationale, (2) files touched and branches in flight, (3) open questions or pending choices, (4) current task and what is blocked or next, (5) anything an unfamiliar reader would need to NOT redo work. Aim for 200-500 words. Skip pleasantries.'
    if command -v timeout >/dev/null 2>&1; then
        SUMMARY=$(tail -c "$LLM_INPUT_BYTES" "$TRANSCRIPT" 2>/dev/null | timeout 60 claude -p "$PROMPT" 2>/dev/null || true)
    else
        SUMMARY=$(tail -c "$LLM_INPUT_BYTES" "$TRANSCRIPT" 2>/dev/null | claude -p "$PROMPT" 2>/dev/null || true)
    fi
    SUMMARY=$(printf '%s' "$SUMMARY" | head -c "$SUMMARY_MAX_BYTES")
fi
[ -z "$SUMMARY" ] && SUMMARY="*Summary unavailable (claude -p failed, timed out, or not on PATH). See raw turns below.*"

# Rewrite snapshot with the real summary now that we have it.
write_snapshot "$SUMMARY"

# Archive a dated copy of the snapshot
cp "$SNAPSHOT_FILE" "$ARCHIVE/snapshot-${TS}.md" 2>/dev/null || true

# Rotate: keep last 10 snapshots, last 3 transcript backups
ls -1t "$ARCHIVE"/snapshot-*.md 2>/dev/null | tail -n +11 | xargs -r -I {} rm -f {} 2>/dev/null
ls -1t "$ARCHIVE"/transcript-*.jsonl 2>/dev/null | tail -n +4 | xargs -r -I {} rm -f {} 2>/dev/null

exit 0
