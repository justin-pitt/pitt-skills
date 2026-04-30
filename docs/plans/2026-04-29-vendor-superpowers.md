# Vendor superpowers Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bake all 14 [obra/superpowers](https://github.com/obra/superpowers) skills into pitt-skills so the universal install prompt gives every coworker (Claude Code + Copilot) immediate access — `brainstorming`, `systematic-debugging`, `subagent-driven-development`, and 11 others — with no follow-up install instruction.

**Architecture:** Hybrid. Claude Code users auto-enable the upstream `superpowers@superpowers-dev` plugin via `settings.snippet.json` (live upstream, fresh per release). Copilot CLI / VS Code Chat users get vendored SKILL.md snapshots in `plugins/pitt-skills/skills/<name>/` that `build.ps1` converts to `.github/instructions/*.instructions.md`. Drift between the two channels is acceptable because both serve from the same MIT-licensed upstream and the snapshot is one command to refresh.

**Tech Stack:** PowerShell 7+ (vendor + sync scripts), Pester (tests), GitHub Actions (CI), pwsh `Set-Content`/`Get-Content`/`ConvertFrom-Json`. No new dependencies.

**Reference design:** `docs/plans/2026-04-29-vendor-superpowers-design.md` (commit `db89d8b`).

**Upstream pin for initial vendor:** `obra/superpowers` commit `6efe32c9e2dd002d0c394e861e0529675d1ab32e` (2026-04-23). Tasks 2–4 use this SHA.

**Skill inventory (14):**

```
brainstorming                       receiving-code-review
dispatching-parallel-agents         requesting-code-review
executing-plans                     subagent-driven-development
finishing-a-development-branch      systematic-debugging
test-driven-development             using-git-worktrees
using-superpowers                   verification-before-completion
writing-plans                       writing-skills
```

**Branch:** `feat/vendor-superpowers` (off main; design doc already committed there as `db89d8b`).

**Out of scope:** vendoring superpowers' agents/commands/hooks/scripts/tests, renaming skill `name:` fields, building a generic "vendor entire marketplace" tool. See design doc.

---

### Lessons from M2 + M4 that apply here

- pwsh 7+ path on Justin's box: `$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe` — bare `pwsh` is 5.1 and Pester won't run.
- `$home` is read-only in PowerShell. Use `$userHome`.
- `[ordered]@{}` for any hashtable that gets `ConvertTo-Json`'d — plain `@{}` order is non-deterministic and breaks idempotency tests.
- bats is NOT installed locally; CI runs the bats job. Don't try to install bats locally.
- Justin's commit style: terse lowercase prefix (`feat:` / `fix:` / `docs:` / `test:` / `chore:` / `ci:`).
- NEVER include "Claude" / "Co-Authored-By: Claude..." / "Generated with [Claude Code]" / robot emoji in any commit, PR title, or PR body.
- The CI version-bump rule (added in M4) fires when any `plugins/pitt-skills/skills/*/SKILL.md` changes; bumping `plugin.json` to 1.1.0 in this PR satisfies it.
- When `vendor-skill.ps1`'s default `UPSTREAM.md` is too thin, hand-enrich it to match the M2 PR #4 format (Repo, Path within repo, Commit SHA at vendoring, Original license, Vendored on, "My changes" section listing the `license: MIT` addition).

---

## Task 1: Helper script — `scripts/sync-superpowers.ps1`

**Files:**
- Create: `scripts/sync-superpowers.ps1`

**Why first:** the helper is what Tasks 2–4 use to vendor 14 skills in one shot. Writing it before vendoring means we exercise the script as the actual vendoring path, not retrofit it later.

**Step 1: Create the script**

```powershell
#requires -Version 7.0
<#
Sync (re-vendor) all skills from obra/superpowers into plugins/pitt-skills/skills/
at a pinned upstream commit SHA. Wraps scripts/vendor-skill.ps1 in a loop.

After running, the human still needs to:
  (a) add `license: MIT` to each vendored SKILL.md frontmatter (Copilot CLI requires it)
  (b) hand-enrich each UPSTREAM.md to the richer M2 PR #4 format

Usage:
  pwsh ./scripts/sync-superpowers.ps1 -CommitSha 6efe32c9e2dd002d0c394e861e0529675d1ab32e
  pwsh ./scripts/sync-superpowers.ps1 -CommitSha <new-sha> -Force   # to overwrite an existing vendor
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $CommitSha,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

$skills = @(
    'brainstorming','dispatching-parallel-agents','executing-plans',
    'finishing-a-development-branch','receiving-code-review','requesting-code-review',
    'subagent-driven-development','systematic-debugging','test-driven-development',
    'using-git-worktrees','using-superpowers','verification-before-completion',
    'writing-plans','writing-skills'
)

$repoRoot = Split-Path $PSScriptRoot -Parent
$tempBase = [System.IO.Path]::GetTempPath()
$tmp = Join-Path $tempBase "superpowers-$CommitSha"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }

Write-Host "Cloning obra/superpowers..."
git clone --quiet https://github.com/obra/superpowers $tmp
Push-Location $tmp
git -c advice.detachedHead=false checkout --quiet $CommitSha
Pop-Location

$missing = @()
foreach ($name in $skills) {
    $src = Join-Path $tmp "skills/$name"
    if (-not (Test-Path (Join-Path $src 'SKILL.md'))) {
        $missing += $name
        continue
    }
    Write-Host "Vendoring $name..."
    & (Join-Path $PSScriptRoot 'vendor-skill.ps1') `
        -Source $src `
        -SkillName $name `
        -UpstreamRepo 'obra/superpowers' `
        -UpstreamSha $CommitSha `
        -License 'MIT' `
        -Force:$Force `
        -RepoRoot $repoRoot
}

if ($missing) {
    Write-Warning "Missing in upstream at $CommitSha: $($missing -join ', ')"
}

Write-Host ""
Write-Host "Done. Next steps (manual, per design doc):"
Write-Host "  1. Add 'license: MIT' to each plugins/pitt-skills/skills/<name>/SKILL.md frontmatter."
Write-Host "  2. Hand-enrich each plugins/pitt-skills/skills/<name>/UPSTREAM.md to the richer M2 format."
Write-Host "  3. Bump plugin.json/build.ps1/fixtures to the new version (Task 5 of the plan)."
Write-Host "  4. Regenerate Copilot artifacts via ./scripts/build.ps1 (Task 6)."
```

**Step 2: Smoke-test the script signature**

Run: `& "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe" -NoProfile -Command "./scripts/sync-superpowers.ps1 -CommitSha foo" 2>&1 | Select-Object -First 5`

Expected: it should attempt to clone (network access required). If you don't have network or want to skip, the syntactical validity is enough — `pwsh -Command "Get-Command ./scripts/sync-superpowers.ps1 -Syntax"` should print the param signature without error.

(Don't actually run the full sync yet — Task 2 does that.)

**Step 3: Commit**

```bash
git add scripts/sync-superpowers.ps1
git commit -m "feat: sync-superpowers.ps1 wrapper for re-vendoring at a pinned SHA"
```

---

## Task 2: Run the sync against `6efe32c9e2dd002d0c394e861e0529675d1ab32e`

**Files:**
- Create (via the script): `plugins/pitt-skills/skills/<name>/SKILL.md` and `plugins/pitt-skills/skills/<name>/UPSTREAM.md` for each of the 14 skills

**Step 1: Run the sync**

```bash
& "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe" -NoProfile -Command "./scripts/sync-superpowers.ps1 -CommitSha 6efe32c9e2dd002d0c394e861e0529675d1ab32e"
```

Expected output:

```
Cloning obra/superpowers...
Vendoring brainstorming...
✓ Vendored brainstorming from obra/superpowers@6efe32c9...
Vendoring dispatching-parallel-agents...
✓ Vendored dispatching-parallel-agents from obra/superpowers@6efe32c9...
... (12 more)
Done. Next steps (manual, per design doc):
  1. Add 'license: MIT' to each plugins/pitt-skills/skills/<name>/SKILL.md frontmatter.
  2. ...
```

If the script reports `Missing in upstream at ...:`, stop — the SHA may have moved, or a skill was renamed upstream. Investigate before proceeding.

**Step 2: Verify all 14 dirs exist with both files**

```bash
ls plugins/pitt-skills/skills/ | grep -E '^(brainstorming|dispatching-parallel-agents|executing-plans|finishing-a-development-branch|receiving-code-review|requesting-code-review|subagent-driven-development|systematic-debugging|test-driven-development|using-git-worktrees|using-superpowers|verification-before-completion|writing-plans|writing-skills)$' | wc -l
```

Expected: `14`.

```bash
find plugins/pitt-skills/skills -maxdepth 2 -name SKILL.md | wc -l
```

Expected: `34` (8 from M2/M3 + 12 from PR #4 + 14 just vendored = 34).

**Step 3: Commit (snapshot before frontmatter edits)**

```bash
git add plugins/pitt-skills/skills/brainstorming \
        plugins/pitt-skills/skills/dispatching-parallel-agents \
        plugins/pitt-skills/skills/executing-plans \
        plugins/pitt-skills/skills/finishing-a-development-branch \
        plugins/pitt-skills/skills/receiving-code-review \
        plugins/pitt-skills/skills/requesting-code-review \
        plugins/pitt-skills/skills/subagent-driven-development \
        plugins/pitt-skills/skills/systematic-debugging \
        plugins/pitt-skills/skills/test-driven-development \
        plugins/pitt-skills/skills/using-git-worktrees \
        plugins/pitt-skills/skills/using-superpowers \
        plugins/pitt-skills/skills/verification-before-completion \
        plugins/pitt-skills/skills/writing-plans \
        plugins/pitt-skills/skills/writing-skills
git commit -m "feat: vendor 14 skills from obra/superpowers@6efe32c9"
```

---

## Task 3: Add `license: MIT` to each vendored SKILL.md

**Why:** the Copilot CLI marketplace validator requires `license:` in frontmatter. Upstream omits it; we add it on vendor (per M2 PR #4 convention — see e.g. `plugins/pitt-skills/skills/agent-browser/UPSTREAM.md` "My changes" section).

**Files (modify):** all 14 of `plugins/pitt-skills/skills/<name>/SKILL.md`

**Step 1: Verify frontmatter shape on a sample**

```bash
head -10 plugins/pitt-skills/skills/brainstorming/SKILL.md
```

Expected: a YAML frontmatter block delimited by `---` lines containing `name:` and `description:`. `license:` is absent.

**Step 2: Add `license: MIT` to each (one PowerShell loop)**

```powershell
$skills = 'brainstorming','dispatching-parallel-agents','executing-plans','finishing-a-development-branch','receiving-code-review','requesting-code-review','subagent-driven-development','systematic-debugging','test-driven-development','using-git-worktrees','using-superpowers','verification-before-completion','writing-plans','writing-skills'

foreach ($name in $skills) {
    $path = "plugins/pitt-skills/skills/$name/SKILL.md"
    $content = Get-Content $path -Raw
    if ($content -match '^---\r?\nlicense:') {
        Write-Host "$name: license already present, skipping"
        continue
    }
    # Insert `license: MIT` after the `description:` line (handles both `description: foo` and folded `description: >`)
    $updated = $content -replace '(?m)^(description:.*(?:\r?\n[ \t]+\S.*)*)\r?\n', "`$1`nlicense: MIT`n"
    if ($updated -eq $content) {
        Write-Warning "$name: failed to inject license — frontmatter shape unexpected"
        continue
    }
    Set-Content $path $updated -NoNewline
    # Set-Content -NoNewline avoids appending an extra blank line; the `\n` we inserted is enough.
    Write-Host "$name: license: MIT added"
}
```

Run via `& "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe" -NoProfile -Command "..."` or paste into a pwsh 7 session.

**Step 3: Verify**

```bash
grep -L "^license:" plugins/pitt-skills/skills/*/SKILL.md | grep -E "(brainstorming|dispatching-parallel-agents|executing-plans|finishing-a-development-branch|receiving-code-review|requesting-code-review|subagent-driven-development|systematic-debugging|test-driven-development|using-git-worktrees|using-superpowers|verification-before-completion|writing-plans|writing-skills)/SKILL.md"
```

Expected: empty output (all 14 now have `license:` in their frontmatter).

```bash
head -10 plugins/pitt-skills/skills/brainstorming/SKILL.md
```

Expected: shows the frontmatter now containing `license: MIT` between `description:` and the closing `---`.

**Step 4: Commit**

```bash
git add plugins/pitt-skills/skills/*/SKILL.md
git commit -m "fix: add license: MIT frontmatter to vendored superpowers skills"
```

---

## Task 4: Hand-enrich each UPSTREAM.md to match the M2 PR #4 format

**Why:** `vendor-skill.ps1`'s default `UPSTREAM.md` is shorter than the format used in PR #4 (which has Path-within-repo, multi-bullet "My changes", etc.). Matching the existing convention keeps the directory consistent.

**Files (modify):** all 14 of `plugins/pitt-skills/skills/<name>/UPSTREAM.md`

**Reference format:** look at `plugins/pitt-skills/skills/agent-browser/UPSTREAM.md` for the target structure.

**Step 1: Replace each UPSTREAM.md with the enriched form**

For each of the 14 skills, replace `plugins/pitt-skills/skills/<name>/UPSTREAM.md` with:

```markdown
# Upstream source

- **Repo:** https://github.com/obra/superpowers
- **Path within repo:** `skills/<name>/`
- **Commit SHA at vendoring:** 6efe32c9e2dd002d0c394e861e0529675d1ab32e
- **Original license:** MIT (Copyright 2025 Jesse Vincent — see https://github.com/obra/superpowers/blob/main/LICENSE)
- **Vendored on:** 2026-04-29

## My changes

- Added `license: MIT` to the frontmatter so the Copilot CLI marketplace validator accepts it. Upstream omits the field but the parent repo's `LICENSE` is MIT. The skill body and all other frontmatter fields are preserved verbatim.
- The bundle vendored from `skills/<name>/` is byte-identical to upstream at the SHA above (apart from the frontmatter `license:` insertion noted above).
```

A scripted approach to write all 14 at once:

```powershell
$skills = 'brainstorming','dispatching-parallel-agents','executing-plans','finishing-a-development-branch','receiving-code-review','requesting-code-review','subagent-driven-development','systematic-debugging','test-driven-development','using-git-worktrees','using-superpowers','verification-before-completion','writing-plans','writing-skills'

foreach ($name in $skills) {
    $body = @"
# Upstream source

- **Repo:** https://github.com/obra/superpowers
- **Path within repo:** ``skills/$name/``
- **Commit SHA at vendoring:** 6efe32c9e2dd002d0c394e861e0529675d1ab32e
- **Original license:** MIT (Copyright 2025 Jesse Vincent — see https://github.com/obra/superpowers/blob/main/LICENSE)
- **Vendored on:** 2026-04-29

## My changes

- Added ``license: MIT`` to the frontmatter so the Copilot CLI marketplace validator accepts it. Upstream omits the field but the parent repo's ``LICENSE`` is MIT. The skill body and all other frontmatter fields are preserved verbatim.
- The bundle vendored from ``skills/$name/`` is byte-identical to upstream at the SHA above (apart from the frontmatter ``license:`` insertion noted above).
"@
    Set-Content "plugins/pitt-skills/skills/$name/UPSTREAM.md" $body
    Write-Host "$name: UPSTREAM.md written"
}
```

(In PowerShell `@"..."@` is a here-string with variable expansion; `$name` interpolates and `` ` `` escapes literal backticks for the markdown code spans.)

**Step 2: Spot-check three**

```bash
cat plugins/pitt-skills/skills/brainstorming/UPSTREAM.md
cat plugins/pitt-skills/skills/systematic-debugging/UPSTREAM.md
cat plugins/pitt-skills/skills/subagent-driven-development/UPSTREAM.md
```

Expected: same structure as `plugins/pitt-skills/skills/agent-browser/UPSTREAM.md` — five header bullets and a "My changes" section. Each path-within-repo bullet correctly names the skill.

**Step 3: Commit**

```bash
git add plugins/pitt-skills/skills/*/UPSTREAM.md
git commit -m "docs: enrich UPSTREAM.md for vendored superpowers skills"
```

---

## Task 5: Bump version to 1.1.0 across the three pinned places

**Files:**
- Modify: `scripts/build.ps1` (the hardcoded `version = '1.0.0'`)
- Modify: `tests/build/fixtures/write-fixtures.ps1` (same hardcoded constant)
- Modify: `tests/build/fixtures/expected/plugins/pitt-skills/.claude-plugin/plugin.json` (the JSON fixture)

**Why:** the version field is hardcoded in three places. M4's CLAUDE.md spells this out — keep them in sync.

**Step 1: Edit `scripts/build.ps1`**

Replace `version = '1.0.0'` with `version = '1.1.0'` (one occurrence near the `$pluginManifest = [ordered]@{` block).

**Step 2: Edit `tests/build/fixtures/write-fixtures.ps1`**

Same replacement — `version = '1.0.0'` → `version = '1.1.0'`.

**Step 3: Edit the expected fixture**

`tests/build/fixtures/expected/plugins/pitt-skills/.claude-plugin/plugin.json` line 4: `"version": "1.0.0"` → `"version": "1.1.0"`.

**Step 4: Verify all three changed**

```bash
grep -n "1\.[01]\.0" scripts/build.ps1 tests/build/fixtures/write-fixtures.ps1 tests/build/fixtures/expected/plugins/pitt-skills/.claude-plugin/plugin.json
```

Expected: every match shows `1.1.0`, none show `1.0.0`.

**Step 5: Commit**

```bash
git add scripts/build.ps1 tests/build/fixtures/write-fixtures.ps1 tests/build/fixtures/expected/plugins/pitt-skills/.claude-plugin/plugin.json
git commit -m "chore: bump plugin.json to 1.1.0"
```

---

## Task 6: Regenerate Copilot artifacts via `build.ps1`

**Why:** with 14 new SKILL.md files plus a version bump, `build.ps1` produces 14 new `.github/instructions/<name>.instructions.md` files and updates the regenerated `plugins/pitt-skills/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.

**Step 1: Run the build**

```bash
& "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe" -NoProfile -Command "./scripts/build.ps1"
```

Expected output: `Build complete: 34 skills processed.`

**Step 2: Verify the right artifacts changed**

```bash
git status --short
```

Expected: 14 new `.github/instructions/<superpowers-name>.instructions.md`, modified `plugins/pitt-skills/.claude-plugin/plugin.json`, modified `.claude-plugin/marketplace.json`. Possibly modified `.github/copilot-instructions.md` (preamble) — that's fine.

```bash
ls .github/instructions/ | wc -l
```

Expected: `34` (8 M2/M3 + 12 PR #4 + 14 superpowers).

```bash
grep '"version"' plugins/pitt-skills/.claude-plugin/plugin.json
```

Expected: `"version": "1.1.0",`.

**Step 3: Commit**

```bash
git add .github/instructions/ .github/copilot-instructions.md plugins/pitt-skills/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "feat: regenerate Copilot artifacts for vendored superpowers skills"
```

---

## Task 7: Enable `superpowers@superpowers-dev` in `settings.snippet.json`

**Files:**
- Modify: `settings.snippet.json`

**Why:** the universal install prompt runs `install.ps1`, which merges this snippet into `~/.claude/settings.json`. Adding the enabled-plugin entry means a Claude Code user gets superpowers active right after install with no extra step. The marketplace itself is already registered (added in M2).

**Step 1: Edit the file**

Read `settings.snippet.json`. Locate the `enabledPlugins` block, which currently looks like:

```json
"enabledPlugins": {
  "pitt-skills@pitt-skills": true
}
```

Add the new key (preserving JSON validity):

```json
"enabledPlugins": {
  "pitt-skills@pitt-skills": true,
  "superpowers@superpowers-dev": true
}
```

**Step 2: Verify JSON parses**

```bash
& "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe" -NoProfile -Command "(Get-Content settings.snippet.json -Raw | ConvertFrom-Json).enabledPlugins"
```

Expected: prints both keys, both `True`.

**Step 3: Commit**

```bash
git add settings.snippet.json
git commit -m "feat: auto-enable superpowers@superpowers-dev for Claude Code installs"
```

---

## Task 8: Run the Pester suite, verify green

**Why:** version bump should not break any tests; regenerated artifacts already match the (bumped) fixtures; settings.snippet.json change is not yet test-covered but the existing Merge-ClaudeSettings tests should still pass.

**Step 1: Run Pester**

```bash
& "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe" -NoProfile -Command "Invoke-Pester tests/ -Output Detailed -CI"
```

Expected: `Tests Passed: 32, Failed: 0` (current count from M4). New skills add no new tests in this PR.

**Step 2: If a test fails**

Most likely culprit: a Build.Tests.ps1 failure if Task 5 missed one of the version-pinned files. Re-grep for `1\.0\.0` across the three target files and re-edit. Re-run `build.ps1` and re-stage the regenerated outputs.

(No Step 3 — if green, move on; if red, fix in place.)

---

## Task 9: README credit + CHANGELOG entry

**Files:**
- Modify: `README.md` (one new bullet under "What's inside")
- Modify: `CHANGELOG.md` (new `[1.1.0]` section)

**Step 1: Update README.md**

Read `README.md`. Find the `## What's inside` section. Append one line:

```markdown
Includes 14 skills vendored from [obra/superpowers](https://github.com/obra/superpowers) by Jesse Vincent (MIT). Claude Code users also get the live upstream marketplace via the install script; Copilot users use the vendored snapshot.
```

**Step 2: Update CHANGELOG.md**

Add a new section above the existing `[Unreleased]` / `[1.0.0]` block (whichever is current):

```markdown
## [1.1.0] - 2026-04-29

Vendor obra/superpowers — `brainstorming`, `systematic-debugging`, `subagent-driven-development`, and 11 other dev workflow skills available across all three install audiences.

### Added
- 14 skills vendored from `obra/superpowers@6efe32c9` (MIT, Jesse Vincent): `brainstorming`, `dispatching-parallel-agents`, `executing-plans`, `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `using-superpowers`, `verification-before-completion`, `writing-plans`, `writing-skills`.
- `scripts/sync-superpowers.ps1` — wrapper around `vendor-skill.ps1` that re-vendors all 14 skills against a pinned upstream commit SHA.
- `superpowers@superpowers-dev` auto-enabled in `settings.snippet.json` so Claude Code users get the live upstream plugin alongside the vendored snapshot.

### Changed
- `plugin.json` version bumped 1.0.0 → 1.1.0 (additive content).
```

If the existing `[Unreleased]` section had M4 content that was already labeled `[1.0.0]` after merge, no edit needed there — just insert the new `[1.1.0]` above it.

**Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: README credit + CHANGELOG entry for v1.1.0"
```

---

## Task 10: Push, open PR, verify CI

**Step 1: Push the branch**

```bash
git push -u origin feat/vendor-superpowers
```

**Step 2: Open the PR**

```bash
gh pr create --base main --head feat/vendor-superpowers --title "v1.1.0: vendor 14 skills from obra/superpowers" --body "$(cat <<'EOF'
## Summary

Bakes 14 skills from [obra/superpowers](https://github.com/obra/superpowers) (Jesse Vincent, MIT) into pitt-skills so the universal install prompt gives every audience — Claude Code, Copilot CLI, VS Code Chat — immediate access to `brainstorming`, `systematic-debugging`, `subagent-driven-development`, and 11 others. No follow-up "now also install superpowers" instruction.

## Approach

- **Claude Code users:** `settings.snippet.json` now enables `superpowers@superpowers-dev` from the marketplace registered back in M2. Users get the live upstream plugin via Claude Code's plugin runtime — fresh per upstream release.
- **Copilot CLI / VS Code Chat users:** the 14 SKILL.md files are vendored at `obra/superpowers@6efe32c9` (2026-04-23). `build.ps1` generates `.github/instructions/*.instructions.md` for VS Code Chat; `install.sh`/`install.ps1` symlink `~/.copilot/skills` to the vendored copies for Copilot CLI.

The two channels can drift between superpowers releases. `scripts/sync-superpowers.ps1 -CommitSha <sha> -Force` refreshes the snapshot in one command.

## What landed

- 14 new `plugins/pitt-skills/skills/<name>/{SKILL.md,UPSTREAM.md}` directories (vendored, with `license: MIT` added to each frontmatter)
- `scripts/sync-superpowers.ps1` for future refreshes
- `settings.snippet.json` enables `superpowers@superpowers-dev`
- Version bumped 1.0.0 → 1.1.0 across `build.ps1`, fixture, and write-fixtures
- 14 regenerated `.github/instructions/*.instructions.md`, regenerated `plugin.json` + `marketplace.json`
- `README.md` credit; `CHANGELOG.md` `[1.1.0]` entry

## License attribution

`obra/superpowers` is MIT-licensed (Copyright 2025 Jesse Vincent). Each vendored skill records repo URL, commit SHA, license, and vendoring date in `UPSTREAM.md`. Same pattern as PR #4's vendoring.

## Verify

- [ ] CI green (build / pester / bats / version-bump — version-bump should be satisfied by the 1.1.0 plugin.json bump)
- [ ] `pwsh ./scripts/install.ps1` on Windows still merges settings cleanly with the new `superpowers@superpowers-dev` enable
- [ ] `pwsh ./scripts/install.ps1 -Uninstall` still cleans up correctly (only removes the `pitt-skills` keys per the deliberate scope from M4)
- [ ] After merge, tag v1.1.0 on the merge commit and `gh release create v1.1.0 --generate-notes`
EOF
)"
```

**Step 3: Watch CI**

Use `gh pr checks <number> --watch` or poll until all four jobs report `pass`. If `verify-build` fails with a missing/added file, revisit Task 6 and ensure all regenerated artifacts were committed.

If `version-bump` fails despite the 1.1.0 bump, the `plugin.json` change must not have been staged — re-check `git log -1 --stat` for the regeneration commit.

**Step 4: Stop**

Don't merge. Don't tag. Per Justin's pattern (per-memory `feedback_defer_release_tag_post_merge.md`), v1.1.0 gets tagged on the merge commit after Justin merges.

---

## Notes for the executor

- All 14 new skill names are kebab-case and don't collide with anything else in `plugins/pitt-skills/skills/` (verified against the M2/M3 set and the 12 from PR #4).
- The skill `name:` field stays as upstream wrote it. Don't rename to `superpowers-<name>` or `pitt-<name>` — that breaks cross-references when Claude Code resolves both pitt-skills and the live upstream plugin.
- `UPSTREAM.md` files are the only place we modify upstream content. Don't touch the SKILL.md bodies — leave cross-references like `superpowers:test-driven-development` as text.
- If Pester goes red on Build.Tests.ps1 specifically, the most likely cause is mismatched line endings between the regenerated `plugin.json`/`marketplace.json` and the expected fixture. Justin's `core.autocrlf=true` interaction with `Set-Content` produces stored bytes as LF — matches what build.ps1 outputs on Windows pwsh 7+. Don't second-guess the fixtures unless `git cat-file blob HEAD:<fixture-path>` shows different bytes than the build output.
- The `verify-build` CI job uses `git status --porcelain` (per M4), so an untracked `packages-microsoft-prod.deb` or `testResults.xml` in the runner's CWD won't survive. Both are already handled by the workflow / `.gitignore` from M4.
