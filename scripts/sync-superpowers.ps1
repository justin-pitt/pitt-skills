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
if ($LASTEXITCODE -ne 0) { throw "git clone failed (exit $LASTEXITCODE) - check network/DNS" }

Push-Location $tmp
try {
    git -c advice.detachedHead=false checkout --quiet $CommitSha
    if ($LASTEXITCODE -ne 0) { throw "git checkout ${CommitSha} failed (exit $LASTEXITCODE) - bad SHA?" }
} finally {
    Pop-Location
}

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
    throw "Missing in upstream at ${CommitSha}: $($missing -join ', '). Edit `$skills in this script or pin a different SHA."
}

Write-Host ""
Write-Host "Done. Next steps (manual, per design doc):"
Write-Host "  1. Add 'license: MIT' to each plugins/pitt-skills/skills/<name>/SKILL.md frontmatter."
Write-Host "  2. Hand-enrich each plugins/pitt-skills/skills/<name>/UPSTREAM.md to the richer M2 format."
Write-Host "  3. Bump plugin.json/build.ps1/fixtures to the new version (Task 5 of the plan)."
Write-Host "  4. Regenerate Copilot artifacts via ./scripts/build.ps1 (Task 6)."
