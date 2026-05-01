# CLAUDE.md — pitt-skills

Project-specific guidance for Claude Code working in this repo. The workspace-level [`c:\Code\CLAUDE.md`](../CLAUDE.md) covers cross-project context.

## What this is

A Claude Code marketplace and Copilot Chat instructions distributor. Skills live under `plugins/pitt-skills/skills/`. `scripts/build.ps1` generates Copilot artifacts under `.github/instructions/`, `.github/prompts/`, and `.github/agents/` from each skill's `SKILL.md`. `scripts/install.ps1` and `scripts/install.sh` symlink those artifacts into `~/.copilot/`, mount the plugin's skills under `<HERMES_HOME>/skills/pitt-skills/` for Hermes (auto-discovers nested SKILL.md), merge a snippet into `~/.claude/settings.json`, and auto-detect which CLIs are on PATH (`claude`, `copilot`, `code`, `hermes`).

## Local environment quirks

- **`pwsh` on PATH is Windows PowerShell 5.1, not pwsh 7.** Use `$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe` when running Pester or any script that needs pwsh 7+. All Pester test files start with `#requires -Version 7.0`.
- **bats is not installed locally.** It runs only on the GitHub Actions Ubuntu job (`bats` step in `.github/workflows/build.yml`). Don't try to install it via WSL or apt locally — verify YAML/syntax and trust CI.

## Repo conventions

- **Refuse to overwrite or delete a real (non-symlink) directory** at any path that should hold one of our symlinks. The pattern lives in `New-DirectorySymlink` (install.ps1) and `Remove-DirectorySymlink` — uses `(Get-Item -Force $path).LinkType` and accepts both `SymbolicLink` and `Junction`. Mirror this safety in any new install/uninstall code.
- **`git status --porcelain`, not `git diff --exit-code`, for build-output drift checks.** `git diff --exit-code` ignores untracked files, so a brand-new generated artifact (e.g., when a contributor adds a SKILL.md but forgets to run `build.ps1`) silently passes. The CI's `verify-build` step uses `git status --porcelain` for this reason.
- **Bump `plugins/pitt-skills/.claude-plugin/plugin.json` version with each release** and keep it in sync with the v* git tag. The version is hardcoded in three places: `scripts/build.ps1`, `tests/build/fixtures/write-fixtures.ps1`, and `tests/build/fixtures/expected/plugins/pitt-skills/.claude-plugin/plugin.json`. Update all three together.
- **Defer `git tag vX.Y.Z` to post-merge.** Don't tag a release during the milestone PR — tag the merge commit so the tag matches what shipped. Same pattern as v0.3.0 was tagged on the M3 merge commit.

## CI

Four jobs in `.github/workflows/build.yml`:

- `verify-build` (Ubuntu) — runs `./scripts/build.sh`, fails on any drift via `git status --porcelain`
- `pester` (windows-latest) — runs the Pester suite
- `bats` (Ubuntu) — runs the bats suite
- `version-bump` (PR-only) — fails when a `SKILL.md` changes without bumping `plugins/pitt-skills/.claude-plugin/plugin.json`. Escape hatch: `[skip-bump]` in any commit message on the branch. The regex matches only `SKILL.md`, not `UPSTREAM.md`, so vendor-refresh PRs that only touch `UPSTREAM.md` don't trigger.
