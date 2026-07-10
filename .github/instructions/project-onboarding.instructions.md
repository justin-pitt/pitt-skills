---
applyTo: "**"
description: Use at the start of a session when the user asks you to familiarize yourself with a project, says "you'll be working out of the X project", asks for a tour of the codebase, runs /init, or otherwise needs you to come up to speed before doing real work. Triggers on phrases like "familiarize yourself", "get up to speed", "tour the code", "what's in this project", "give me the lay of the land", or any opening message that names a project or directory without a concrete task attached. Reads the workspace project map (if any), the project's CLAUDE.md / AGENTS.md / context files, the manifest file, settings module, and recent git state, then presents a compact briefing — and surfaces project-specific gotchas before you start writing code. Do NOT use for: a concrete in-flight task ("fix the bug in X"), continuing work from a prior session (read the session snapshot instead), or pure file-content questions ("what does this function do") — those don't need onboarding.
---

# Project onboarding

Many sessions open with some variant of "you'll be working out of the X project, familiarize yourself with the codebase." Done by hand, the briefing comes out slightly different every time — and it's easy to miss a project-specific rule sitting in a CLAUDE.md, AGENTS.md, or context file one directory away. This skill makes the briefing repeatable, scoped to the right project, and aware of the gotchas before you start writing code.

## When to use

Fire this skill at the **start of a session** when the user wants you to load context before working. Typical openers:

- "you'll be working out of the X project"
- "familiarize yourself with the codebase"
- "get up to speed on this repo"
- "what's the lay of the land here"
- "tour the project"
- Or just a bare project name with no task attached

**Do NOT fire** when:

- The user gives a concrete task ("add a Stripe webhook") — read only what the task needs.
- The user is continuing prior work — read the session snapshot first (if the environment writes one pre-compaction).
- The user asks a narrow file question ("what does this function do") — just read the file.
- The user says `/init` and wants a CLAUDE.md generated — defer to the built-in `/init` command; this skill is for *understanding* a project, not authoring its CLAUDE.md.

## The briefing — six steps

Run these in order. Use `TodoWrite` to track. The whole flow should take under 60 seconds and produce a tight summary, not a wall of text.

### Step 1 — Identify the project

The current working directory tells you which project — check `pwd`. If the workspace holds many independent repos as sibling subdirectories, each subdirectory is a separate project.

If the directory is ambiguous (you're at a workspace root, or the user names something that could match more than one project), **ask before reading**. If a workspace-level `CLAUDE.md` has a project map, use it to disambiguate; quote the candidates and let the user pick.

**Treat `-temp`, `-scratch`, and `-design` siblings as scratch.** If you're in a clearly suffixed scratch/design-export folder, the un-suffixed sibling is usually canonical — confirm with the user which one they actually want.

### Step 2 — Read the layered context

In parallel (single message, multiple tool calls), read whichever of these exist:

1. **Workspace `CLAUDE.md`** — if the project lives inside a larger workspace, the root often has a project map, deploy-target conventions, branch policy, and cross-cutting rules.
2. **Project `CLAUDE.md`** — at the project root. Project-specific stack, commands, deploy notes.
3. **Project `AGENTS.md`** — some projects delegate to AGENTS.md instead of CLAUDE.md. If the project's CLAUDE.md is short and points elsewhere, follow the pointer.
4. **Other declared context files** — some projects use a context matrix or index file (e.g. `.claude/CONTEXT_MATRIX.md`) to declare which files to load per task type. If one exists, read it; it will tell you what to read next.
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

**If many stale branches show up**, mention it in the briefing and offer branch cleanup as a follow-up — but do NOT auto-run it.

### Step 5 — Surface project-specific gotchas

The goal here is to surface the rules that will bite you *before* you write code — not to dump a generic checklist. Gather them from what you actually read, then mention only what applies to this project.

Where the gotchas live:

- **Documented rules** — anything the project's `CLAUDE.md` / `AGENTS.md` / context files explicitly call out (conventions, "always/never" rules, ordering requirements, known traps). These are the highest-signal source — quote them.
- **Deploy-target specifics** — how this project ships (PaaS, container, app store, package registry) often carries traps: env-var APIs that replace-all instead of merge, build steps that must run before deploy, credentials/profiles that must be reused rather than regenerated. Check the deploy config and any deploy guide the repo references.
- **Stack / framework quirks** — version-specific gotchas, required tooling versions, generated artifacts that must be rebuilt after a source change, line-ending or platform pitfalls.
- **Collaboration rules** — if more than one person commits, note pull-before-push expectations; surface any commit-message, attribution, or branch-naming conventions the repo or the user's own config declares.

**Universal rules to apply to every project** — but source them from the *user's own* configuration, don't invent them:

- **Branch protection** — many setups forbid committing directly to `main`/`master`; use a feature branch. Honor whatever the workspace or project config states.
- **Commit / PR conventions** — surface whatever commit-message, attribution, or sign-off rules the user's CLAUDE.md / global config declares.
- **Research errors before fixing** — if the user's config asks you to look up an error before proposing a fix, follow it.

If the project's config declares no such rules, don't impose any — just note that none were found.

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
- <if a session snapshot exists, mention it and offer to read>

What would you like to work on?
```

Keep this **under 25 lines**. The user has the same screen real estate you do; long briefings buy nothing.

## Edge cases

- **No `CLAUDE.md` or `AGENTS.md` at all** — read README, manifest, top-level source dir to infer stack. Mention in the briefing that the project lacks a CLAUDE.md and offer to draft one (defer to `/init` if the user agrees).
- **Project not in the workspace map** — read what you can, brief normally, and mention that the project isn't listed in the workspace `CLAUDE.md` table (the user may want to add it).
- **Monorepo or multi-app project** — identify the top-level orchestration first (root `package.json` workspaces, root `pyproject.toml`, `lerna.json`, etc.), then ask which sub-app the user wants to focus on before going deeper.
- **Recently-compacted session** — if a session snapshot exists and is recent (check its mtime), read it BEFORE doing the rest of this flow; the snapshot may make most of these steps redundant. Surface what was in flight, then ask whether to continue or start fresh.
- **The user contradicts a rule from the briefing** — defer to the user (per instruction priority). If you surfaced a convention but the user explicitly asks for the opposite, comply and don't re-litigate.

## Integration

- **Pairs with a session-snapshot / memory skill** — a snapshot written pre-compaction is the first thing to check on a resumed session.
- **Pairs with branch cleanup** — if Step 4 surfaces many stale branches, offer cleanup as a follow-up.
- **Pairs with a codebase-audit skill** — once onboarded, a whole-project audit is a natural next step if the user wants a quality sweep.
- **Pairs with a skill-finder** — if the project's domain maps to an installed specialist skill, mention it in the briefing.
