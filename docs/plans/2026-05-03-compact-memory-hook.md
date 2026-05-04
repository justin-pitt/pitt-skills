# Pre-compact session-snapshot hook + skill Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Justin's broken pre-compact hook pair with a working session-snapshot mechanism that survives compaction via auto-memory, then package the validated script as a `compact-memory` skill so coworkers and family can install it from the pitt-skills marketplace.

**Architecture:** Pre-compact hook copies the transcript to a backup, generates an LLM summary via headless `claude -p`, and writes both into `_session-snapshot.md` in the auto-memory dir (always loaded by the harness on every turn — survives compaction). Post-compact cleanup hook is deleted; rotation happens inside pre-compact. Skill packaging is a new `plugins/pitt-skills/skills/compact-memory/` dir with the script as a vendored resource and SKILL.md as the install guide.

**Tech Stack:** Bash, `python3` (for parsing the hook's stdin JSON — already required by the existing hook), `claude` CLI for LLM summary, the auto-memory file system. Plus pitt-skills' standard build/test stack (pwsh 7+, Pester, build.ps1) for the skill package.

**Reference design:** `docs/plans/2026-05-03-compact-memory-hook-design.md` (commit `89a5188`).

**Branch:** `feat/compact-memory-skill` (off main; design doc already committed there).

---

## Lessons that apply

- The hook receives JSON on stdin including `transcript_path`. Parse it with `python3` (already used in the existing `pre-compact.sh` — keep that pattern).
- `$CLAUDE_PROJECT_DIR` is the workspace root inside hooks. Use it for project-dir encoding.
- Project-dir encoding (verified by inspecting `~/.claude/projects/`): drive letter strip + separators-to-`-`, case preserved. `c:\Code\` → `c--Code`. Compute it, or let the script tolerate not finding the dir and bail silently.
- `claude -p` exists for headless single-shot invocation. Pipe transcript text to stdin, get markdown out.
- Justin's commit style: terse lowercase prefix.
- NEVER include "Claude" / "Co-Authored-By: Claude..." / "Generated with [Claude Code]" / robot emoji in commits, PR titles, or PR bodies.
- Adding a SKILL.md will trigger the version-bump CI rule. Bump `plugin.json` in 3 pinned places (`scripts/build.ps1`, `tests/build/fixtures/write-fixtures.ps1`, the JSON fixture).
- Pre-commit hook regenerates Copilot artifacts when SKILL.md or `scripts/build.*` is staged. Stage the regenerated outputs alongside.
- pwsh 7+ is at `$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe`. Bare `pwsh` is 5.1.

---

# Part A — Local repair (validate the design before packaging)

These tasks edit Justin's per-machine config. No git involvement. The skill packaging in Part B uses the validated script as input.

---

### Task 1: Add the `_session-snapshot.md` index entry to MEMORY.md

**Files:**
- Modify: `C:\Users\pittj\.claude\projects\c--Code\memory\MEMORY.md`

**Why:** Auto-memory loads `MEMORY.md` always; per-topic files are loaded on demand when the index points at them. The hook overwrites `_session-snapshot.md` each compaction, but the MEMORY.md pointer is a one-time set-and-forget addition.

**Step 1: Read current MEMORY.md to confirm shape**

```bash
cat "$USERPROFILE/.claude/projects/c--Code/memory/MEMORY.md"
```

Expected: `# Memory Index` heading, followed by `- [filename.md](filename.md) — one-line hook` entries.

**Step 2: Insert the new line at the top of the index**

Add this line as the first bullet under `# Memory Index`:

```markdown
- [_session-snapshot.md](_session-snapshot.md) — Pre-compaction snapshot, check mtime for recency
```

**Step 3: Verify**

```bash
head -5 "$USERPROFILE/.claude/projects/c--Code/memory/MEMORY.md"
```

Expected: the new line appears immediately under `# Memory Index`.

(No commit. This is an edit to user-private memory, outside any repo.)

---

### Task 2: Write the new `~/.claude/hooks/pre-compact.sh`

**Files:**
- Modify (overwrite): `C:\Users\pittj\.claude\hooks\pre-compact.sh`

**Step 1: Replace the entire file with this content**

```bash
#!/bin/bash
# Pre-compact session-snapshot hook.
# Saves an LLM summary + raw transcript backup into the auto-memory dir
# so detail survives compaction. Never breaks compaction itself —
# any failure is silent (exit 0) so the harness keeps going.

set -uo pipefail

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('transcript_path', ''))" 2>/dev/null)
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    exit 0
fi

# Encode the workspace path the same way Claude Code's auto-memory does:
# drop the drive letter, replace separators with `-`, preserve case.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_ENC=$(echo "$PROJECT_DIR" | sed 's|^[A-Za-z]:||; s|[\\/]|-|g; s|^-||')
MEMORY_DIR="$HOME/.claude/projects/${PROJECT_ENC}/memory"
SNAPSHOT_FILE="$MEMORY_DIR/_session-snapshot.md"
ARCHIVE="$MEMORY_DIR/snapshots"

mkdir -p "$MEMORY_DIR" "$ARCHIVE" 2>/dev/null || exit 0

TS=$(date -u +"%Y%m%d-%H%M%S")
TS_HUMAN=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
BACKUP="$ARCHIVE/transcript-${TS}.jsonl"
cp "$TRANSCRIPT" "$BACKUP" 2>/dev/null || true

# 1. LLM summary — best effort, falls back gracefully
SUMMARY=""
if command -v claude >/dev/null 2>&1; then
    PROMPT='You are summarizing a Claude Code transcript that was just compacted. Future-you needs to recover what was in flight. Write a concise markdown brief covering: (1) decisions made with rationale, (2) files touched and branches in flight, (3) open questions or pending choices, (4) current task and what is blocked or next, (5) anything an unfamiliar reader would need to NOT redo work. Aim for 200-500 words. Skip pleasantries.'
    SUMMARY=$(cat "$TRANSCRIPT" | claude -p "$PROMPT" 2>/dev/null || true)
fi
[ -z "$SUMMARY" ] && SUMMARY="*Summary unavailable (claude -p failed or not on PATH). See raw turns below.*"

# 2. Branch and raw transcript tail — both best-effort
BRANCH=$(cd "$PROJECT_DIR" 2>/dev/null && git branch --show-current 2>/dev/null || echo "(unknown)")
RAW_TAIL=$(tail -n 50 "$TRANSCRIPT" 2>/dev/null || echo "(transcript tail unavailable)")

# 3. Write the snapshot file
cat > "$SNAPSHOT_FILE" <<EOF
# Pre-compaction session snapshot

**Compacted at:** ${TS_HUMAN}
**Workspace:** ${PROJECT_DIR}
**Branch:** ${BRANCH}
**Full transcript backup:** snapshots/transcript-${TS}.jsonl

## Summary (LLM-generated)

${SUMMARY}

## Raw turns (last 50 lines of transcript JSONL)

\`\`\`jsonl
${RAW_TAIL}
\`\`\`
EOF

# 4. Archive a dated copy of the snapshot
cp "$SNAPSHOT_FILE" "$ARCHIVE/snapshot-${TS}.md" 2>/dev/null || true

# 5. Rotate: keep last 10 snapshots, last 3 transcript backups
ls -1t "$ARCHIVE"/snapshot-*.md 2>/dev/null | tail -n +11 | xargs -r -I {} rm -f {} 2>/dev/null
ls -1t "$ARCHIVE"/transcript-*.jsonl 2>/dev/null | tail -n +4 | xargs -r -I {} rm -f {} 2>/dev/null

exit 0
```

**Step 2: Verify executable bit**

```bash
chmod +x "$USERPROFILE/.claude/hooks/pre-compact.sh"
ls -l "$USERPROFILE/.claude/hooks/pre-compact.sh"
```

Expected: `-rwxr-xr-x ...` permissions.

**Step 3: Lint-check**

```bash
bash -n "$USERPROFILE/.claude/hooks/pre-compact.sh" && echo OK
```

Expected: `OK` (no syntax errors).

(No commit — this is per-machine config.)

---

### Task 3: Remove the broken `Stop`-event cleanup hook

**Files:**
- Modify: `C:\Users\pittj\.claude\settings.json`
- Delete: `C:\Users\pittj\.claude\hooks\post-compact-cleanup.sh`

**Step 1: Inspect the current `Stop` hook entry**

```bash
cat "$USERPROFILE/.claude/settings.json"
```

Find the `"Stop"` block inside `"hooks"`. It will reference `post-compact-cleanup.sh`.

**Step 2: Edit settings.json — remove the `Stop` array entry pointing to `post-compact-cleanup.sh`**

If the only `Stop` matcher is the post-compact one, remove the entire `"Stop": [...]` array. If there are other `Stop` matchers (unlikely but possible), remove just the one for `post-compact-cleanup.sh`.

The PreCompact entry stays as-is — it still points at `~/.claude/hooks/pre-compact.sh`, which now does the right thing.

**Step 3: Verify JSON parses**

```bash
python3 -c "import json; json.load(open('$USERPROFILE/.claude/settings.json'.replace(chr(92), '/')))"  && echo OK
```

(or use `jq . "$USERPROFILE/.claude/settings.json" >/dev/null && echo OK`)

Expected: `OK`.

**Step 4: Delete the obsolete script**

```bash
rm "$USERPROFILE/.claude/hooks/post-compact-cleanup.sh"
ls "$USERPROFILE/.claude/hooks/"
```

Expected: only `pre-compact.sh` remains (or any other unrelated hooks Justin had).

(No commit.)

---

### Task 4: Validate locally with a real compaction

**Why:** confirm the design works end-to-end before packaging. If it doesn't, fix in place; do not proceed to Part B.

**Step 1: Force a compaction in a working session**

In any active Claude Code session (preferably this one — it's already long), run:

```
/compact
```

Wait for the harness to confirm compaction completed.

**Step 2: Verify the snapshot files exist**

```bash
ls -la "$USERPROFILE/.claude/projects/c--Code/memory/_session-snapshot.md"
ls -la "$USERPROFILE/.claude/projects/c--Code/memory/snapshots/"
```

Expected:
- `_session-snapshot.md` exists with mtime within the last few minutes
- `snapshots/` contains one new `snapshot-<timestamp>.md` and one `transcript-<timestamp>.jsonl`

**Step 3: Inspect the snapshot content**

```bash
cat "$USERPROFILE/.claude/projects/c--Code/memory/_session-snapshot.md"
```

Expected sections present:
- Header with timestamp, workspace, branch, transcript backup pointer
- "Summary (LLM-generated)" with either real summary text OR the "Summary unavailable" fallback
- "Raw turns (last 50 lines...)" with a fenced jsonl block

**Step 4: Verify Claude can find the snapshot**

In a fresh turn (post-compaction), ask: "Read _session-snapshot.md and tell me what we were just doing." Verify Claude locates the file via the MEMORY.md pointer, reads it, and produces a sensible recovery summary.

**Step 5: If anything fails — STOP and iterate**

Common failures:
- Snapshot file missing → check `bash -x` output of the hook by manually invoking with a sample transcript: `echo '{"transcript_path":"<a-known-path>"}' | bash "$USERPROFILE/.claude/hooks/pre-compact.sh"` and inspect.
- "Summary unavailable" when expected to work → check `claude -p` works at all: `echo "test" | claude -p "echo this back"`.
- Wrong project-dir encoding → list `~/.claude/projects/` and adjust the `PROJECT_ENC` sed pattern.

Do NOT proceed to Part B until Step 4 succeeds.

---

# Part B — Package as a pitt-skills skill

These tasks live in the pitt-skills repo. Branch `feat/compact-memory-skill` is already created with the design doc committed.

---

### Task 5: Create the skill files

**Files:**
- Create: `plugins/pitt-skills/skills/compact-memory/SKILL.md`
- Create: `plugins/pitt-skills/skills/compact-memory/scripts/pre-compact.sh`

**Step 1: Create `scripts/pre-compact.sh` — copy of the validated script from Task 2**

```bash
mkdir -p plugins/pitt-skills/skills/compact-memory/scripts
cp "$USERPROFILE/.claude/hooks/pre-compact.sh" plugins/pitt-skills/skills/compact-memory/scripts/pre-compact.sh
```

(The skill ships the exact script Justin validated. No transformation.)

**Step 2: Create `SKILL.md`**

Content:

```markdown
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
2. Pipes the transcript into headless `claude -p` to generate a curated 200–500 word summary (decisions, files, branches, open questions, what's in flight).
3. Writes `_session-snapshot.md` in the auto-memory dir with the LLM summary and a tail of the transcript.
4. Archives a dated copy and rotates older artifacts (last 10 snapshots, last 3 transcript backups).

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

You should see the snapshot file with timestamp, summary, and raw transcript tail. On the next turn, ask Claude "Read _session-snapshot.md and tell me what we were just doing" — it should locate and read the snapshot via the MEMORY.md pointer.

## If you previously had a broken setup

Older versions of this pattern paired a `PreCompact` hook with a `Stop` hook that deleted the backup on the next response (defeating the point). If you had that, remove the `post-compact-cleanup.sh` script and the corresponding `Stop` matcher from `settings.json` before installing this one.

## Failure modes (all silent — never breaks compaction)

- `claude -p` not on PATH or fails → snapshot has raw transcript only, summary section says "unavailable"
- Memory dir missing → script creates it
- Transcript path missing → script exits 0 silently
```

**Step 3: Verify both files**

```bash
ls -la plugins/pitt-skills/skills/compact-memory/
ls -la plugins/pitt-skills/skills/compact-memory/scripts/
```

Expected: SKILL.md + scripts/pre-compact.sh both present.

**Step 4: Lint the script copy**

```bash
bash -n plugins/pitt-skills/skills/compact-memory/scripts/pre-compact.sh && echo OK
```

Expected: `OK`.

**Step 5: Commit**

```bash
git add plugins/pitt-skills/skills/compact-memory
git commit -m "feat(compact-memory): new skill packaging the pre-compact session-snapshot hook"
```

---

### Task 6: Bump plugin.json version

**Files:**
- Modify: `scripts/build.ps1`
- Modify: `tests/build/fixtures/write-fixtures.ps1`
- Modify: `tests/build/fixtures/expected/plugins/pitt-skills/.claude-plugin/plugin.json`

**Step 1: Check current version on main**

```bash
grep '"version"' plugins/pitt-skills/.claude-plugin/plugin.json
```

Note the current value (e.g., `1.6.0`). Increment minor (e.g., to `1.7.0`).

**Step 2: Edit all three pinned places**

Replace the current version with the next minor in each of:

- `scripts/build.ps1`: line `version = '<current>'` (one occurrence near the `$pluginManifest = [ordered]@{` block)
- `tests/build/fixtures/write-fixtures.ps1`: same literal
- `tests/build/fixtures/expected/plugins/pitt-skills/.claude-plugin/plugin.json`: line 4 `"version": "<current>"`

**Step 3: Verify**

```bash
grep -rn "version.*=.*'\|\"version\":" scripts/build.ps1 tests/build/fixtures/write-fixtures.ps1 tests/build/fixtures/expected/plugins/pitt-skills/.claude-plugin/plugin.json | grep -v '\.bak'
```

All three should show the new version. None should still show the old.

**Step 4: Commit**

```bash
git add scripts/build.ps1 tests/build/fixtures/write-fixtures.ps1 tests/build/fixtures/expected/plugins/pitt-skills/.claude-plugin/plugin.json
git commit -m "chore: bump plugin.json to <new-version>"
```

---

### Task 7: Regenerate Copilot artifacts

**Step 1: Run build.ps1**

```bash
& "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe" -NoProfile -Command "./scripts/build.ps1"
```

Expected output: `Build complete: <N> skills processed.` (N = previous count + 1, since we added compact-memory).

**Step 2: Inspect what changed**

```bash
git status --short
```

Expected:
- New: `.github/instructions/compact-memory.instructions.md`
- Modified: `plugins/pitt-skills/.claude-plugin/plugin.json` (version bump)
- Possibly modified: `.claude-plugin/marketplace.json`
- Possibly autocrlf-noise on other instruction files (skip these — `git diff` should show zero content delta)

**Step 3: Stage only the legitimate changes**

```bash
git add .github/instructions/compact-memory.instructions.md plugins/pitt-skills/.claude-plugin/plugin.json
# Add marketplace.json only if its diff is real content, not autocrlf:
git diff .claude-plugin/marketplace.json
# If that shows real changes, add it:
git add .claude-plugin/marketplace.json
```

**Step 4: Verify Pester suite still passes**

```bash
& "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe" -NoProfile -Command "Invoke-Pester tests/ -Output Detailed -CI"
```

Expected: all tests still pass (no new tests added in this PR).

**Step 5: Commit**

```bash
git commit -m "feat: regenerate Copilot artifacts for compact-memory skill"
```

---

### Task 8: Push and open PR

**Step 1: Push the branch**

```bash
git push -u origin feat/compact-memory-skill
```

**Step 2: Open the PR**

```bash
gh pr create --base main --head feat/compact-memory-skill --title "feat(compact-memory): pre-compact session-snapshot hook + skill" --body "$(cat <<'EOF'
## Summary

Adds a \`compact-memory\` skill that ships a working PreCompact hook for Claude Code. The hook writes an LLM-summarized + raw-transcript snapshot into the auto-memory dir on each compaction, so detail survives compaction instead of being lossily summarized away.

**Trigger:** Justin had configured this feature months ago, but the original hook pair was broken — a \`Stop\`-event cleanup hook deleted the pre-compact backup on the very next response, before anything could read it. This PR fixes the design and packages it for distribution.

## What's in the skill

- \`scripts/pre-compact.sh\` — the hook script. Copies the full transcript to a backup, generates an LLM summary via \`claude -p\`, writes \`_session-snapshot.md\` in the auto-memory dir, archives + rotates older artifacts.
- \`SKILL.md\` — install guide with three steps (copy script, edit settings.json, add MEMORY.md index entry) plus failure-mode notes.

## How it works

The auto-memory system (\`~/.claude/projects/<encoded>/memory/MEMORY.md\` and the per-topic files it references) is loaded into every conversation context, including the first turn after a compaction. The hook routes the snapshot through this system, so the next turn naturally has access to it without any post-compact glue logic.

The Stop-event cleanup hook is no longer needed — rotation happens inside pre-compact itself (delete-old-before-write-new).

## Validated locally

Justin ran the new hook against a real compaction in his current session and confirmed the snapshot landed correctly. The skill packages the same script.

## Verify

- [ ] CI green (build / pester / bats / version-bump — version-bump satisfied by the version bump in this PR)
- [ ] After merge, anyone installing pitt-skills can opt in via the SKILL.md SETUP steps
- [ ] After merge, tag the new version on the merge commit

## Plan + design

- Design: \`docs/plans/2026-05-03-compact-memory-hook-design.md\`
- Plan: \`docs/plans/2026-05-03-compact-memory-hook.md\`
EOF
)"
```

**Step 3: Watch CI**

```bash
gh pr checks <PR-number> --watch
```

Wait for all four jobs to be green: build / pester / bats / version-bump.

**Step 4: Stop**

Don't merge. Don't tag. Per Justin's pattern (per-memory `feedback_defer_release_tag_post_merge.md`), version tagging is post-merge.

---

## Notes for the executor

- Tasks 1–4 are local-only, no git. Tasks 5–8 are git-based on `feat/compact-memory-skill`.
- Do not skip Task 4 (local validation). If the hook doesn't actually produce a usable snapshot in real conditions, the skill packaging is shipping a broken script.
- The auto-memory dir for a workspace is `~/.claude/projects/<encoded-workspace-path>/memory/`. The encoding is "drop drive letter, separators-to-`-`, preserve case." For Justin's `c:\Code` workspace this is `c--Code`. If your workspace is different, adjust accordingly.
- `claude -p` invoked from inside a hook DURING compaction is the design's biggest unknown. The parent session is at context limits, but the child invocation is fresh and just summarizes the transcript file — should work but flag if it doesn't and consider falling back to a Python-based summarizer or skipping the LLM step entirely.
- The pre-commit hook (`.githooks/pre-commit`) fires on Tasks 5+ because we're staging a new SKILL.md. It runs `build.ps1` and checks for drift. Tasks 6–7 cover this — bump version + commit regenerated artifacts.
