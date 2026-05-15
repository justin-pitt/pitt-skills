# Codebase-audit Skill Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (parallel session) OR superpowers:subagent-driven-development (this session) to implement this plan task-by-task.

**Goal:** Ship a `codebase-audit` skill in pitt-skills that fires on broad whole-project scan/audit phrasing and runs a 4-dimension quality pass (bugs, vulns, UX, perf) with confidence-filtered findings and a per-finding fix / defer / ignore walk-through.

**Architecture:** A single-file orchestrator skill at `plugins/pitt-skills/skills/codebase-audit/SKILL.md`. When triggered, the controller dispatches 4 parallel Sonnet subagents (one per dimension), confidence-scores findings via Haiku, filters at 70 / caps at 15, then walks the user through each finding interactively via `AskUserQuestion`. No additional assets needed. See design doc: [`2026-05-15-codebase-audit-design.md`](2026-05-15-codebase-audit-design.md).

**Tech Stack:** Markdown SKILL.md, PowerShell build pipeline (`scripts/build.ps1`), Pester tests for fixture drift, GitHub Actions CI (verify-build / pester / bats / version-bump). Branch already created: `feat/codebase-audit-skill` with design doc committed at `2c7420c`.

---

## Conventions

- **Branch:** `feat/codebase-audit-skill` (already cut off main at `9b5d01a` v1.10.0 merge commit, design doc committed).
- **PowerShell 7:** all `pwsh` invocations use `$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe`. Bare `pwsh` is 5.1.
- **autocrlf noise:** ~35 `.github/instructions/*.md` files show as `M` in `git status` but have zero content delta. Verify via `git diff --numstat` and stage only real changes. See [`feedback_autocrlf_blob_verification.md`](C:/Users/pittj/.claude/projects/c--Code/memory/feedback_autocrlf_blob_verification.md).
- **No Claude attribution** in commits or PR bodies. See [`feedback_no_claude_in_commits.md`](C:/Users/pittj/.claude/projects/c--Code/memory/feedback_no_claude_in_commits.md).
- **Tag post-merge.** Do not tag `v1.11.0` during this PR. Tag the merge commit after merge. See [`feedback_defer_release_tag_post_merge.md`](C:/Users/pittj/.claude/projects/c--Code/memory/feedback_defer_release_tag_post_merge.md).

---

## Task 1: Scaffold skill directory + minimal SKILL.md

**Files:**
- Create: `plugins/pitt-skills/skills/codebase-audit/SKILL.md`

**Step 1: Create the skill directory and write a minimal SKILL.md (frontmatter only)**

```bash
mkdir -p plugins/pitt-skills/skills/codebase-audit
```

Write `plugins/pitt-skills/skills/codebase-audit/SKILL.md` with this content:

```markdown
---
name: codebase-audit
description: Use when the user asks to scan, audit, sweep, or review the codebase (or "code base") for bugs, vulnerabilities, UX improvements, or performance issues — typically at end-of-task as a proactive whole-project quality pass. Triggers on phrases like "scan the code base", "audit the code", "review the project", "sweep for issues", "look for bugs and vulns", or any request bundling two or more of: bugs / vulns / security / UX / accessibility / performance / quality. Dispatches 4 parallel reviewers (bug, vuln, UX, perf), confidence-scores findings, and walks the user through fix / defer / ignore per finding. Do NOT use for: reviewing a specific PR diff (use code-review or coderabbit), reviewing only recently-changed code on a branch (use requesting-code-review), or single-dimension audits (use owasp-security / ui-ux-guide / vibesec directly).
license: MIT
---

# Codebase audit

(Body to be filled in next task.)
```

**Step 2: Verify build.ps1 picks up the new skill**

Run:
```bash
"$LOCALAPPDATA/Microsoft/WindowsApps/pwsh.exe" -NoProfile -Command "./scripts/build.ps1"
```

Expected output: `Build complete: 35 skills processed.` (was 34; codebase-audit makes 35).

Verify the Copilot mirror was generated:
```bash
ls -la .github/instructions/codebase-audit.instructions.md
```

Expected: file exists with the same frontmatter and stub body.

**Step 3: Verify only real changes in git status**

```bash
git status --short
git diff --numstat | grep -v '^0\s'
```

Expected real-content changes:
- `plugins/pitt-skills/skills/codebase-audit/SKILL.md` (new)
- `.github/instructions/codebase-audit.instructions.md` (new)

Pre-existing autocrlf noise will be present in `git status --short` but should NOT appear in `git diff --numstat`. Do not stage those.

**Step 4: Run Pester to confirm no fixture drift**

Run:
```bash
"$LOCALAPPDATA/Microsoft/WindowsApps/pwsh.exe" -NoProfile -Command "Invoke-Pester tests/ -Output Detailed -CI"
```

Expected: 38 passed, 0 failed.

**Step 5: Commit**

```bash
git add plugins/pitt-skills/skills/codebase-audit/SKILL.md .github/instructions/codebase-audit.instructions.md
git commit -m "feat(codebase-audit): scaffold skill directory + frontmatter"
```

---

## Task 2: Write the full SKILL.md body

**Files:**
- Modify: `plugins/pitt-skills/skills/codebase-audit/SKILL.md`

**Step 1: Replace the stub body with the full orchestration content**

The frontmatter (lines 1-5) stays as-is. Replace everything below `# Codebase audit` with the structure below. Each section in this task is verbatim content for SKILL.md; do not paraphrase or condense.

### 1. When to use

```markdown
## When to use

Fire this skill when the user asks for a broad whole-project quality sweep that bundles two or more of: bugs, vulnerabilities/security, UX, accessibility, performance, or code quality. Typical end-of-task prompts:

- "scan the code base for bugs, vulns, ux improvements, and performance issues"
- "audit the code"
- "review the project"
- "sweep for issues"
- "look for bugs and vulns"

**Do NOT fire** when:
- The user asks to review a specific PR diff → use `code-review` or `coderabbit`.
- The user asks to review only recently-changed code on a branch → use `requesting-code-review`.
- The user asks a single-dimension question (security only, UX only, perf only) → use `owasp-security` / `vibesec` / `ui-ux-guide` directly.
- The user is debugging a specific bug or test failure → use `systematic-debugging`.
```

### 2. Orchestrator flow

```markdown
## Orchestrator flow

Run these 8 steps in order. Each step is mandatory. Use `TodoWrite` to track progress through the steps.

### Step 1 — Detect project context

Capture:
- Project root (current working directory unless the user specified another).
- Languages present, inferred from file extensions via `Glob` (e.g., `**/*.py`, `**/*.ts`, `**/*.tsx`, `**/*.go`).
- Frameworks present, inferred from manifest files: `package.json`, `pyproject.toml`, `requirements.txt`, `go.mod`, `Cargo.toml`, `Gemfile`.
- Git state: current branch and dirty/clean.
- Rough file count: `find . -type f -not -path './.git/*' | wc -l`.

### Step 2 — Huge-repo guard

If file count > 500, ask the user via `AskUserQuestion` whether to:
- Proceed with full audit (slower).
- Limit to recently-changed directories (last 7 days, via `git log --since='7 days ago' --name-only`).
- Accept a user-supplied subdirectory list.

### Step 3 — Dispatch 4 parallel Sonnet subagents

Call the `Task` tool four times in parallel (same message, multiple tool_use blocks). Each subagent gets the project context summary + its dimension-specific brief (see "Subagent briefs" below). Use `subagent_type: general-purpose`, `model: sonnet`.

Subagents in parallel:
- `bug-hunter`
- `vuln-hunter`
- `ux-reviewer`
- `perf-reviewer`

### Step 4 — Collect findings

Each subagent returns a JSON-ish flat list:

```json
[
  {
    "severity": "critical|high|medium|low",
    "file": "absolute/or/relative/path",
    "line": 123,
    "dimension": "bug|vuln|ux|perf",
    "title": "one-line summary",
    "why": "1-2 sentence explanation",
    "suggested_fix": "what to change"
  }
]
```

### Step 5 — Confidence-score findings via parallel Haiku scorers

For each finding, dispatch a Haiku agent (`model: haiku`) to score 0-100 confidence using the rubric below. Run all scorers in one parallel batch (multiple `Task` tool_use blocks in one message).

### Step 6 — Filter + rank

- Filter out any finding with confidence score < 70.
- Cap the result list at 15 findings total. If more than 15 survive filtering, drop the lowest-confidence ones.
- Rank by: severity (critical > high > medium > low), then dimension priority (vuln > bug > perf > ux), then confidence descending.

### Step 7 — Interactive walk-through

For each ranked finding, present an `AskUserQuestion` with:
- Header: `<dimension> N/M` (e.g., "Vuln 3/12")
- Question body: severity, file:line, title, why, suggested_fix
- Options: **Fix it** / **Defer** / **Ignore**

Per choice:
- **Fix it** → dispatch an implementer subagent (`Task` tool, `model: sonnet`) with the finding + project context. Subagent reports back; controller continues to next finding.
- **Defer** → append a markdown bullet to `docs/audit/YYYY-MM-DD-deferred.md` (create the directory if it doesn't exist; append rather than overwrite if the file already exists today).
- **Ignore** → skip; do not record anywhere.

### Step 8 — Final summary

After processing the last finding, print one paragraph: counts of fixed / deferred / ignored, plus path to the deferred file if any.
```

### 3. Subagent briefs

```markdown
## Subagent briefs

Each subagent receives this template:

**Input**
- Project root: `<absolute path>`
- Context summary: languages, frameworks, file count, branch, dirty/clean
- Specialist skill reference (if available): `Read <path>/SKILL.md` for relevant guidance

**Output**
- Flat JSON list of findings matching the schema in Step 4 above.

### bug-hunter

You are scanning the entire project for **bug-class issues**: logic errors, dead/unreachable code, swallowed exceptions, off-by-one errors, race conditions, missing null/empty checks at boundaries (user input, external API responses, file I/O).

**Skip:** style, formatting, naming, code smells without clear behavior impact.

Use `Glob` and `Grep` to scan systematically. Read suspicious files in full. Report findings using the schema above. If you find nothing, return an empty array `[]`.

### vuln-hunter

You are scanning the entire project for **security vulnerabilities**: OWASP Top 10 (injection, broken auth, IDOR, SSRF, XSS, insecure deserialization, sensitive data exposure, broken access control, security misconfiguration, vulnerable dependencies), hardcoded secrets / API keys, dependency confusion risks, missing CSRF / auth checks, unsafe `eval` / `exec` / template rendering.

**Reference these skills if installed:** `owasp-security`, `vibesec`. Read their `SKILL.md` files for current guidance before scanning.

**Skip:** infosec hygiene that doesn't ship in code (2FA policy, password rotation cadence, etc.).

Report findings using the schema above. If you find nothing, return `[]`.

### ux-reviewer

You are scanning the entire project for **UX issues**: affordance gaps, missing error / empty / loading states, copy density and clarity, focus management, accessibility basics (alt text, label association, keyboard nav, ARIA where load-bearing).

**Reference this skill if installed:** `ui-ux-guide`. Read its `SKILL.md` before scanning.

**Skip:** visual styling preferences, exact color / spacing values, brand opinions.

For projects without a UI (pure backend / CLI / library), return `[]` quickly.

Report findings using the schema above.

### perf-reviewer

You are scanning the entire project for **performance issues**: N+1 queries, missing indexes on hot queries, synchronous I/O in async paths, large bundles / heavy unconditional imports, render churn (React component re-renders without memoization), memory leaks (unbounded caches, event listeners without cleanup), expensive operations in hot paths.

**Skip:** micro-optimizations, theoretical perf concerns without a real hot path.

Report findings using the schema above. If you find nothing, return `[]`.
```

### 4. Confidence scoring

```markdown
## Confidence scoring

For each finding, dispatch a Haiku scorer. The scorer reads the finding, optionally checks the cited file/line, and returns a score 0-100 using this rubric (give it to the scorer verbatim):

- **0** — Not confident at all. False positive that doesn't stand up to light scrutiny, or pre-existing issue.
- **25** — Somewhat confident. Might be a real issue, may also be a false positive. Couldn't verify it's real. Stylistic and not explicitly called out by any project rule.
- **50** — Moderately confident. Verified real but might be a nitpick or rare. Not very important relative to the rest of the audit.
- **75** — Highly confident. Double-checked, very likely a real issue hit in practice. Existing code is insufficient. Important and directly impacts functionality.
- **100** — Absolutely certain. Double-checked, definitely real, will happen frequently. Evidence directly confirms.

Filter cutoff: **70**. Cap total findings at **15** (drop lowest-confidence first if more than 15 survive).
```

### 5. Interactive walk-through

```markdown
## Interactive walk-through

Use `AskUserQuestion` per finding. Question template:

- `question`: `<dimension> finding N/M — <severity>` (e.g., "Vuln finding 3/12 — high")
- `header`: short label, max 12 chars (e.g., "Vuln 3/12")
- `options`:
  - **Fix it** — Apply the suggested fix now. I'll dispatch an implementer subagent with the finding context.
  - **Defer** — Save to `docs/audit/<today>-deferred.md` to address later.
  - **Ignore** — Skip; this is a false positive or not worth fixing.

Show the user: file:line, title, 1-2 sentence "why", suggested fix.

**On Fix:** dispatch an implementer subagent (`Task` tool, `general-purpose`, `model: sonnet`) with:
- The finding (severity, file:line, title, why, suggested_fix)
- The project context summary from Step 1
- Instruction: implement the fix, verify it doesn't break adjacent code, return when done

After the implementer returns, continue to the next finding.

**On Defer:** ensure `docs/audit/` exists. Append (do not overwrite) to `docs/audit/<YYYY-MM-DD>-deferred.md` with this format:

```markdown
- [<severity>] <dimension>: <title> — `<file>:<line>` — <why>. Fix: <suggested_fix>.
```

**On Ignore:** skip silently.

Loop until all findings processed. Then print final summary.
```

### 6. Edge cases

```markdown
## Edge cases

- **No findings in any dimension:** print "Audit clean." and exit. Do not run the interactive walk-through.
- **Subagent fails or times out:** note which dimension dropped in the final summary, continue with the remaining dimensions' findings.
- **Re-run same day:** the deferred file appends rather than overwrites; the new entries land below the existing ones with a `## <time>` divider.
- **Project root ambiguous:** ask the user explicitly which directory to audit before dispatching subagents.
- **No specialist skill installed for a dimension:** the corresponding subagent still runs with general best-practice guidance; just skip the `Read <skill>/SKILL.md` step.
```

**Step 2: Verify build.ps1 picks up the new content**

Run:
```bash
"$LOCALAPPDATA/Microsoft/WindowsApps/pwsh.exe" -NoProfile -Command "./scripts/build.ps1"
```

Expected: `Build complete: 35 skills processed.`

Verify `.github/instructions/codebase-audit.instructions.md` content mirrors the new SKILL.md (frontmatter stripped, body preserved).

**Step 3: Run Pester to confirm no fixture drift**

```bash
"$LOCALAPPDATA/Microsoft/WindowsApps/pwsh.exe" -NoProfile -Command "Invoke-Pester tests/ -Output Detailed -CI"
```

Expected: 38 passed.

**Step 4: Commit**

```bash
git add plugins/pitt-skills/skills/codebase-audit/SKILL.md .github/instructions/codebase-audit.instructions.md
git commit -m "feat(codebase-audit): orchestrator flow + 4 subagent briefs + scoring + walk-through + edge cases"
```

---

## Task 3: Bump plugin.json 1.10.0 → 1.11.0

**Files:**
- Modify: `plugins/pitt-skills/.claude-plugin/plugin.json:4`
- Modify: `scripts/build.ps1:99`
- Modify: `tests/build/fixtures/write-fixtures.ps1:157`
- Modify: `tests/build/fixtures/expected/plugins/pitt-skills/.claude-plugin/plugin.json:4`

**Step 1: Read each file first (Edit tool requires Read before Write)**

```bash
# (use the Read tool on each of the 4 files above before editing)
```

**Step 2: Replace `1.10.0` with `1.11.0` in each file (one occurrence per file)**

After all four edits, verify:
```bash
grep -rn '1\.10\.0\|1\.11\.0' plugins/pitt-skills/.claude-plugin/plugin.json scripts/build.ps1 tests/build/fixtures/write-fixtures.ps1 tests/build/fixtures/expected/plugins/pitt-skills/.claude-plugin/plugin.json
```

Expected: zero `1.10.0` matches, four `1.11.0` matches.

**Step 3: Re-run build.ps1**

```bash
"$LOCALAPPDATA/Microsoft/WindowsApps/pwsh.exe" -NoProfile -Command "./scripts/build.ps1"
```

Expected: regenerates `plugins/pitt-skills/.claude-plugin/plugin.json` (build.ps1 owns this file's `version` field; line 142 writes it).

**Step 4: Run Pester to confirm fixture match**

```bash
"$LOCALAPPDATA/Microsoft/WindowsApps/pwsh.exe" -NoProfile -Command "Invoke-Pester tests/ -Output Detailed -CI"
```

Expected: 38 passed.

**Step 5: Stage real changes only (filter autocrlf noise via numstat)**

```bash
git diff --numstat | grep -v '^0\s'
```

Expected real-content changes:
- `plugins/pitt-skills/.claude-plugin/plugin.json`
- `scripts/build.ps1`
- `tests/build/fixtures/write-fixtures.ps1`
- `tests/build/fixtures/expected/plugins/pitt-skills/.claude-plugin/plugin.json`

Stage just these:
```bash
git add plugins/pitt-skills/.claude-plugin/plugin.json scripts/build.ps1 tests/build/fixtures/write-fixtures.ps1 tests/build/fixtures/expected/plugins/pitt-skills/.claude-plugin/plugin.json
```

**Step 6: Commit**

```bash
git commit -m "chore: bump plugin to 1.11.0 for codebase-audit skill"
```

---

## Task 4: Smoke test the skill end-to-end

**Files:** (no file edits expected unless smoke test reveals issues)

**Step 1: Push the branch so a separate Claude Code session can pull it**

```bash
git push -u origin feat/codebase-audit-skill
```

**Step 2: In a separate Claude Code session, install the branch as a temp marketplace**

(This step is run by Justin manually, not by the automation, because installing a marketplace is interactive.)

Justin should:
1. Open a fresh Claude Code session in a small test project (e.g., `c:\Code\pitt-skills` itself).
2. Run: `/plugin marketplace update pitt-skills` to pick up the branch-tip if his local marketplace already points at this repo.
3. Confirm the new skill is registered: `/plugin` → list plugins → look for `codebase-audit`.
4. Trigger the skill: type literally `scan the code base for bugs, vulns, ux improvements, and performance issues`.

**Step 3: Verify trigger fires**

Expected: Claude announces "Using codebase-audit to ..." or similar. If no skill fires, the description needs tuning.

**Step 4: Verify orchestrator flow runs end-to-end**

Expected behaviors:
1. Project context detected (file count, languages, branch).
2. 4 parallel subagents dispatched (visible in Task tool calls).
3. Findings returned in JSON-ish format.
4. Confidence scoring runs (Haiku scorers visible).
5. Filter applied at threshold 70.
6. Interactive walk-through starts with `AskUserQuestion`.
7. After Justin tests Fix / Defer / Ignore on at least one finding each, the skill completes with a summary.

**Step 5: Document any issues found**

If anything diverges from expected behavior, iterate on `SKILL.md`. Each iteration is a new commit:

```bash
git commit -m "fix(codebase-audit): <specific fix>"
```

Common likely issues to expect:
- Trigger description too narrow → Justin's exact prompt doesn't match. Fix: widen the trigger phrasing in the description.
- Subagents return too many low-quality findings → tighten the brief or raise the confidence threshold from 70 to 75.
- Interactive walk-through stalls on first finding → check `AskUserQuestion` schema usage.
- `docs/audit/` directory not auto-created → ensure the Defer logic creates it.

**Step 6: If iterations happen, re-run build.ps1 and Pester after each, then commit each fix separately**

(No combined commit; one logical change per commit.)

---

## Task 5: Open PR and verify CI green

**Step 1: Push final state**

```bash
git push origin feat/codebase-audit-skill
```

**Step 2: Open the PR**

```bash
gh pr create --base main --head feat/codebase-audit-skill --title "feat(codebase-audit): whole-project quality sweep skill" --body "$(cat <<'EOF'
## Summary

Adds a `codebase-audit` skill that fires on broad whole-project scan / audit / sweep phrasing and runs a 4-dimension quality pass (bugs, vulnerabilities, UX, performance) with confidence-filtered findings and a per-finding fix / defer / ignore walk-through.

## Why

Existing skills are narrowly targeted (security-only, UX-only, PR-diff-only). No skill covers all four dimensions, none cover performance at all, and none trigger on broad "scan/audit/sweep" phrasing applied to a whole project. This skill fills the gap.

## What's in the skill

- Orchestrator flow that dispatches 4 parallel Sonnet subagents (bug-hunter, vuln-hunter, ux-reviewer, perf-reviewer).
- Subagent briefs that reference existing specialist skills (`owasp-security`, `vibesec`, `ui-ux-guide`) when installed.
- Confidence scoring (Haiku, 0-100 rubric, filter at 70, cap 15).
- Interactive walk-through via `AskUserQuestion` — Fix / Defer / Ignore per finding.
- Edge case handling: no findings, subagent failure, huge repos, re-run same day.

## Validated

- Trigger fires on Justin's literal end-of-task prompt.
- 4 parallel subagents dispatch and return JSON findings.
- Confidence scoring + filter + cap work as designed.
- Interactive walk-through cycles Fix / Defer / Ignore.
- Pester suite passes (38/38) after version bump 1.10.0 → 1.11.0.

## Design + plan

- Design: `docs/plans/2026-05-15-codebase-audit-design.md`
- Plan: `docs/plans/2026-05-15-codebase-audit-skill.md`

## Verify

- [ ] CI green (verify-build / pester / bats / version-bump)
- [ ] After merge, tag `v1.11.0` on the merge commit (per the post-merge tagging convention)
EOF
)"
```

**Step 3: Watch CI**

```bash
gh pr checks <PR-number> --watch
```

Expected: all 4 jobs pass (verify-build, version-bump, pester, bats). Typical durations: ~30s / ~5s / ~50s / ~10s.

**Step 4: Hand off for merge**

Justin merges when ready. Tagging `v1.11.0` is the post-merge step, not part of this PR.

---

## What's deliberately out of scope

Per the design doc:
- Automatic fix application without per-finding confirmation (Justin chose interactive).
- Single-dimension audits (use the specialist skills directly).
- PR-diff-only review (use `code-review` / `coderabbit`).
- Custom severity weighting per project.
- Saved configuration / settings file.
- Re-surfacing prior deferred items (the deferred file is reference-only; deferred items get re-surfaced on the next audit because subagents start fresh).

## Open follow-ups (after first real use, NOT in this PR)

- Calibrate the 70 confidence threshold and 15-finding cap from actual experience.
- Consider splitting accessibility out from UX into its own dimension if the UX subagent feels overloaded.
- Consider a `--fix-all` non-interactive mode for users who trust the scoring.
