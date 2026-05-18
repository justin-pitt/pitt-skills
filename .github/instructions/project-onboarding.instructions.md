---
applyTo: "**"
description: Use at the start of a session when the user asks you to familiarize yourself with a project, says "you'll be working out of the X project", asks for a tour of the codebase, runs /init, or otherwise needs you to come up to speed before doing real work. Triggers on phrases like "familiarize yourself", "get up to speed", "tour the code", "what's in this project", "give me the lay of the land", or any opening message that names a project (e.g., "reelisted", "autolab", "stageup", "TheCTIAgent") without a concrete task attached. Reads the workspace project map, the project's CLAUDE.md / AGENTS.md / Context Matrix, the manifest file, settings module, and recent git state, then presents a compact briefing — and surfaces project-specific gotchas before you start writing code. Do NOT use for: a concrete in-flight task ("fix the bug in X"), continuing work from a prior session (read _session-snapshot.md instead), or pure file-content questions ("what does this function do") — those don't need onboarding.
---

# Project onboarding

Most of Justin's sessions open with some variant of "you'll be working out of the X project, familiarize yourself with the codebase." Every time I do this manually I make slightly different choices about what to read first and what to surface — and I sometimes miss project-specific rules that are sitting in a CLAUDE.md, AGENTS.md, or Context Matrix one directory away. This skill makes the briefing repeatable, scoped to the right project, and aware of the workspace-level gotchas.

## When to use

Fire this skill at the **start of a session** when the user wants you to load context before working. Typical openers:

- "you'll be working out of the reelisted project"
- "familiarize yourself with the codebase"
- "get up to speed on autolab"
- "what's the lay of the land in TheCTIAgent"
- "tour the project"
- Or just a bare project name with no task ("we're in stageup today")

**Do NOT fire** when:

- The user gives a concrete task ("add a Stripe webhook to reelisted") — read only what the task needs.
- The user is continuing prior work — read `_session-snapshot.md` from auto-memory first (the compact-memory hook writes it pre-compaction).
- The user asks a narrow file question ("what does `process_mls_pdf` do") — just read the file.
- The user says `/init` and wants a CLAUDE.md generated — defer to the built-in `/init` command; this skill is for *understanding* a project, not authoring its CLAUDE.md.

## The briefing — six steps

Run these in order. Use `TodoWrite` to track. The whole flow should take under 60 seconds and produce a tight summary, not a wall of text.

### Step 1 — Identify the project

The current working directory tells you which project. Justin's workspace lives at `c:\Code` on Windows (or wherever cloned — check `pwd`). Each subdirectory is a separate project.

If the directory is ambiguous (you're at the workspace root, or the user names "the rental project" which could be `staybridge` or `stayvant`), **ask before reading**. The workspace `CLAUDE.md` has a project map you can use to disambiguate; quote the two candidates and let the user pick.

**Treat `-temp` and `-design` siblings as scratch.** If you're in `stageup-temp/` or `stayvant-design/`, the un-suffixed sibling (`stageup/`, `stayvant/`) is canonical — confirm with the user which one they actually want.

### Step 2 — Read the layered context

In parallel (single message, multiple tool calls), read whichever of these exist:

1. **Workspace `CLAUDE.md`** — usually at the workspace root. Has the project map, deploy-target conventions, branch policy, and cross-cutting rules (no Claude attribution in commits, never commit to `master`/`main`, use `curl` against Render REST API not the MCP tools).
2. **Project `CLAUDE.md`** — at the project root. Project-specific stack, commands, deploy notes.
3. **Project `AGENTS.md`** — some projects (notably `autolab-performance-py`) delegate to AGENTS.md instead of CLAUDE.md. If the project's CLAUDE.md is short and points elsewhere, follow the pointer.
4. **`.claude/CONTEXT_MATRIX.md`** — `TheCTIAgent` uses a Context Matrix to declare which files to load per task type. If it exists, read it; it will tell you what to read next.
5. **`README.md`** — fallback if the above are missing or thin.

### Step 3 — Read the manifest + settings

In parallel, read whichever applies to the project's stack:

- **Python**: `pyproject.toml` or `requirements.txt` + the settings module (`settings.py`, `config/`, `core/settings/`)
- **Node / Next.js**: `package.json` + `next.config.*` + `tsconfig.json`
- **React Native / Expo**: `package.json` + `app.json` / `app.config.*` + `eas.json`
- **Go**: `go.mod` + `main.go` or `cmd/`
- **Rust**: `Cargo.toml`
- **Ruby**: `Gemfile`

You're looking for: language version, framework version, key dependencies, deploy target hints, custom scripts (esp. `package.json` `"scripts"`).

### Step 4 — Read recent git state

Run `scripts/git-onboarding-snapshot.sh` (or `--json`) — it bundles the standard `branch --show-current` / `status --porcelain` / `log --oneline -10` / `branch -vv | head -20` quad with section headers.

Capture: current branch, dirty/clean, last ~10 commits (who's working on what), how many local branches exist, whether any are tracking gone remotes.

**If many stale branches show up**, mention it in the briefing and offer `branch-hygiene` as a follow-up — but do NOT auto-run it.

### Step 5 — Surface project-specific gotchas

Apply this checklist against what you read. **Only mention rules that apply to this project** — don't dump the full list every time.

| If the project … | Surface this rule |
|---|---|
| deploys to Render (reelisted, autolab, render-watchdog, render-discord-webhook, stayvant via Docker?) | Use `curl` against Render REST API, not the MCP tools. Read `render-api-guide.md` at workspace root before any Render API work — the `PUT /services/{id}/env-vars` is replace-all, and service creation triggers an immediate deploy before env vars can be set. |
| is `autolab-performance-py` | Dropship inventory: Shopify variants must have `inventoryItem.tracked=false` or Buy Buttons render "Out of Stock". `sync_shopify` runs chained with `scrape_prices` in the Render cron, not standalone. Custom-app permission changes go through versioned deploy + merchant approval, NOT uninstall/reinstall. |
| is React Native (`stageup`) | Never use `TouchableOpacity` from `react-native` inside `GestureHandlerRootView` — use `Pressable`. |
| is `TheCTIAgent` | Bugs go to Linear (project key in CLAUDE.md), not GitHub issues. Partner `chrisurline` also commits — pull origin first. Roast/banter tone in PR comments to chrisurline is the default, not polite. |
| is `pitt-skills` | `pwsh` on PATH is Windows PowerShell 5.1; use `$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe` for PS7-only scripts. Bump `plugins/pitt-skills/.claude-plugin/plugin.json` version in 3 places when any SKILL.md changes (build.ps1, write-fixtures.ps1, expected fixture). Defer `git tag` to post-merge. Marketplace registration must use HTTPS, not SSH shorthand. |
| has Docker / deploys to Fly.io (`stayvant`) | Read Dockerfile + `fly.toml` before assuming local-dev parity. |
| has EAS / TestFlight (`stageup`) | Preview vs production profiles diverge. Apple cert/provisioning profile capture format is consistent across releases — reuse, don't regenerate. |

**Universal rules to apply to every project** (these come from the workspace `CLAUDE.md` and Justin's global rules):

- **Never commit to `master` or `main` directly.** Use a feature branch or `justins-branch`.
- **No Claude attribution** in commit messages, PR titles, PR bodies, or anything that lands in version control. No `Co-Authored-By: Claude`, no "🤖 Generated with Claude Code".
- **Research errors before fixing.** When the user reports an error, WebSearch the exact message first; don't guess.

### Step 6 — Brief the user

Print a compact summary in this shape (adapt the headings to the project):

```
## <project-name> briefing

**Stack**: <lang+framework versions> · **Deploy**: <target>
**Branch**: <current> (<clean|N uncommitted>) · **Recent**: <1-line on last few commits>

**Project-specific rules in play**:
- <only the rules from Step 5 that actually apply>

**Open questions / things to know**:
- <stale branch count if notable>
- <anything surprising from CLAUDE.md / AGENTS.md / settings>
- <if a _session-snapshot.md exists, mention it and offer to read>

What would you like to work on?
```

Keep this **under 25 lines**. The user has the same screen real estate you do; long briefings buy nothing.

## Edge cases

- **No `CLAUDE.md` or `AGENTS.md` at all** — read README, manifest, top-level source dir to infer stack. Mention in the briefing that the project lacks a CLAUDE.md and offer to draft one (defer to `/init` if Justin agrees).
- **Project not in the workspace map** — read what you can, brief normally, and mention that the project isn't listed in the workspace `CLAUDE.md` table (Justin may want to add it).
- **Monorepo or multi-app project** — identify the top-level orchestration first (root `package.json` workspaces, root `pyproject.toml`, `lerna.json`, etc.), then ask which sub-app the user wants to focus on before going deeper.
- **Recently-compacted session** — if `_session-snapshot.md` exists in auto-memory and is recent (check mtime), read it BEFORE doing the rest of this flow; the snapshot may make most of these steps redundant. Surface what was in flight, then ask whether to continue or start fresh.
- **The user contradicts a rule from the briefing** — defer to the user (per global instruction priority). E.g., if you surfaced "no Claude attribution" but the user explicitly asks for it, comply and don't re-litigate.

## Integration

- **Pairs with `compact-memory`** — the session snapshot it writes is the first thing to check on a resumed session.
- **Pairs with `branch-hygiene`** — if Step 4 surfaces many stale branches, offer this as a follow-up.
- **Pairs with `codebase-audit`** — once onboarded, a whole-project audit is a natural next step if the user wants a quality sweep.
- **Pairs with `find-skills`** — if the project's domain (Shopify, ThreatConnect, Tines, Cortex XSIAM) maps to an installed specialist skill, mention it in the briefing.
