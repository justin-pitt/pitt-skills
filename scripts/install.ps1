[CmdletBinding()]
# -DotSource, -RemoveShadowing, -Tools, and -Uninstall are wired up.
# -Tools defaults to all three integrations (claude, copilotCli, vscode); pass -Tools explicitly to limit.
# When -Tools is not passed, the script auto-detects which CLIs are installed (claude / copilot / code)
# and only wires those up. The same auto-detection gates -Uninstall.
# -WhatIf is reserved for a future milestone and currently no-op.
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

function ConvertTo-HashtableRecursive {
    # ConvertFrom-Json -AsHashtable is PS 6.0+. On Windows PowerShell 5.1 we
    # walk the PSCustomObject result and rebuild it as nested [hashtable] so
    # the rest of the script can use Keys/ContainsKey/[] uniformly.
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $Value.PSObject.Properties) {
            $h[$p.Name] = ConvertTo-HashtableRecursive $p.Value
        }
        return $h
    }
    if ($Value -is [System.Collections.IList] -and $Value -isnot [string]) {
        $items = foreach ($i in $Value) { ConvertTo-HashtableRecursive $i }
        return ,@($items)
    }
    return $Value
}

function ConvertFrom-JsonAsHashtable {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Json)
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return $Json | ConvertFrom-Json -AsHashtable
    }
    return (ConvertTo-HashtableRecursive ($Json | ConvertFrom-Json))
}

function Merge-ClaudeSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SnippetPath
    )
    $claudeHome = Get-ClaudeHome
    if (-not (Test-Path $claudeHome)) { New-Item -ItemType Directory -Path $claudeHome -Force | Out-Null }
    $settingsPath = Join-Path $claudeHome 'settings.json'
    $snippet = ConvertFrom-JsonAsHashtable -Json (Get-Content $SnippetPath -Raw)

    if (Test-Path $settingsPath) {
        Copy-Item $settingsPath "$settingsPath.bak" -Force
        try {
            $existing = ConvertFrom-JsonAsHashtable -Json (Get-Content $settingsPath -Raw)
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
            Write-Warning "Settings key '$key' has incompatible types in existing ($($existing[$key].GetType().Name)) vs snippet ($($snippet[$key].GetType().Name)). Existing value will be overwritten - see $settingsPath.bak to restore."
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
    if (Test-Path $Link) {
        $existing = Get-Item $Link -Force
        if ($existing.LinkType) {
            # Stale symlink or junction - safe to remove
            Remove-Item $Link -Force
        } else {
            throw "Refusing to overwrite non-symlink at '$Link'. Move or remove it manually, then re-run."
        }
    }
    try {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target -ErrorAction Stop | Out-Null
    } catch {
        # Fallback for Windows without Developer Mode: directory junction (no admin required, dirs only).
        # $IsWindows is PS 6+ only and is $null on Windows PowerShell 5.1, so also check $env:OS.
        if ($IsWindows -or $env:OS -eq 'Windows_NT') {
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

function Remove-ClaudeSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SnippetPath  # accepted for symmetry; unused
    )
    $claudeHome = Get-ClaudeHome
    $settingsPath = Join-Path $claudeHome 'settings.json'
    if (-not (Test-Path $settingsPath)) {
        Write-Host "Claude settings: nothing to remove (no $settingsPath)."
        return
    }
    Copy-Item $settingsPath "$settingsPath.bak" -Force
    try {
        $existing = ConvertFrom-JsonAsHashtable -Json (Get-Content $settingsPath -Raw)
    } catch {
        throw "Existing settings.json at $settingsPath is not valid JSON ($($_.Exception.Message)). Original backed up at $settingsPath.bak. Fix the JSON manually and re-run."
    }

    if ($existing.ContainsKey('extraKnownMarketplaces') -and $existing['extraKnownMarketplaces'] -is [hashtable]) {
        # Only remove the pitt-skills entry. The other marketplaces in settings.snippet.json
        # (superpowers-dev, anthropic-agent-skills, superpowers-marketplace) reference upstream
        # marketplaces a user might want independently of this plugin - leave them alone.
        if ($existing['extraKnownMarketplaces'].ContainsKey('pitt-skills')) {
            $existing['extraKnownMarketplaces'].Remove('pitt-skills')
        }
        if ($existing['extraKnownMarketplaces'].Count -eq 0) {
            $existing.Remove('extraKnownMarketplaces')
        }
    }

    if ($existing.ContainsKey('enabledPlugins') -and $existing['enabledPlugins'] -is [hashtable]) {
        if ($existing['enabledPlugins'].ContainsKey('pitt-skills@pitt-skills')) {
            $existing['enabledPlugins'].Remove('pitt-skills@pitt-skills')
        }
        if ($existing['enabledPlugins'].Count -eq 0) {
            $existing.Remove('enabledPlugins')
        }
    }

    # ConvertFrom-Json -AsHashtable returns a regular [hashtable] with non-deterministic
    # key order. Convert each level to [ordered] so the on-disk file is stable across runs.
    $ordered = ConvertTo-OrderedHashtable $existing
    $ordered | ConvertTo-Json -Depth 32 | Set-Content $settingsPath
    Write-Host "Claude settings: removed pitt-skills entries (backup at $settingsPath.bak)."
}

function ConvertTo-OrderedHashtable {
    # Preserve insertion order. ConvertFrom-Json -AsHashtable in pwsh 7.3+ returns
    # an OrderedHashtable that already preserves order; we mirror that into [ordered]
    # so older pwsh and downstream Set-Content writes are deterministic without
    # alphabetizing the user's other keys.
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)] $Value)
    if ($Value -is [hashtable]) {
        $ordered = [ordered]@{}
        foreach ($k in $Value.Keys) {
            $ordered[$k] = ConvertTo-OrderedHashtable $Value[$k]
        }
        return $ordered
    }
    return $Value
}

function Remove-DirectorySymlink {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Link)
    if (-not (Test-Path $Link)) {
        return [pscustomobject]@{ Path = $Link; Status = 'absent' }
    }
    $existing = Get-Item -Force $Link
    if ($existing.LinkType -in @('SymbolicLink', 'Junction')) {
        # Mirror New-DirectorySymlink's removal: -Force without -Recurse so we never
        # accidentally walk into the link target and delete real content.
        Remove-Item $Link -Force
        return [pscustomobject]@{ Path = $Link; Status = 'removed' }
    }
    Write-Warning "Refusing to delete non-symlink at '$Link'. Looks like real content; remove manually if intended."
    return [pscustomobject]@{ Path = $Link; Status = 'refused' }
}

function Remove-CopilotCliSymlinks {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepoRoot)
    $userHome = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    $result = Remove-DirectorySymlink -Link (Join-Path $userHome '.copilot/skills')
    Write-Host "Copilot CLI: ~/.copilot/skills $($result.Status)"
}

function Remove-CopilotChatSymlinks {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepoRoot)
    $userHome = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    $r1 = Remove-DirectorySymlink -Link (Join-Path $userHome '.copilot/instructions')
    $r2 = Remove-DirectorySymlink -Link (Join-Path $userHome '.copilot/prompts')
    Write-Host "Copilot Chat: ~/.copilot/instructions $($r1.Status); ~/.copilot/prompts $($r2.Status)"
}

function Test-ToolInstalled {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)
    return [bool] (Get-Command $Name -ErrorAction SilentlyContinue)
}

if (-not $DotSource) {
    $repoRoot = Split-Path $PSScriptRoot -Parent

    if (-not $Uninstall) {
        # Detect shadowing before merging settings - surface the conflict early.
        # Only meaningful for the Claude integration, but cheap to always run.
        # Skipped on -Uninstall: we are not adding plugin skills, so shadowing is moot.
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
    }

    $detected = @()
    if (Test-ToolInstalled 'claude')  { $detected += 'claude' }
    if (Test-ToolInstalled 'copilot') { $detected += 'copilotCli' }
    if (Test-ToolInstalled 'code')    { $detected += 'vscode' }
    # Auto-detect only if the caller did not explicitly pass -Tools. The param has a
    # non-empty default, so checking $PSBoundParameters is the only way to distinguish
    # "user picked all three" from "user did not specify". Same gate applies to -Uninstall.
    if (-not $PSBoundParameters.ContainsKey('Tools')) { $Tools = $detected }

    if (-not $Tools -or $Tools.Count -eq 0) {
        $verb = if ($Uninstall) { 'uninstall' } else { 'wire up' }
        Write-Warning "No tools to $verb. Pass -Tools claude,copilotCli,vscode to override auto-detection."
        return
    }

    $action = if ($Uninstall) { 'Uninstalling' } else { 'Wiring up' }
    Write-Host "Detected tools: $($detected -join ', ')"
    Write-Host "${action}: $($Tools -join ', ')"

    foreach ($tool in $Tools) {
        if ($Uninstall) {
            switch ($tool) {
                'claude'     { Remove-ClaudeSettings -SnippetPath (Join-Path $repoRoot 'settings.snippet.json') }
                'copilotCli' { Remove-CopilotCliSymlinks -RepoRoot $repoRoot }
                'vscode'     { Remove-CopilotChatSymlinks -RepoRoot $repoRoot }
                default      { Write-Warning "Unknown tool '$tool' - skipping. Valid: claude, copilotCli, vscode" }
            }
        } else {
            switch ($tool) {
                'claude'     { Merge-ClaudeSettings -SnippetPath (Join-Path $repoRoot 'settings.snippet.json') }
                'copilotCli' { Install-CopilotCliSymlinks -RepoRoot $repoRoot }
                'vscode'     { Install-CopilotChatSymlinks -RepoRoot $repoRoot }
                default      { Write-Warning "Unknown tool '$tool' - skipping. Valid: claude, copilotCli, vscode" }
            }
        }
    }
    if ($Uninstall) {
        Write-Host "Done. Restart your tool(s) to pick up changes."
    } else {
        Write-Host "Done. Restart your tool(s)."
    }
}
