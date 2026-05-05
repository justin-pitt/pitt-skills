#requires -Version 7.0
<#
.SYNOPSIS
Automated setup for the compact-memory skill.

.DESCRIPTION
1. Copies the hook to ~/.claude/hooks/pre-compact.sh
2. Merges the PreCompact entry into ~/.claude/settings.json
3. Adds the _session-snapshot.md index entry to existing ~/.claude/projects/*/memory/MEMORY.md files

Honors $env:CLAUDE_HOME if set, else uses ~/.claude. Idempotent.
#>

$ErrorActionPreference = 'Stop'

$skillDir   = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$hookSrc    = Join-Path $skillDir 'scripts/pre-compact.sh'
$claudeHome = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOME '.claude' }
$hookDst    = Join-Path $claudeHome 'hooks/pre-compact.sh'
$settings   = Join-Path $claudeHome 'settings.json'
$hookCmd    = '~/.claude/hooks/pre-compact.sh'
$indexLine  = '- [_session-snapshot.md](_session-snapshot.md) — Pre-compaction snapshot, check mtime for recency'

# --- 1. Install hook ---
if (-not (Test-Path $hookSrc)) {
    Write-Error "Hook source not found at $hookSrc"
    exit 1
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $hookDst) | Out-Null
Copy-Item -Path $hookSrc -Destination $hookDst -Force
Write-Host "[1/3] installed hook -> $hookDst"

# --- 2. Merge settings.json ---
if (Test-Path $settings) {
    Copy-Item $settings "$settings.bak" -Force
    $json = Get-Content $settings -Raw | ConvertFrom-Json
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $settings) | Out-Null
    $json = [PSCustomObject]@{}
}

if (-not $json.PSObject.Properties['hooks']) {
    $json | Add-Member -MemberType NoteProperty -Name hooks -Value ([PSCustomObject]@{})
}
if (-not $json.hooks.PSObject.Properties['PreCompact']) {
    $json.hooks | Add-Member -MemberType NoteProperty -Name PreCompact -Value @()
}

$alreadyHas = $false
foreach ($matcher in @($json.hooks.PreCompact)) {
    foreach ($hook in @($matcher.hooks)) {
        if ($hook.command -eq $hookCmd) {
            $alreadyHas = $true
        }
    }
}

if (-not $alreadyHas) {
    $newMatcher = [PSCustomObject]@{
        hooks = @([PSCustomObject]@{
            type    = 'command'
            command = $hookCmd
        })
    }
    $json.hooks.PreCompact = @(@($json.hooks.PreCompact) + $newMatcher)
    $json | ConvertTo-Json -Depth 20 | Set-Content $settings -Encoding utf8
    Write-Host "[2/3] merged PreCompact into $settings (backup at $settings.bak)"
} else {
    Write-Host "[2/3] PreCompact already configured in $settings, no change"
}

# --- 3. Add MEMORY.md index entry ---
# Default Claude Code MEMORY.md is a flat bullet list with no heading. If a
# `# Memory Index` heading exists, insert under it; otherwise prepend at top.
$projectsDir = Join-Path $claudeHome 'projects'
$addedHeading = 0
$addedTop = 0
$skipped = 0
if (Test-Path $projectsDir) {
    foreach ($projectDir in (Get-ChildItem $projectsDir -Directory -ErrorAction SilentlyContinue)) {
        $memoryMd = Join-Path $projectDir.FullName 'memory/MEMORY.md'
        if (-not (Test-Path $memoryMd)) { continue }
        $content = Get-Content $memoryMd -Raw
        if ($content -match '_session-snapshot\.md') {
            $skipped++
            continue
        }
        $nl = if ($content -match "`r`n") { "`r`n" } else { "`n" }
        if ($content -match '(?m)^# Memory Index') {
            $new = [regex]::Replace($content, '(?m)^(# Memory Index *\r?\n+)', "`$1$indexLine$nl", 1)
            $addedHeading++
        } else {
            $new = $indexLine + $nl + $content
            $addedTop++
        }
        Set-Content -Path $memoryMd -Value $new -Encoding utf8 -NoNewline
    }
}
Write-Host "[3/3] MEMORY.md updates: $addedHeading under heading, $addedTop at top, $skipped already-present"

Write-Host "Done. Run /compact in a long session to verify."
