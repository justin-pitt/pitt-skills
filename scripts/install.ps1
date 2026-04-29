[CmdletBinding()]
# -DotSource, -RemoveShadowing, and -Tools are wired up.
# In M3, -Tools defaults to all three integrations (claude, copilotCli, vscode); pass -Tools explicitly to limit.
# When -Tools is not passed, the script auto-detects which CLIs are installed (claude / copilot / code) and only wires those up.
# -WhatIf and -Uninstall are reserved for M4 and currently no-op.
param(
    [switch]$DotSource,
    [switch]$WhatIf,
    [switch]$Uninstall,
    [switch]$RemoveShadowing,
    [string[]]$Tools = @('claude', 'copilotCli', 'vscode')
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
        try {
            $existing = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable
        } catch {
            throw "Existing settings.json at $settingsPath is not valid JSON ($($_.Exception.Message)). Original backed up at $settingsPath.bak. Fix the JSON manually and re-run."
        }
    } else {
        $existing = @{}
    }

    foreach ($key in $snippet.Keys) {
        if ($existing.ContainsKey($key) -and $existing[$key] -is [hashtable] -and $snippet[$key] -is [hashtable]) {
            foreach ($subkey in $snippet[$key].Keys) {
                $existing[$key][$subkey] = $snippet[$key][$subkey]
            }
        } elseif ($existing.ContainsKey($key) -and $existing[$key].GetType() -ne $snippet[$key].GetType()) {
            Write-Warning "Settings key '$key' has incompatible types in existing ($($existing[$key].GetType().Name)) vs snippet ($($snippet[$key].GetType().Name)). Existing value will be overwritten — see $settingsPath.bak to restore."
            $existing[$key] = $snippet[$key]
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

    $failures = @()
    foreach ($name in $shadowing) {
        $src = Join-Path $standaloneDir $name
        $dst = Join-Path $backupDir $name
        try {
            Move-Item $src $dst -ErrorAction Stop
            Write-Host "  moved $src -> $dst"
        } catch {
            $failures += "$name`: $($_.Exception.Message)"
        }
    }
    if ($failures) {
        throw "Failed to back up $($failures.Count) shadowing skill(s):`n  $($failures -join "`n  ")"
    }
}

function New-DirectorySymlink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Link,
        [Parameter(Mandatory)] [string] $Target
    )
    $parent = Split-Path $Link -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if (Test-Path $Link) { Remove-Item $Link -Recurse -Force }
    try {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target -ErrorAction Stop | Out-Null
    } catch {
        # Fallback for Windows without Developer Mode: directory junction (no admin required, dirs only)
        if ($IsWindows) {
            cmd /c mklink /J "$Link" "$Target" | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Link)) {
                throw "Failed to create symlink or junction at '$Link' -> '$Target' (mklink exit $LASTEXITCODE): $($_.Exception.Message)"
            }
        } else {
            throw
        }
    }
}

function Install-CopilotCliSymlinks {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepoRoot)
    $userHome = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    New-DirectorySymlink `
        -Link (Join-Path $userHome '.copilot/skills') `
        -Target (Join-Path $RepoRoot 'plugins/pitt-skills/skills')
}

function Install-CopilotChatSymlinks {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepoRoot)
    $userHome = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    New-DirectorySymlink `
        -Link (Join-Path $userHome '.copilot/instructions') `
        -Target (Join-Path $RepoRoot '.github/instructions')
    if (Test-Path (Join-Path $RepoRoot '.github/prompts')) {
        New-DirectorySymlink `
            -Link (Join-Path $userHome '.copilot/prompts') `
            -Target (Join-Path $RepoRoot '.github/prompts')
    }
}

if (-not $DotSource) {
    $repoRoot = Split-Path $PSScriptRoot -Parent

    # Detect shadowing before merging settings — surface the conflict early.
    # Only meaningful for the Claude integration, but cheap to always run.
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

    foreach ($tool in $Tools) {
        switch ($tool) {
            'claude'     { Merge-ClaudeSettings -SnippetPath (Join-Path $repoRoot 'settings.snippet.json') }
            'copilotCli' { Install-CopilotCliSymlinks -RepoRoot $repoRoot }
            'vscode'     { Install-CopilotChatSymlinks -RepoRoot $repoRoot }
        }
    }
    Write-Host "Done. Restart your tool(s)."
}
