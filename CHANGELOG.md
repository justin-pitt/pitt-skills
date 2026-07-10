# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.15.0] - 2026-05-17

Skill-pack-wide audit pass: visibility, deterministic-vs-judgment split, and composability cleanup.

### Added
- Deterministic helper scripts pulled out of skill prose (same result every run, zero token cost):
  - `branch-hygiene/scripts/collect-branch-facts.sh` — local branches, remote/upstream, worktrees, open PRs in one shot.
  - `codebase-audit/scripts/project-inventory.py` — file-extension histogram, file/dir counts, manifest detection.
  - `project-onboarding/scripts/git-onboarding-snapshot.sh` — bundled `git status`/`branch -vv`/`log` snapshot.
  - `writing-skills/scripts/validate-skill-frontmatter.py` — strict SKILL.md frontmatter validator.
  - `writing-plans/scripts/scan-plan-placeholders.py` — flags `TODO`/`<placeholder>`/`FIXME` style gaps.
  - `subagent-driven-development/scripts/extract-plan-tasks.py` — parses plan files into `{title,status,body,files}` JSON.
  - `file-organizer/scripts/dir-inventory.sh` and `duplicate-hashes.sh` — directory inventory and SHA-256 duplicate finder.
  - `compact-memory/scripts/encode-memory-dir.sh` and `encode-memory-dir.ps1` — workspace-path → memory-dir encoder.
  - `using-git-worktrees/scripts/worktree-preflight.sh` and `run-project-deps.sh` — worktree directory + gitignore check, multi-stack dependency installer.
  - `requesting-code-review/scripts/review-range-shas.sh` — picks `BASE_SHA`/`HEAD_SHA` against `origin/main` (fallback `origin/master`, then `HEAD~1`) and exports changed-file list.

### Changed
- Visibility hardening:
  - `disable-model-invocation: true` on high-side-effect skills: `finishing-a-development-branch`, `branch-hygiene`, `agent-browser`, `playwright-testing/playwright-cli`. They are still `/run`-able by the user but Claude no longer auto-fires them.
  - `user-invocable: false` on pure-knowledge / context skills (16 total) so they don't clutter the `/` menu but still feed context: `cortex-xsiam`, `tines`, `tufin`, `threatconnect`, `openrouter`, `owasp-security`, `vibesec`, `shopify-autolab` (workspace-level), `using-superpowers`, `verification-before-completion`, `find-skills`, parent `playwright-testing` and its `core`, `ci`, `migration`, `pom` sub-indexes.
  - `brainstorming` Step 6 + the line-115 follow-up edited to **stop auto-committing the design doc**. The skill now writes the doc, reports the path, and asks the user before any commit. Keeps the skill auto-invocable while removing its only high-risk side effect.
- Deterministic-vs-judgment split. The 10 SKILL.md bodies that previously dictated specific shell pipelines now call the new scripts above and reserve prose for the steps that actually need judgment: `branch-hygiene`, `codebase-audit`, `project-onboarding`, `writing-skills`, `writing-plans`, `subagent-driven-development`, `file-organizer`, `compact-memory`, `using-git-worktrees`, `requesting-code-review`.
- Composability cleanup (no behavior change, just less drift surface):
  - `oiloil-ui-ux-guide` (workspace) collapsed to a small redirect pointing at the canonical `ui-ux-guide` in this plugin.
  - `playwright-testing/core/SKILL.md` collapsed to a stub redirect to the parent index (`disable-model-invocation: true`, `user-invocable: false`); reference markdown files in `core/` unchanged.
  - `process-interviewer` Phase 5 now hands off to `writing-skills` instead of restating skill structure.
  - `vibesec` and `owasp-security` both gained an explicit "companion skill, do not duplicate text" header so they stop drifting toward each other.
  - `finishing-a-development-branch` Step 1 and `receiving-code-review` overview now defer to `verification-before-completion` for the "actually run the test command and check the output" loop.
- `plugin.json` version bumped 1.14.0 → 1.15.0 (plus the two hardcoded mirrors in `scripts/build.ps1` and `tests/build/fixtures/`).

## [1.14.0] - 2026-05-16

Two new workflow skills targeting the highest-frequency repeated prompts surfaced from 30 days of session history: project onboarding and cross-repo branch hygiene.

### Added
- `project-onboarding` skill. Fires when the user opens a session with "familiarize yourself with X", "you'll be working out of the X project", or similar. Reads the workspace project map, per-project CLAUDE.md / AGENTS.md / Context Matrix, manifest file, settings module, and recent git state, then surfaces only the project-specific rules that actually apply (Render API gotchas for Render projects, dropship `tracked=false` for autolab, Linear-not-GitHub for TheCTIAgent, PS 5.1-vs-7 for pitt-skills, etc.).
- `branch-hygiene` skill. Cross-branch sweep: categorizes every local branch (Protected / Gone / Merged / OpenPR / StaleUnmerged / Active), presents a plan, deletes safe-to-delete after per-category approval, fast-forwards long-lived branches from upstream, cleans orphaned worktrees, and surfaces stale PRs with mergeability state. Complements `commit-commands:clean_gone` (which is scoped to `[gone]` refs only) and `finishing-a-development-branch` (which handles a single branch's end-of-life).

### Changed
- `plugin.json` version bumped 1.13.0 → 1.14.0 (plus the two hardcoded mirrors in `scripts/build.ps1` and `tests/build/fixtures/`).

## [1.8.1] - 2026-05-04

`compact-memory` setup scripts now handle the default Claude Code `MEMORY.md` format.

### Fixed
- `compact-memory/scripts/setup.ps1` and `setup.sh` previously skipped any `MEMORY.md` lacking a `# Memory Index` heading, then logged the result as `skipped (already-present or no heading)` — making it impossible to tell whether the index entry got installed. Default Claude Code auto-memory `MEMORY.md` files are flat bullet lists with no heading, so on a vanilla install step 3 was a silent no-op.
- New behavior: insert under the heading when present, otherwise prepend the bullet at the top of the file. Log differentiates the three outcomes (`under heading`, `at top`, `already-present`).
- `compact-memory/SKILL.md` "Edit 3" updated to drop the heading-required wording.

### Changed
- `plugin.json` version bumped 1.8.0 → 1.8.1.

## [Unreleased] — v1.3.0

Retire `threatconnect-polarity` ahead of a more robust replacement skill.

### Removed
- `threatconnect-polarity` skill removed from the plugin. A replacement is being authored separately and will land in a future release. The `threatconnect-polarity.instructions.md` Copilot mirror is removed by `build.ps1` regeneration.

### Changed
- `plugin.json` version bumped 1.2.0 → 1.3.0.

## [1.2.0] - 2026-04-30

`cortex-xsiam` and `tines` vendored skills both gain comprehensive content merged from author standalone copies. New build-verify pre-commit hook keeps Copilot mirrors in sync. PowerShell 5.1 compatibility for the installer wrappers.

### Added
- `cortex-xsiam` skill expanded with 7 new references (`attack-surface-mgmt`, `case-customization`, `endpoint-protection`, `engines`, `identity-threat`, `tenant-administration`, `xql-reference`) merged from author's standalone copy. SKILL.md gains an Alert/Issue/Case/Incident terminology block disambiguating the four entities including the int-IDs-for-reads vs string-IDs-for-writes API gotcha. Reference table grew from 8 to 14 rows.
- `tines` skill expanded with 3 new references (`best-practices`, `formulas`, `gotchas`) and substantial enhancements to 8 existing references. SKILL.md description expanded with new triggers (AI Agent action, formulas, pills syntax, Terraform provider, AI credit pool, MCP server templates, debug context). Reference table grew from 8 to 11 rows.
- `.githooks/pre-commit` build-verify hook. Aborts the commit if `scripts/build.ps1` output drifts from staged content; opt in per-clone with `git config core.hooksPath .githooks`.

### Changed
- `plugin.json` version bumped 1.1.0 → 1.2.0.
- `scripts/install.ps1`, `scripts/vendor-skill.ps1`, `scripts/sync-superpowers.ps1` made compatible with Windows PowerShell 5.1: em-dashes in BOM-less script files scrubbed (Windows-1252 mojibake had been silently eating function definitions), `ConvertFrom-Json -AsHashtable` shim added for PS 5.1, `$IsWindows` guard widened so the `mklink /J` junction fallback fires when symlink creation needs admin / Developer Mode.

## [1.1.0] - 2026-04-29

Vendor `obra/superpowers` — `brainstorming`, `systematic-debugging`, `subagent-driven-development`, and 11 other dev workflow skills available across all three install audiences.

### Added
- 14 skills vendored from `obra/superpowers@6efe32c9` (MIT, Jesse Vincent): `brainstorming`, `dispatching-parallel-agents`, `executing-plans`, `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `using-superpowers`, `verification-before-completion`, `writing-plans`, `writing-skills`.
- `scripts/sync-superpowers.ps1` — wrapper around `vendor-skill.ps1` that re-vendors all 14 skills against a pinned upstream commit SHA.
- `superpowers@superpowers-dev` auto-enabled in `settings.snippet.json` so Claude Code users get the live upstream plugin alongside the vendored snapshot.

### Changed
- `plugin.json` version bumped 1.0.0 → 1.1.0 (additive content).

## [1.0.0] - 2026-04-29

Milestone 4: CI, authoring guide, real `--Uninstall`, prompt-driven install instructions.

### Added
- GitHub Actions CI: build cleanliness check, Pester + bats test runs, and SKILL.md-bump-without-plugin.json-version-bump enforcement on PRs.
- `vendor-skill.ps1` helper for forking upstream skills with provenance (`UPSTREAM.md`).
- Authoring guide at `docs/authoring-a-skill.md` covering both author-original and vendored skills.
- Prompt-driven install instructions per audience (Claude Code / Copilot CLI / VS Code Chat / Copilot Desktop) in the README.
- Real `--Uninstall` flag on both `install.ps1` and `install.sh`, with Pester + bats coverage.

### Changed
- Uninstall preserves user key order in `settings.json` rather than reordering on rewrite.

### Removed
- M2 migration checklist (work complete).

## [0.3.0] - 2026-04-29

Milestones 2 + 3: all eight skills ported, build pipeline for Copilot artifacts, three-way installer.

### Added
- Ported seven additional skills: `cortex-xsiam`, `tines`, `tufin` (author-original); `owasp-security`, `playwright-testing`, `ui-ux-guide`, `vibesec` (vendored unmodified from upstream with `UPSTREAM.md` provenance).
- Vendored playwright-testing reference tree (60+ guide files) so in-skill links resolve.
- `build.ps1` + `build.sh` to generate Copilot CLI prompts and Copilot Chat instructions from each `SKILL.md`.
- `install.ps1` and `install.sh` with tool detection, symlinks for Copilot CLI + Chat targets, refusal to overwrite real directories, and shadowing-skill detection that merges into `settings.json`.
- Golden-file Pester fixtures for `build.ps1`; pwsh 7+ pin and idempotency guards.
- Catalog entry deferring `webapp-testing` to the upstream `anthropics/skills` marketplace.

### Changed
- `install.ps1` hardened against malformed JSON, type mismatches, and partial `Move-Item` failures; preserves array type from `Get-ShadowingSkills`.
- Vendored skill frontmatter `name` aligned with directory (M1 spec).
- `ui-ux-guide` and `vibesec` upstream licenses corrected to Apache-2.0.

## [0.1.0] - 2026-04-28

Milestone 1: walking skeleton.

### Added
- Single skill (`threatconnect-polarity`) installable as a Claude Code marketplace plugin from GitHub.
- Marketplace catalog and plugin manifest.
- Repo scaffolding, initial design doc, and implementation plan.
