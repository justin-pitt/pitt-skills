# Codebase-audit skill — design

## Goal

A pitt-skills skill that fires on broad whole-project scan / audit phrasing and runs a four-dimension quality pass (bugs, vulnerabilities, UX, performance) with confidence-filtered findings and a per-finding fix/defer/ignore walk-through.

## Why this exists

Justin runs the prompt "scan the code base for bugs, vulns, ux improvements, and performance issues" at end-of-task and no skill fires. Existing skills are narrowly targeted:

| Skill | Coverage |
|---|---|
| `owasp-security`, `vibesec` | Security only |
| `ui-ux-guide` | UX only |
| `systematic-debugging` | Reactive bug fixing |
| `requesting-code-review` | PR/branch review workflow |
| `coderabbit:code-review`, `pr-review-toolkit:review-pr` | PR diff scope |
| `aikido:scan`, `semgrep` | External scanners, security-only |

No single skill covers all four dimensions, none cover performance, and none trigger on broad "scan/sweep/audit" phrasing applied to a whole project. The new skill fills the gap.

## Architecture

A single-file orchestrator skill at `plugins/pitt-skills/skills/codebase-audit/SKILL.md`. No additional assets.

Flow:

1. **Detect project context** — current working directory, languages present (via glob over file extensions), git state (current branch, dirty?), rough file count.
2. **Dispatch 4 parallel Sonnet subagents** via the Task tool, one per dimension. Each receives the project root, the context summary, a dimension brief, and a reference to its specialist skill if installed.
3. **Each subagent returns a flat list of findings:** `{ severity, file, line, dimension, title, why, suggested_fix }`. Severity is `critical | high | medium | low`.
4. **Confidence-score each finding** via parallel Haiku scorers (0-100 rubric, same five levels as the existing `code-review` skill: 0 / 25 / 50 / 75 / 100).
5. **Filter at threshold 70.** Cap at 15 findings total to keep the interactive walk-through tractable.
6. **Rank.** Severity first (critical > high > medium), then dimension priority (vulns > bugs > perf > UX).
7. **Walk findings interactively** via `AskUserQuestion` — per finding, offer **Fix it / Defer / Ignore**.
   - Fix: dispatch an implementer subagent with the finding + project context.
   - Defer: append the finding to `docs/audit/YYYY-MM-DD-deferred.md` (one file per audit day, append-only on re-runs).
   - Ignore: skip.
8. **Final summary** — count of fixed / deferred / ignored, path to the deferred-findings file.

## Trigger description

```yaml
name: codebase-audit
description: Use when the user asks to scan, audit, sweep, or review the
  codebase (or "code base") for bugs, vulnerabilities, UX improvements, or
  performance issues — typically at end-of-task as a proactive whole-project
  quality pass. Triggers on phrases like "scan the code base", "audit the
  code", "review the project", "sweep for issues", "look for bugs and vulns",
  or any request bundling two or more of: bugs / vulns / security / UX /
  accessibility / performance / quality. Dispatches 4 parallel reviewers,
  confidence-scores findings, and walks the user through fix / defer / ignore
  per finding. Do NOT use for: reviewing a specific PR diff (use code-review
  or coderabbit), reviewing only recently-changed code on a branch (use
  requesting-code-review), or single-dimension audits (use owasp-security
  / ui-ux-guide / vibesec directly).
```

Justin's literal end-of-task prompt — "scan the code base for bugs, vulns, ux improvements, and performance issues" — matches verbatim (phrase + four dimensions).

## Subagent briefs

Each subagent receives:

- Project root path
- Context summary (languages, frameworks, file count, branch, dirty state)
- Dimension brief (focus, anti-focus, output format)
- Reference to specialist skill if installed: `Read <skill-path>` for `owasp-security`, `vibesec`, `ui-ux-guide`
- Output schema: `[{severity, file, line, dimension, title, why, suggested_fix}]`

### bug-hunter

**Focus:** logic errors, dead/unreachable code, swallowed exceptions, off-by-one, race conditions, missing null/empty checks at boundaries (user input, external API responses, file I/O).
**Anti-focus:** style, formatting, naming, code smells without clear behavior impact.

### vuln-hunter

**Focus:** OWASP Top 10 (injection, broken auth, IDOR, SSRF, XSS, insecure deserialization, etc.), hardcoded secrets / API keys, dependency confusion risks, missing CSRF / auth checks, unsafe `eval`/`exec`/template rendering. Pulls reference from `owasp-security` and `vibesec` if installed.
**Anti-focus:** infosec hygiene that doesn't ship in code (2FA policy, password rotation cadence, etc.).

### ux-reviewer

**Focus:** affordance gaps, missing error/empty/loading states, copy density and clarity, focus management, accessibility basics (alt text, label association, keyboard nav, ARIA where load-bearing). Pulls reference from `ui-ux-guide` if installed.
**Anti-focus:** visual styling preferences, exact color/spacing values, brand opinions.

### perf-reviewer

**Focus:** N+1 queries, missing indexes on hot queries, synchronous I/O in async paths, large bundles / heavy unconditional imports, render churn (React component re-renders without memoization), memory leaks (unbounded caches, event listeners without cleanup), expensive ops in hot paths.
**Anti-focus:** micro-optimizations, theoretical perf concerns without a real hot path.

## Confidence scoring

Same 0-100 rubric as the `code-review` skill (so the pattern is consistent across Justin's review skills):

- **0** — false positive on light scrutiny, or pre-existing
- **25** — somewhat confident, couldn't verify, stylistic
- **50** — verified real but nitpicky / rare
- **75** — high confidence, likely hit in practice, important
- **100** — certain, will fire frequently, evidence directly confirms

Filter cutoff is **70**, lower than code-review's 80, because this is a proactive sweep where borderline items are still worth surfacing — the user filters via the interactive walk-through.

## Interactive walk-through

Per finding, present via `AskUserQuestion`:

- Question header: dimension (e.g., "Vuln finding 3/12")
- Question body: severity / file:line / title / why / suggested_fix
- Options: **Fix it** / **Defer** / **Ignore**

Loop until all findings processed. End with a one-paragraph summary: fixed N, deferred M (path), ignored K.

## Edge cases

- **No findings in any dimension:** print "Audit clean." and exit. No interactive walk-through.
- **Subagent fails or times out:** note which dimension dropped in the final summary, continue with the remaining dimensions.
- **Huge repos (>500 files):** before dispatching, warn and ask whether to proceed full, scope to recently-changed directories (last 7 days), or accept a user-supplied subdirectory list.
- **Re-run same day:** the `docs/audit/YYYY-MM-DD-deferred.md` file appends rather than overwrites.
- **Project root ambiguous:** ask the user explicitly which directory to audit.

## Testing approach

- **Smoke test on `pitt-skills` itself.** Small codebase, well-known to me. Verifies the skill fires, subagents dispatch, scoring + filtering + walk-through work end-to-end.
- **Real-world test on `reelisted` or `autolab-performance-py`.** Validates scaling on a larger Django codebase. Exposes any noise / threshold issues.
- **Trigger test.** Confirm Justin's literal end-of-task prompt fires this skill and no other skill beats it on specificity. Test the shorter variants ("scan it", "audit the code").

## Out of scope (YAGNI)

- Automatic fix application without confirmation (Justin chose interactive)
- Single-dimension audits (use the existing specialist skills directly)
- PR-diff-only review (use `code-review` / `coderabbit`)
- Custom severity weighting per project (hardcode dimension priority for now: vulns > bugs > perf > UX)
- Saved configuration / settings file (one default config, override via prompt if needed)
- Re-running prior deferred items (the deferred file is reference-only; deferred items get re-surfaced on the next audit because the subagents start fresh)

## Open follow-ups (not blocking)

- After first real use, calibrate the 70 confidence threshold and 15-finding cap from actual experience
- Consider adding a 5th dimension (accessibility as its own dimension instead of folded into UX) if the UX subagent feels overloaded
- Consider a `--fix-all` mode that skips the walk-through for users who trust the scoring (not now)
