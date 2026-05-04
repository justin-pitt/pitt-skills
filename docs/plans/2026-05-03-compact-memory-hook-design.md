# Pre-compact session-snapshot hook — design

**Status:** approved 2026-05-03 (brainstorm phase complete)
**Branch:** `feat/compact-memory-skill` (off main)
**Trigger:** Justin remembered configuring a pre-compact context preservation feature in Claude Code "a while ago." Inspection found the hooks at `~/.claude/hooks/pre-compact.sh` + `post-compact-cleanup.sh` are wired correctly in `~/.claude/settings.json`, but the design is broken: the pre-compact hook copies the transcript to a backup, then the `Stop`-event cleanup hook deletes that backup on the very next assistant response. Net effect today: backup exists for ~one response-window, then is gone before anything reads it. The feature does not actually preserve context across compaction.

## Goal

Replace the broken hook pair with a working pre-compact session-snapshot mechanism that survives compaction by routing through Claude Code's auto-memory system (which is loaded into every conversation context). The snapshot must work for decision-heavy conversations where the user's recent prompts are short answers like "yes", "c", "looks good" — i.e. mechanical user-prompt extraction is not sufficient, an intelligent summary is required.

## Scope

Two deliverables (option (c) from the brainstorm — fix locally first, then package as a skill):

1. **Local repair** — rewrite `~/.claude/hooks/pre-compact.sh`, delete `~/.claude/hooks/post-compact-cleanup.sh`, remove the corresponding `Stop`-event hook entry from `~/.claude/settings.json`. No git involvement; this is per-machine harness configuration. Validates the design with a real session before generalizing.
2. **Skill package** — new `plugins/pitt-skills/skills/compact-memory/` directory containing:
   - `SKILL.md` — describes when to invoke (user asks about pre-compact context preservation), plus inline setup instructions
   - `scripts/pre-compact.sh` — the validated hook script as a vendored resource
   - Setup steps: copy script to `~/.claude/hooks/`, add `PreCompact` hook entry to `~/.claude/settings.json` (snippet in SKILL.md body), remove any broken `Stop`-event cleanup if present.

## Architecture

On each compaction, the pre-compact hook performs five actions in sequence:

1. **Capture last ~10 turn-pairs verbatim** from the transcript JSONL using `jq`. Mechanical extraction; works as long as `jq` is on PATH. Output: a markdown section with interleaved `**User:** ...` / `**Assistant:** ...` entries.
2. **Generate an intelligent summary** by piping the transcript into `claude -p "<summary prompt>"`. Costs pennies per compaction; falls back gracefully to "summary unavailable" on network/API failure.
3. **Write `_session-snapshot.md`** in the auto-memory dir, containing the LLM summary up top and the raw turn-pairs as a forensic appendix below. Overwrite on each compaction (one file always present).
4. **Copy the full transcript** to `<memory-dir>/snapshots/transcript-<timestamp>.jsonl` for deep-dive recovery.
5. **Rotate older artifacts**: keep last 10 snapshot archives, last 3 transcript backups.

The post-compact cleanup hook is **deleted** — its current Stop-event-triggered cleanup is the bug. The new design does not need any post-compact action because:
- `_session-snapshot.md` is overwritten by the next compaction (no rotation needed for the live file)
- Archive rotation happens inside `pre-compact.sh` itself (delete-old-before-write-new)

## File layout

In `C:\Users\pittj\.claude\projects\c--Code\memory\`:

| Path | What | Lifecycle |
|---|---|---|
| `MEMORY.md` (existing) | One new permanent line near the top: `- [_session-snapshot.md](_session-snapshot.md) — Pre-compaction snapshot, check mtime for recency` | Always loaded by harness |
| `_session-snapshot.md` (new) | LLM summary + raw turn-pairs + pointer to transcript backup | Overwritten each compaction |
| `snapshots/snapshot-<timestamp>.md` (new dir, archive) | Past snapshots | Keep last 10 |
| `snapshots/transcript-<timestamp>.jsonl` | Full transcript backups | Keep last 3 (large files) |

The underscore prefix on `_session-snapshot.md` signals it's harness-managed, not a hand-written memory entry.

## Snapshot file format

```markdown
# Pre-compaction session snapshot

**Compacted at:** 2026-05-03 21:34 UTC
**Workspace:** c:\Code\pitt-skills
**Branch:** feat/compact-memory-skill
**Full transcript:** snapshots/transcript-20260503-213412.jsonl

## Summary (LLM-generated)

<200-500 word brief from claude -p, or "Summary unavailable — see raw turns below" if the call failed>

## Raw turn-pairs (last 10)

### Turn -10
**User:** ...
**Assistant:** ...

### Turn -9
...
```

## LLM prompt for the summary

> You are summarizing a Claude Code transcript that was just compacted. Future-you needs to recover what was in flight. Write a concise markdown brief covering: (1) decisions made with rationale, (2) files touched and branches in flight, (3) open questions or pending choices, (4) current task and what's blocked or next, (5) anything an unfamiliar reader would need to NOT redo work. Aim for 200–500 words. Skip pleasantries.

## Failure modes

- `jq` not on PATH → skip turn-pair extraction (raw transcript backup still happens; snapshot file's "Raw turn-pairs" section says "jq unavailable")
- `claude -p` fails (network, API down, no key, rate-limited) → snapshot's "Summary" section says "Summary unavailable", raw turns still present
- Memory dir doesn't exist → `mkdir -p` creates it
- Transcript path missing or unreadable → exit 0 silently. Never break compaction itself
- `claude` not on PATH (someone else uses this skill but doesn't have the CLI in PATH) → same as above; summary unavailable

## Skill packaging

`plugins/pitt-skills/skills/compact-memory/SKILL.md` frontmatter:

```yaml
---
name: compact-memory
description: Use when the user asks about preserving context across Claude Code compaction, pre-compact session snapshots, or recovering from compaction summarization. Documents and ships a PreCompact hook that writes an LLM-summarized + raw-turn-pair snapshot into the auto-memory dir so detail survives compaction.
license: MIT
---
```

Body: explains the auto-memory + PreCompact mechanism, why the default compact-then-summarize is lossy, and how to install. Setup instructions:

1. Copy `scripts/pre-compact.sh` from this skill's dir to `~/.claude/hooks/pre-compact.sh` and `chmod +x` it.
2. Add the `PreCompact` hook to `~/.claude/settings.json` (full snippet provided).
3. If `~/.claude/hooks/post-compact-cleanup.sh` exists from an older broken setup, remove it and the corresponding `Stop` hook entry from `settings.json`.

This skill is unusual in that it's mostly docs + a vendored script (similar to how Justin packages tool-specific guides like `tines` or `cortex-xsiam`), not a "Claude does X" runtime skill. The trigger description tells Claude when to recommend installation; Claude itself doesn't run the hook (the harness does).

## Versioning

Adds a new SKILL.md → triggers the version-bump CI rule. Bump `plugins/pitt-skills/.claude-plugin/plugin.json` from current (1.6.0 or whatever main is now) to next minor. Update the three pinned places (`scripts/build.ps1`, `tests/build/fixtures/write-fixtures.ps1`, the JSON fixture) per the convention from CLAUDE.md.

## Testing

- **Local validation (delivers (1)):** trigger `/compact` in a long session after the new hook is in place. Verify `_session-snapshot.md` appears in memory dir with both LLM summary and raw turns. Verify `MEMORY.md` index line resolves to it. Confirm next turn can locate and reference the snapshot when asked.
- **Skill installation test (delivers (2)):** after the skill is packaged and in main, follow the SKILL.md SETUP instructions on a fresh user account or VM and confirm end-to-end (compaction triggers snapshot creation). Same pattern as Justin's "brother test" for the README onboarding.

## Out of scope

- Per-project vs global snapshots — the auto-memory dir is already keyed per-workspace, so the snapshot is naturally scoped without extra logic
- Encrypting or redacting the snapshot — no PII concerns flagged for Justin's use cases yet
- Auto-injecting the snapshot into the post-compact prompt without Claude's involvement — auto-memory's existing always-loaded behavior already handles this passively
- Multi-machine snapshot sync — out of scope; snapshots live on the local machine only
- A pre-compact preview UI ("here's what would be compacted, want to keep anything?") — possible future work; not needed for the brother's use case

## Open questions

None blocking. Proceed to writing-plans.
