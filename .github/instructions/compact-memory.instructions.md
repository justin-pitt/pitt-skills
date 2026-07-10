---
applyTo: "**"
description: Use when the user asks about preserving context across Claude Code compaction, pre-compact session snapshots, surviving compaction summarization, or recovering work from a compacted session. Documents and ships a PreCompact hook that writes an LLM-summarized + raw-transcript snapshot into the auto-memory dir so detail survives compaction.
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

You can install this in three ways. They all produce the same result.

### Option 1 — Automated (recommended)

Run the bundled setup script. It copies the hook, merges the `PreCompact` entry into `~/.claude/settings.json`, and adds the `_session-snapshot.md` index entry to every existing `~/.claude/projects/*/memory/MEMORY.md`. Idempotent.

POSIX shells (Linux/macOS/Git Bash):
```bash
bash <skill-dir>/scripts/setup.sh
```

PowerShell 7+:
```powershell
& "<skill-dir>/scripts/setup.ps1"
```

Honors `$CLAUDE_HOME` (or `$env:CLAUDE_HOME` on PS) if set, else uses `~/.claude`. Requires `jq` on the bash path; the PowerShell version uses native JSON cmdlets and has no extra deps. Backs up `settings.json` to `settings.json.bak` before editing.

### Option 2 — AI-assisted

Tell your Claude Code agent (or any LLM agent with file-edit tools): **"Set up the compact-memory skill following the steps in `<skill-dir>/SKILL.md`."** The agent reads this file and applies the three edits below using its file-write tools — no `jq` or shell required. This is the easiest path if you'd rather not run an unfamiliar script and you trust the agent.

### Option 3 — By hand

Three edits. Each is small.

**Edit 1.** Copy the hook script to `~/.claude/hooks/pre-compact.sh` and make it executable.

```bash
mkdir -p ~/.claude/hooks
cp <skill-dir>/scripts/pre-compact.sh ~/.claude/hooks/pre-compact.sh
chmod +x ~/.claude/hooks/pre-compact.sh
```

(On Windows-native paths, the destination is `%USERPROFILE%\.claude\hooks\pre-compact.sh`.)

**Edit 2.** Add a `PreCompact` block under the top-level `"hooks"` key in `~/.claude/settings.json`. If `"hooks"` doesn't exist yet, create it.

```json
{
  "hooks": {
    "PreCompact": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/pre-compact.sh" }
        ]
      }
    ]
  }
}
```

If you already have other entries under `"hooks"`, only add the `PreCompact` array — leave existing entries alone. Validate with `jq . ~/.claude/settings.json` before saving.

**Edit 3.** For each project workspace where you want compaction snapshots, add an index entry to that workspace's auto-memory `MEMORY.md`.

The path is `~/.claude/projects/<encoded-workspace-path>/memory/MEMORY.md`. To compute it deterministically, run one of:

```bash
bash <skill-dir>/scripts/encode-memory-dir.sh "/path/to/workspace"
```

```powershell
& "<skill-dir>/scripts/encode-memory-dir.ps1" "C:\path\to\workspace"
```

Both print the encoded folder name (e.g. `c--Code` or `-home-justin-code`). The hand-rule, for reference: drop the drive-letter colon prefix, replace `:` and `/` and `\` with `-`, preserve case. Examples:

| Workspace | Encoded path |
|---|---|
| `c:\Code` | `c--Code` |
| `/home/justin/code` | `-home-justin-code` |

Add this line at the top of the file (or as the first bullet under a `# Memory Index` heading if your `MEMORY.md` has one — the default Claude Code format is a flat bullet list with no heading):

```markdown
- [_session-snapshot.md](_session-snapshot.md) — Pre-compaction snapshot, check mtime for recency
```

### Test it

After any of the three options, run `/compact` in a long Claude Code session. Then check:

```bash
ls ~/.claude/projects/<encoded>/memory/_session-snapshot.md
cat ~/.claude/projects/<encoded>/memory/_session-snapshot.md
```

You should see the snapshot file (well under 100KB) with timestamp, summary, and raw transcript tail. On the next turn, ask Claude "Read _session-snapshot.md and tell me what we were just doing" — it should locate the file via the MEMORY.md pointer and produce a recovery summary.

## If you previously had a broken setup

Older versions of this pattern paired a `PreCompact` hook with a `Stop` hook that deleted the backup on the next response (defeating the point). If you had that, remove the `post-compact-cleanup.sh` script and the corresponding `Stop` matcher from `settings.json` before installing this one.

## Known pitfalls

### Recursion: `claude -p` inherits hooks

`claude -p` invoked from inside this hook spawns a **fresh Claude Code session in the same project directory**, which inherits all your hooks — including this one. If that subprocess hits context limits and triggers its own PreCompact, you get unbounded recursion: each layer overwrites the parent's snapshot and spawns more subprocess sessions. An early version of this script blew up to hundreds of megabytes of orphan transcripts in a single afternoon.

The shipped script defends against this with four layered guards. **Do not remove them, even if they look paranoid:**

1. **Size guard** — skip if the transcript is under 1 MB. A real long-running session is many megabytes by the time it compacts; a subprocess session is well under 1 MB at the moment its own PreCompact would fire.
2. **Lockfile** — `_session-snapshot.lock` in the memory dir prevents concurrent runs. Stale locks (older than 5 minutes) are ignored so a crashed run can't permanently wedge things. Cleanup via `trap EXIT`.
3. **Timeout-bounded LLM call** — `timeout 60` (or `gtimeout` on macOS with Homebrew coreutils) wraps the `claude -p` call so a hung subprocess can't wedge the parent compaction. **If neither `timeout` nor `gtimeout` is on PATH (stock macOS), the LLM summary is skipped entirely** rather than risking an unbounded hang — the raw-tail snapshot (guard 4) still captures everything important.
4. **Raw-tail snapshot written BEFORE `claude -p`** — even if the LLM call hangs, dies, or recurses, the on-disk snapshot is still useful (raw transcript tail + workspace metadata + transcript backup pointer). The script rewrites it with the LLM summary on success.

If you fork this and want to swap `claude -p` for another summarizer (e.g., a local Python script with no recursion vector), you can drop guards 1–3 — but keep guard 4 (raw-tail-first) as a robustness measure.

### Byte bounds, not line bounds

Claude Code transcript JSONL lines can be multi-megabyte (full message bodies, tool listings). A line-based `tail -n 50` blows up the snapshot file size and the LLM input. The script uses byte-based caps (`tail -c $LLM_INPUT_BYTES`, `head -c $SUMMARY_MAX_BYTES`). Don't switch back to line-based slicing.

## Failure modes (all silent — never breaks compaction)

- `claude -p` not on PATH or fails → snapshot has raw transcript only, summary section says "unavailable"
- Memory dir missing → script creates it
- Transcript path missing → script exits 0 silently
- No working `python` / `python3` → script exits 0 silently (Python is needed to parse the hook's stdin JSON)
