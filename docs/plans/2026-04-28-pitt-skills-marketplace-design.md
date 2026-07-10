# pitt-skills marketplace — design

**Date:** 2026-04-28
**Status:** Approved, ready for implementation planning
**Author:** Justin Pitt (with Claude)

## Context

I want a single GitHub repo that:

1. **Syncs my Claude Code skills between my home and work laptops** — `git pull` is the update verb.
2. **Doubles as a personal Claude Code marketplace** — installable via `/plugin marketplace add justin-pitt/pitt-skills`.
3. **Is shareable with coworkers** who use GitHub Copilot in three forms: VS Code Chat (most common), Copilot CLI, and the Copilot Desktop App.

The repo lives on my personal public GitHub. Coworkers can clone freely; my employer does not restrict cloning external public repos.

## Goals

- One source of truth (`SKILL.md` files) — author once, distribute everywhere.
- Symlink-based install so `git pull` propagates updates to every tool with no further action.
- Prompt-driven onboarding: paste-a-prompt-into-your-AI install path for non-technical coworkers.
- Hybrid sourcing: vendor only the skills I've forked; reference unmodified upstream marketplaces in a curated catalog.

## Non-goals

- A multi-tier build pipeline. We're at ~10–50 skills, not hundreds.
- A separate enterprise mirror repo (Approach B from brainstorming). Compliance allows the personal-public model.
- Org-level Copilot Chat instructions. Coworkers opt in per-machine.
- Skill quality automation (linting, eval harnesses, test fixtures). Out of scope for v1.

## Architecture

### Repo layout

```
pitt-skills/
├── README.md                           ← landing: install instructions per audience
├── .claude-plugin/
│   └── marketplace.json                ← Claude marketplace catalog (generated)
├── plugins/
│   └── pitt-skills/                    ← single plugin wrapping all my skills
│       ├── .claude-plugin/plugin.json  ← plugin manifest (generated)
│       └── skills/
│           ├── <skill-name>/SKILL.md   ← canonical authored format
│           └── ...
├── .github/                            ← GENERATED — do not hand-edit
│   ├── copilot-instructions.md
│   ├── instructions/<name>.instructions.md
│   ├── prompts/<name>.prompt.md        ← only when SKILL opts in
│   └── agents/<name>.agent.md          ← only when SKILL opts in
├── catalog/
│   └── upstream.md                     ← curated list of unmodified third-party marketplaces I rely on
├── scripts/
│   ├── build.ps1 / build.sh            ← regenerates .github/* and JSON manifests from skills/
│   └── install.ps1 / install.sh        ← symlinks for personal use across machines
├── settings.snippet.json               ← drop-in for ~/.claude/settings.json
└── docs/
    ├── plans/                          ← this design doc and future plans live here
    └── authoring-a-skill.md
```

### Sourcing strategy (hybrid)

| Category | Storage |
|---|---|
| Skills I wrote from scratch | First-class — `plugins/pitt-skills/skills/<name>/SKILL.md` |
| Third-party I've customized | Vendored copy in same place + `UPSTREAM.md` (source repo, commit SHA, license, my changes) |
| Third-party unmodified | **Reference, don't vendor** — entry in `catalog/upstream.md` + `extraKnownMarketplaces` block in `settings.snippet.json` |

Rationale: vendoring stuff you don't fork rots — upstream changes, you don't pull. Reference what you don't customize; vendor only when you actually fork.

### Authoring format — `SKILL.md`

```yaml
---
name: <skill-name>
description: <one-line trigger description>
license: MIT
allowed-tools: [...]
copilot-chat:
  applyTo: "**"            # default: always-on
  prompt: false            # opt-in: also emit .prompt.md
  agent: false             # opt-in: emit .agent.md instead of .instructions.md
---

<skill body — markdown>
```

The `copilot-chat` block is custom frontmatter; ignored by Claude Code and Copilot CLI, consumed only by `build.ps1`.

### Build pipeline

`scripts/build.ps1` (and Bash mirror) walks `plugins/pitt-skills/skills/`, and for each `SKILL.md`:

1. Always emits `.github/instructions/<name>.instructions.md` (rewritten frontmatter to Copilot's `applyTo` schema).
2. If `copilot-chat.prompt: true`, also emits `.github/prompts/<name>.prompt.md`.
3. If `copilot-chat.agent: true`, emits `.github/agents/<name>.agent.md` instead of an instruction file.
4. Regenerates `.claude-plugin/marketplace.json` and `plugins/pitt-skills/.claude-plugin/plugin.json` so adding a skill never requires manual JSON edits.
5. Writes a `.github/copilot-instructions.md` preamble pointing readers at the catalog.

**Idempotent.** GitHub Actions runs `build.ps1` on every PR and fails if `.github/*` is dirty — proves consistency.

**Language:** PowerShell (matches Windows-first workflow), with a thin `build.sh` Bash wrapper for CI / non-Windows contributors.

### Install / sync mechanism

The four target tools and what they natively read:

| Tool | Reads from | Format |
|---|---|---|
| Claude Code | `~/.claude/plugins/...` (registered marketplace) + `~/.claude/skills/<name>/SKILL.md` (standalone) | `SKILL.md` |
| Copilot CLI | `~/.copilot/skills/<name>/SKILL.md` + `.claude/skills/` | `SKILL.md` |
| VS Code Copilot Chat | workspace `.github/instructions/` + `~/.copilot/instructions/` | `*.instructions.md` |
| Copilot Desktop App | same user-level paths as VS Code | same |

`scripts/install.ps1` (mirror in `install.sh`):

1. Detect installed tools.
2. **Claude Code** — auto-merge the contents of `settings.snippet.json` into `~/.claude/settings.json` (preserving existing keys; backup written next to the original; `-WhatIf` flag for dry-run). Optionally symlink each `plugins/pitt-skills/skills/<name>/` into `~/.claude/skills/<name>/` for unprefixed access (off by default).
3. **Copilot CLI** — symlink `plugins/pitt-skills/skills/` → `~/.copilot/skills/`.
4. **VS Code / Desktop Copilot Chat** — symlink `.github/instructions/` → `~/.copilot/instructions/` and `.github/prompts/` → `~/.copilot/prompts/`.
5. Print a summary of what was wired.

**Flags:** `-WhatIf`, `-Tools claude,copilotCli,vscode`, `-Force`, `-Uninstall`.

**Windows symlink fallback:** detect Developer Mode; fall back to junction points / `mklink` when not enabled. No admin required either way.

**Updates:** `git pull` only. Symlinks point at the live tree; no re-install needed. CI has already regenerated `.github/*` from any SKILL.md change at PR time.

### Prompt-driven install (for coworkers)

The README features a one-paste prompt for any AI assistant the coworker uses:

```
Clone https://github.com/justin-pitt/pitt-skills into ~/Code/pitt-skills
(or %USERPROFILE%\Code\pitt-skills on Windows). After cloning, run
./scripts/install.ps1 on Windows or ./scripts/install.sh on macOS/Linux.
Show me the installer's summary output, then tell me which tools were
detected and wired up. If anything failed, propose a fix before retrying.
```

With tool-specific tails appended:

- **Claude Code:** "When done, also tell me to restart Claude Code so the new pitt-skills marketplace gets registered."
- **Copilot CLI:** "When done, run `/skills reload` and confirm pitt-skills entries appear."
- **VS Code Copilot Chat:** "When done, remind me to reload the VS Code window (Ctrl+Shift+P → Developer: Reload Window)."
- **Copilot Desktop App:** "When done, remind me to fully quit and reopen the Copilot desktop app."

Manual fallback documented for users who'd rather not let an agent run scripts:

```bash
git clone https://github.com/justin-pitt/pitt-skills ~/Code/pitt-skills
cd ~/Code/pitt-skills
pwsh ./scripts/install.ps1     # or ./scripts/install.sh
```

### Versioning

- `plugin.json` carries a `version` field bumped on releases (semver).
- CI fails if any `SKILL.md` changed but `version` did not.
- Override: include `[skip-bump]` in the commit message for docs-only changes.
- Without a `version`, Claude resolves to git commit SHA — adequate for personal sync but discouraged for the shared distribution path.

### Authoring & maintenance workflow

**New custom skill:**

1. Use `skill-creator` to scaffold `~/.claude/skills/<name>/SKILL.md`.
2. Author and test locally.
3. `mv` into `<repo>/plugins/pitt-skills/skills/<name>`.
4. (Optional) re-run `install.ps1` if standalone-symlinks are enabled.
5. `scripts/build.ps1` → regenerates derived files.
6. Commit + push. CI verifies clean rebuild.

**Vendor a third-party skill (forking it):**

1. Copy from upstream cache into `plugins/pitt-skills/skills/<name>/`.
2. Add `UPSTREAM.md` with source repo + commit SHA + license + change log.
3. Preserve any upstream `LICENSE` file alongside.
4. Build, commit, push.

**Reference an unmodified upstream marketplace (no vendoring):**

1. Add an entry to `catalog/upstream.md` with the install one-liner.
2. Add the marketplace to `settings.snippet.json` under `extraKnownMarketplaces` so the installer auto-registers it.

**Two-machine sync:**

- Home → Work: push, pull on work — symlinks resolve to the live tree, every tool sees changes.
- The only machine-specific file is `~/.claude/settings.json` itself; the installer tracks what it merged via a marker so re-runs are idempotent.

## Decisions log

| # | Decision | Rationale |
|---|---|---|
| 1 | Approach A (one personal public repo, dual-format) | No employer restrictions on external clones; one repo is dramatically simpler than two. |
| 2 | Repo name: `pitt-skills` | User choice. |
| 3 | Single plugin wrapping all skills | At this scale, fragmentation costs more than it saves. Each skill remains independently invokable via `pitt-skills:<name>`. |
| 4 | Hybrid sourcing (vendor forks, reference unmodified) | Vendoring everything rots; pure references lose customization control. |
| 5 | `SKILL.md` only as authored format; `.github/*` is generated | Single source of truth; build script enforces consistency. |
| 6 | Symlink-based install (not copy) | Makes `git pull` the only update verb. |
| 7 | Build script: PowerShell + Bash wrapper | Matches Windows-first workflow; CI works on Linux runners. |
| 8 | CI enforcement: rebuild on PR, fail if `.github/*` dirty | Provable repo consistency; ~20 lines. |
| 9 | Auto-merge into `~/.claude/settings.json` (with backup + dry-run) | Convenience over transparency, with safeguards. *Subject to revision per user.* |

## Open questions / deferred

- Whether to default the "symlink select skills into `~/.claude/skills/` for unprefixed access" install option to on or off. Currently off — revisit after using the marketplace for a few weeks.
- Settings.json auto-merge default — user reserved the right to flip to "print-and-paste" later.
- Whether to publish a Claude marketplace badge / catalog entry to `awesome-claude-skills` and `awesome-copilot` once the repo is stable.

## Implementation handoff

Next: invoke `superpowers:writing-plans` to convert this design into a step-by-step implementation plan with task ordering, validation steps, and review checkpoints.
