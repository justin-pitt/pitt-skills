# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — v1.1.0

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
