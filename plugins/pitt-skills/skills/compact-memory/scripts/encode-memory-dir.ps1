#requires -Version 5.1
<#
.SYNOPSIS
    Encode a workspace path into the directory name Claude Code uses under
    ~/.claude/projects/. Mirrors encode-memory-dir.sh.

.DESCRIPTION
    Rule: drop the drive letter, then replace `:`, `/`, and `\` with `-`.
    Prints two lines: encoded segment and full memory dir path.

.PARAMETER Path
    Workspace path to encode. Defaults to $PWD.

.PARAMETER Validate
    Also run a JSON syntax check on ~/.claude/settings.json.

.EXAMPLE
    .\encode-memory-dir.ps1 "C:\Code\pitt-skills"
    .\encode-memory-dir.ps1 -Validate
#>
[CmdletBinding()]
param(
    [string]$Path = (Get-Location).Path,
    [switch]$Validate
)

$ErrorActionPreference = 'Stop'

$p = $Path
if ($p -match '^[A-Za-z]:') {
    $p = $p.Substring(2)
}
$enc = $p -replace ':', '-' -replace '/', '-' -replace '\\', '-'
$enc = $enc -replace '^-+', ''

$claudeHome = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOME '.claude' }
$memoryDir = Join-Path (Join-Path (Join-Path $claudeHome 'projects') $enc) 'memory'

Write-Output $enc
Write-Output $memoryDir

if ($Validate) {
    $settings = Join-Path $claudeHome 'settings.json'
    if (Test-Path $settings) {
        try {
            Get-Content -Raw $settings | ConvertFrom-Json | Out-Null
            Write-Output 'settings.json: ok'
        } catch {
            Write-Error "settings.json: invalid JSON ($_)"
            exit 1
        }
    } else {
        Write-Output 'settings.json: not present'
    }
}
