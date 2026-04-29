[CmdletBinding()]
param(
    [switch]$DotSource,
    [switch]$WhatIf,
    [switch]$Uninstall,
    [switch]$RemoveShadowing,
    [string[]]$Tools = @('claude')
)

function Get-ClaudeHome {
    if ($env:CLAUDE_HOME) { return $env:CLAUDE_HOME }
    return Join-Path $HOME ".claude"
}

function Merge-ClaudeSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SnippetPath
    )
    $claudeHome = Get-ClaudeHome
    if (-not (Test-Path $claudeHome)) { New-Item -ItemType Directory -Path $claudeHome -Force | Out-Null }
    $settingsPath = Join-Path $claudeHome 'settings.json'
    $snippet = Get-Content $SnippetPath -Raw | ConvertFrom-Json -AsHashtable

    if (Test-Path $settingsPath) {
        Copy-Item $settingsPath "$settingsPath.bak" -Force
        $existing = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable
    } else {
        $existing = @{}
    }

    foreach ($key in $snippet.Keys) {
        if ($existing.ContainsKey($key) -and $existing[$key] -is [hashtable] -and $snippet[$key] -is [hashtable]) {
            foreach ($subkey in $snippet[$key].Keys) {
                $existing[$key][$subkey] = $snippet[$key][$subkey]
            }
        } else {
            $existing[$key] = $snippet[$key]
        }
    }

    $existing | ConvertTo-Json -Depth 32 | Set-Content $settingsPath
}

function Get-ShadowingSkills {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot
    )
    $standaloneDir = Join-Path (Get-ClaudeHome) 'skills'
    if (-not (Test-Path $standaloneDir)) { return ,@() }

    $pluginSkillsDir = Join-Path $RepoRoot 'plugins/pitt-skills/skills'
    if (-not (Test-Path $pluginSkillsDir)) { return ,@() }

    $pluginNames = Get-ChildItem $pluginSkillsDir -Directory | Select-Object -ExpandProperty Name
    $standaloneNames = Get-ChildItem $standaloneDir -Directory | Select-Object -ExpandProperty Name

    $result = @($standaloneNames | Where-Object { $pluginNames -contains $_ })
    return ,$result
}

function Remove-ShadowingSkills {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot
    )
    $shadowing = Get-ShadowingSkills -RepoRoot $RepoRoot
    if (-not $shadowing) { return }

    $standaloneDir = Join-Path (Get-ClaudeHome) 'skills'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path $standaloneDir ".shadow-backup-$stamp"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    foreach ($name in $shadowing) {
        $src = Join-Path $standaloneDir $name
        $dst = Join-Path $backupDir $name
        Move-Item $src $dst
        Write-Host "  moved $src -> $dst"
    }
}

if (-not $DotSource) {
    $repoRoot = Split-Path $PSScriptRoot -Parent

    # Detect shadowing before merging settings — surface the conflict early
    $shadowing = Get-ShadowingSkills -RepoRoot $repoRoot
    if ($shadowing) {
        Write-Warning "Found $($shadowing.Count) standalone skill(s) under ~/.claude/skills/ that will SHADOW the pitt-skills plugin version:"
        $shadowing | ForEach-Object { Write-Warning "  - $_" }
        if ($RemoveShadowing) {
            Write-Host "Backing up and removing shadowing copies (per -RemoveShadowing)..."
            Remove-ShadowingSkills -RepoRoot $repoRoot
        } else {
            Write-Warning "Re-run with -RemoveShadowing to back them up to ~/.claude/skills/.shadow-backup-<timestamp>/ and remove the originals. Until then, the plugin version of each listed skill will not load."
        }
    }

    Merge-ClaudeSettings -SnippetPath (Join-Path $repoRoot 'settings.snippet.json')
    Write-Host "Claude settings merged. Restart Claude Code to register pitt-skills marketplace."
}
