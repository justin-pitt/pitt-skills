---
applyTo: "**"
description: Use when the user asks to scan, audit, sweep, or review the codebase (or "code base") for bugs, vulnerabilities, UX improvements, or performance issues — typically at end-of-task as a proactive whole-project quality pass. Triggers on phrases like "scan the code base", "audit the code", "review the project", "sweep for issues", "look for bugs and vulns", or any request bundling two or more of: bugs / vulns / security / UX / accessibility / performance / quality. Dispatches 4 parallel reviewers (bug, vuln, UX, perf), confidence-scores findings, and walks the user through fix / defer / ignore per finding. Do NOT use for: reviewing a specific PR diff (use code-review or coderabbit), reviewing only recently-changed code on a branch (use requesting-code-review), or single-dimension audits (use owasp-security / ui-ux-guide / vibesec directly).
---

# Codebase audit

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

## Orchestrator flow

Run these 8 steps in order. Each step is mandatory. Use `TodoWrite` to track progress through the steps.

### Step 1 — Detect project context

Capture:
- Project root (current working directory unless the user specified another).
- Languages present, inferred from file extensions via `Glob` (e.g., `**/*.py`, `**/*.ts`, `**/*.tsx`, `**/*.go`).
- Frameworks present, inferred from manifest files: `package.json`, `pyproject.toml`, `requirements.txt`, `go.mod`, `Cargo.toml`, `Gemfile`.
- Git state: current branch and dirty/clean.
- Rough file count: use the `Glob` tool with pattern `**/*` then count results. Skip files under `.git/`, `node_modules/`, `__pycache__/`, `.venv/`, `dist/`, `build/` to keep the count meaningful.

### Step 2 — Huge-repo guard

If file count > 1500 (calibrated so typical Django/Next.js projects don't trip the guard; small CLI tools and libraries are well under), ask the user via `AskUserQuestion` whether to:
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
    "suggested_fix": "what to change",
    "confidence": null
  }
]
```

Dimension subagents leave `confidence` as `null`; the controller fills it in Step 5 after Haiku scoring.

### Step 5 — Confidence-score findings via parallel Haiku scorers

For each finding, dispatch a Haiku agent (`Task` tool, `subagent_type: general-purpose`, `model: haiku`) to score 0-100 confidence using the rubric below. Run all scorers in one parallel batch (multiple `Task` tool_use blocks in one message). The scorer reads the finding (and may verify by reading the cited file/line), then returns a single integer 0-100; the controller attaches this back to the finding as a `confidence` field before Step 6.

### Step 6 — Filter + rank

- Filter out any finding with confidence score < 70.
- Cap the result list at 15 findings total. If more than 15 survive filtering, drop the lowest-confidence ones.
- Rank by: severity (critical > high > medium > low), then dimension priority (vuln > bug > perf > ux), then confidence descending.

### Step 7 — Interactive walk-through

For each ranked finding, present an `AskUserQuestion` with:
- Header: `<dimension> N/M` (e.g., "Vuln 3/12")
- Question body: severity / file:line / title / why / suggested_fix
- Options: **Fix it** / **Defer** / **Ignore**

Per choice:
- **Fix it** → dispatch an implementer subagent (`Task` tool, `model: sonnet`) with the finding + project context. Subagent reports back; controller continues to next finding.
- **Defer** → append a markdown bullet to `docs/audit/YYYY-MM-DD-deferred.md` (create the directory if it doesn't exist; append rather than overwrite if the file already exists today).
- **Ignore** → skip; do not record anywhere.

### Step 8 — Final summary

After processing the last finding, print one paragraph: counts of fixed / deferred / ignored, plus path to the deferred file if any.

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

## Confidence scoring

For each finding, dispatch a Haiku scorer. The scorer reads the finding, optionally checks the cited file/line, and returns a score 0-100 using this rubric (give it to the scorer verbatim):

- **0** — Not confident at all. False positive that doesn't stand up to light scrutiny, or pre-existing issue.
- **25** — Somewhat confident. Might be a real issue, may also be a false positive. Couldn't verify it's real. Stylistic and not explicitly called out by any project rule.
- **50** — Moderately confident. Verified real but might be a nitpick or rare. Not very important relative to the rest of the audit.
- **75** — Highly confident. Double-checked, very likely a real issue hit in practice. Existing code is insufficient. Important and directly impacts functionality.
- **100** — Absolutely certain. Double-checked, definitely real, will happen frequently. Evidence directly confirms.

Filter cutoff: **70**. Cap total findings at **15** (drop lowest-confidence first if more than 15 survive).

## Interactive walk-through

Use `AskUserQuestion` per finding. Pass these fields:

- `question`: `<dimension> finding N/M — <severity>` (e.g., "Vuln finding 3/12 — high"). Include file:line, title, 1-2 sentence "why", and the suggested fix on separate lines inside the question body so the user has enough context to choose.
- `header`: short label, max 12 chars (e.g., "Vuln 3/12").
- `multiSelect`: `false`.
- `options`: exactly three, each with both `label` and `description`:

```json
[
  { "label": "Fix it",  "description": "Apply the suggested fix now. The controller will dispatch an implementer subagent with the finding context." },
  { "label": "Defer",   "description": "Save the finding to docs/audit/<today>-deferred.md to address later." },
  { "label": "Ignore",  "description": "Skip; this is a false positive or not worth fixing." }
]
```

**On Fix:** dispatch an implementer subagent (`Task` tool, `general-purpose`, `model: sonnet`) with:
- The finding (severity, file:line, title, why, suggested_fix)
- The project context summary from Step 1
- Instruction: implement the fix, verify it doesn't break adjacent code, return when done

After the implementer returns, continue to the next finding.

**On Defer:** ensure `docs/audit/` exists. Append (do not overwrite) to `docs/audit/<YYYY-MM-DD>-deferred.md`. On the first deferred finding of this run, append a header line `## <HH:MM UTC>` so re-runs the same day stay separated. Then append a bullet in this format:

```markdown
- [<severity>] <dimension>: <title> — `<file>:<line>` — <why>. Fix: <suggested_fix>.
```

**On Ignore:** skip silently.

Loop until all findings processed. Then print final summary.

## Edge cases

- **No findings in any dimension:** print "Audit clean." and exit. Do not run the interactive walk-through.
- **Subagent fails or times out:** note which dimension dropped in the final summary, continue with the remaining dimensions' findings.
- **Re-run same day:** the deferred file appends rather than overwrites; the new entries land below the existing ones with a `## <time>` divider.
- **Project root ambiguous:** ask the user explicitly which directory to audit before dispatching subagents.
- **No specialist skill installed for a dimension:** the corresponding subagent still runs with general best-practice guidance; just skip the `Read <skill>/SKILL.md` step.
