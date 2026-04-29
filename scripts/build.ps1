#requires -Version 7.0
# scripts/build.ps1 -- Generate Copilot Chat artifacts (.github/instructions/, prompts/,
# agents/, copilot-instructions.md) and JSON manifests from SKILL.md frontmatter.
#
# Idempotent: wipes generated dirs before regenerating. Safe to re-run.
#
# Output line endings (matches golden fixtures in tests/build/fixtures/expected/):
#   .md files -- LF interior newlines, trailing CRLF (Set-Content default on Windows pwsh 7+)
#   .json files -- fully CRLF (ConvertTo-Json default + Set-Content trailing CRLF)
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

$skillsDir = Join-Path $RepoRoot 'plugins/pitt-skills/skills'
$githubDir = Join-Path $RepoRoot '.github'
$instructionsDir = Join-Path $githubDir 'instructions'
$promptsDir = Join-Path $githubDir 'prompts'
$agentsDir = Join-Path $githubDir 'agents'

# Wipe-and-regenerate to keep idempotent and self-cleaning.
foreach ($d in @($instructionsDir, $promptsDir, $agentsDir)) {
    if (Test-Path $d) { Remove-Item $d -Recurse -Force }
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

function ConvertFrom-Frontmatter {
    param([string]$Content)
    if ($Content -notmatch '(?ms)\A---\r?\n(.*?)\r?\n---\r?\n(.*)\z') {
        throw "No YAML frontmatter found"
    }
    # Lightweight YAML parse -- only key:value, nested via 2-space indent.
    # Also handles `description: >` folded-block scalars (joins indented continuation
    # lines with a single space) since some real skills (cortex-xsiam) use that form.
    $yaml = $matches[1]
    $body = $matches[2]
    $result = @{}
    $currentKey = $null
    $foldedKey = $null  # key whose value is a folded-block scalar (`>` or `|`)
    $foldedLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $yaml -split "`r?`n") {
        # If we're in a folded-block scalar, keep collecting indented lines.
        if ($null -ne $foldedKey) {
            if ($line -match '^\s+(\S.*)$') {
                $foldedLines.Add($matches[1].Trim())
                continue
            } else {
                # End of folded scalar: flush.
                $result[$foldedKey] = ($foldedLines -join ' ')
                $foldedKey = $null
                $foldedLines.Clear()
                # fall through and let this line match below
            }
        }
        if ($line -match '^([a-zA-Z][\w-]*):\s*(.*)$') {
            $key = $matches[1]
            $val = $matches[2]
            if ($val -eq '') {
                $currentKey = $key
                $result[$currentKey] = @{}
            } elseif ($val -eq '>' -or $val -eq '|') {
                # Folded/literal block scalar -- start collecting indented lines.
                $foldedKey = $key
                $foldedLines.Clear()
                $currentKey = $null
            } else {
                $result[$key] = $val.Trim('"').Trim("'")
                $currentKey = $null
            }
        } elseif ($line -match '^\s\s([a-zA-Z][\w-]*):\s*(.*)$' -and $currentKey) {
            $val = $matches[2].Trim('"').Trim("'")
            if ($val -eq 'true') { $val = $true }
            elseif ($val -eq 'false') { $val = $false }
            $result[$currentKey][$matches[1]] = $val
        }
    }
    # Flush any trailing folded scalar that ran to end-of-frontmatter.
    if ($null -ne $foldedKey) {
        $result[$foldedKey] = ($foldedLines -join ' ')
    }
    # Strip a leading blank line from the body if present so output has exactly one
    # blank line between the closing `---` and the first body line.
    $body = $body -replace '\A\r?\n', ''
    # Also strip a trailing newline -- `Set-Content` will append a CRLF after the final
    # character, and we want exactly one trailing line ending in the output (matching
    # the golden fixtures, which were authored from here-strings with no trailing `\n`).
    $body = $body -replace '\r?\n\z', ''
    return @{ Frontmatter = $result; Body = $body }
}

$skills = Get-ChildItem $skillsDir -Directory
# Use [ordered]@{} to keep deterministic JSON key order (plain @{} hashtables iterate
# in indeterminate order, breaking both the diff and idempotency tests).
$pluginManifest = [ordered]@{
    name = 'pitt-skills'
    description = "Justin Pitt's personal collection of Claude Code and Copilot skills"
    version = '1.0.0'
    author = [ordered]@{ name = 'Justin Pitt'; email = 'justin@pittnet.net' }
}

foreach ($skill in $skills) {
    $skillFile = Join-Path $skill.FullName 'SKILL.md'
    if (-not (Test-Path $skillFile)) { continue }

    $parsed = ConvertFrom-Frontmatter (Get-Content $skillFile -Raw)
    $name = $parsed.Frontmatter.name
    $desc = $parsed.Frontmatter.description
    $copilot = $parsed.Frontmatter.'copilot-chat'

    $applyTo = if ($copilot -is [hashtable] -and $copilot.applyTo) { $copilot.applyTo } else { '**' }
    $emitPrompt = ($copilot -is [hashtable]) -and ($copilot.prompt -eq $true)
    $emitAgent = ($copilot -is [hashtable]) -and ($copilot.agent -eq $true)

    if ($emitAgent) {
        # .agent.md output
        $out = "---`nname: $name`ndescription: $desc`n---`n`n$($parsed.Body)"
        Set-Content (Join-Path $agentsDir "$name.agent.md") $out
    } else {
        # .instructions.md output
        $out = "---`napplyTo: `"$applyTo`"`ndescription: $desc`n---`n`n$($parsed.Body)"
        Set-Content (Join-Path $instructionsDir "$name.instructions.md") $out
    }

    if ($emitPrompt) {
        $out = "---`ndescription: $desc`n---`n`n$($parsed.Body)"
        Set-Content (Join-Path $promptsDir "$name.prompt.md") $out
    }
}

# copilot-instructions.md preamble. Backticks here are LITERAL backticks in the output
# (escaped as `` so PowerShell does not interpret them as line-continuation).
$preamble = "# Copilot custom instructions`n`nThis repo's Copilot Chat instructions are generated from skills in ``plugins/pitt-skills/skills/``. See [README](../README.md) for usage."
Set-Content (Join-Path $githubDir 'copilot-instructions.md') $preamble

# Plugin manifest
$pluginManifestDir = Join-Path $RepoRoot 'plugins/pitt-skills/.claude-plugin'
if (-not (Test-Path $pluginManifestDir)) {
    New-Item -ItemType Directory -Path $pluginManifestDir -Force | Out-Null
}
$pluginManifest | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $pluginManifestDir 'plugin.json')

# Marketplace manifest
$marketplace = [ordered]@{
    name = 'pitt-skills'
    owner = [ordered]@{ name = 'Justin Pitt'; email = 'justin@pittnet.net' }
    plugins = @([ordered]@{
        name = 'pitt-skills'
        source = './plugins/pitt-skills'
        description = "Justin Pitt's personal collection of Claude Code and Copilot skills"
    })
}
$marketplaceDir = Join-Path $RepoRoot '.claude-plugin'
if (-not (Test-Path $marketplaceDir)) {
    New-Item -ItemType Directory -Path $marketplaceDir -Force | Out-Null
}
$marketplace | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $marketplaceDir 'marketplace.json')

Write-Host "Build complete: $($skills.Count) skills processed."
