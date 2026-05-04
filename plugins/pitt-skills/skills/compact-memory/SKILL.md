---
name: compact-memory
description: Use when the user asks about preserving context across Claude Code compaction, pre-compact session snapshots, surviving compaction summarization, or recovering work from a compacted session. Documents and ships a PreCompact hook that writes an LLM-summarized + raw-transcript snapshot into the auto-memory dir so detail survives compaction.
license: MIT
---

# Compact-memory hook

Claude Code compacts long conversations to fit in the context window. The default behavior is lossy — only a summary survives — which is fine for casual Q&A but bad when the conversation contains decisions, file paths, branch state, or in-flight work the next turn needs.

This skill ships a `PreCompact` hook that captures a session snapshot before compaction happens. The snapshot lands in Claude Code's auto-memory dir, which the harness loads on every turn, so the snapshot survives compaction and the next turn can recover detail.

## What the hook does

On each compaction, the hook:

1. Copies the full transcript JSONL to a timestamped backup under `<memory-dir>/snapshots/`.
2. Pipes the **last ~200KB** of the transcript into headless `claude -p` to generate a curated 200–500 word summary (decisions, files, branches, open questions, what's in flight).
3. Writes `_session-snapshot.md` in the auto-memory dir with the LLM summary and the **last ~30KB** of transcript.
4. Archives a dated copy and rotates older artifacts (last 10 snapshots, last 3 transcript backups).

All inputs are **byte-bounded** because Claude Code transcripts can have multi-megabyte JSONL lines (full message bodies, tool listings). A line-based tail blows up the snapshot; a byte-based tail keeps it well under the 256KB auto-memory read limit.

The snapshot is referenced from `MEMORY.md` so the harness eagerly indexes it; future turns read it via the existing memory system.

## Setup

Three steps:

### 1. Copy the hook script into your `~/.claude/hooks/`

```bash
mkdir -p ~/.claude/hooks
cp <this-skill-dir>/scripts/pre-compact.sh ~/.claude/hooks/pre-compact.sh
chmod +x ~/.claude/hooks/pre-compact.sh
```

On Windows, the destination is `%USERPROFILE%\.claude\hooks\pre-compact.sh` (Git Bash path: `$USERPROFILE/.claude/hooks/pre-compact.sh`).

### 2. Add the `PreCompact` hook to your `~/.claude/settings.json`

Inside the top-level `"hooks"` object, add:

```json
"PreCompact": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "~/.claude/hooks/pre-compact.sh"
      }
    ]
  }
]
```

If `"hooks"` doesn't exist, add it as a top-level key. Validate with `jq . ~/.claude/settings.json` after editing.

### 3. Add an index entry to your auto-memory `MEMORY.md`

Find your project memory dir at `~/.claude/projects/<encoded-workspace-path>/memory/MEMORY.md` (the encoded path looks like `c--Code` for `c:\Code`). Add this line as the first bullet under `# Memory Index`:

```markdown
- [_session-snapshot.md](_session-snapshot.md) — Pre-compaction snapshot, check mtime for recency
```

### Test it

Run `/compact` in a long session. Then check:

```bash
ls ~/.claude/projects/<encoded>/memory/_session-snapshot.md
cat ~/.claude/projects/<encoded>/memory/_session-snapshot.md
```

You should see the snapshot file (well under 100KB) with timestamp, summary, and raw transcript tail. On the next turn, ask Claude "Read _session-snapshot.md and tell me what we were just doing" — it should locate and read the snapshot via the MEMORY.md pointer.

## If you previously had a broken setup

Older versions of this pattern paired a `PreCompact` hook with a `Stop` hook that deleted the backup on the next response (defeating the point). If you had that, remove the `post-compact-cleanup.sh` script and the corresponding `Stop` matcher from `settings.json` before installing this one.

## Known pitfalls

### Recursion: `claude -p` inherits hooks

`claude -p` invoked from inside this hook spawns a **fresh Claude Code session in the same project directory**, which inherits all your hooks — including this one. If that subprocess hits context limits and triggers its own PreCompact, you get unbounded recursion: each layer overwrites the parent's snapshot and spawns more subprocess sessions. An early version of this script blew up to hundreds of megabytes of orphan transcripts in a single afternoon.

The shipped script defends against this with four layered guards. **Do not remove them, even if they look paranoid:**

1. **Size guard** — skip if the transcript is under 1 MB. A real long-running session is many megabytes by the time it compacts; a subprocess session is well under 1 MB at the moment its own PreCompact would fire.
2. **Lockfile** — `_session-snapshot.lock` in the memory dir prevents concurrent runs. Stale locks (older than 5 minutes) are ignored so a crashed run can't permanently wedge things. Cleanup via `trap EXIT`.
3. **`timeout 60s`** on the `claude -p` call — bounds runtime so a hung subprocess can't poison the parent.
4. **Raw-tail snapshot written BEFORE `claude -p`** — even if the LLM call hangs, dies, or recurses, the on-disk snapshot is still useful (raw transcript tail + workspace metadata + transcript backup pointer). The script rewrites it with the LLM summary on success.

If you fork this and want to swap `claude -p` for another summarizer (e.g., a local Python script with no recursion vector), you can drop guards 1–3 — but keep guard 4 (raw-tail-first) as a robustness measure.

### Byte bounds, not line bounds

Claude Code transcript JSONL lines can be multi-megabyte (full message bodies, tool listings). A line-based `tail -n 50` blows up the snapshot file size and the LLM input. The script uses byte-based caps (`tail -c $LLM_INPUT_BYTES`, `head -c $SUMMARY_MAX_BYTES`). Don't switch back to line-based slicing.

## Failure modes (all silent — never breaks compaction)

- `claude -p` not on PATH or fails → snapshot has raw transcript only, summary section says "unavailable"
- Memory dir missing → script creates it
- Transcript path missing → script exits 0 silently
- No working `python` / `python3` → script exits 0 silently (Python is needed to parse the hook's stdin JSON)
