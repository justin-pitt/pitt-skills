[CmdletBinding()]
# Vendor a third-party SKILL.md into plugins/pitt-skills/skills/<SkillName>/.
# Copies SKILL.md verbatim (no re-parsing) and writes UPSTREAM.md alongside it
# recording where the skill came from. Refuses to overwrite an existing
# populated skill dir unless -Force is passed.
param(
    [switch]$DotSource,
    [string]$Source,
    [string]$SkillName,
    [string]$UpstreamRepo,
    [string]$UpstreamSha,
    [string]$License = 'MIT',
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$Force
)

function Invoke-VendorSkill {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $SkillName,
        [Parameter(Mandatory)] [string] $UpstreamRepo,
        [Parameter(Mandatory)] [string] $UpstreamSha,
        [string] $License = 'MIT',
        [string] $RepoRoot = (Split-Path $PSScriptRoot -Parent),
        [switch] $Force
    )

    # Resolve $Source to a SKILL.md path. Accept either a directory containing
    # SKILL.md or a direct path to SKILL.md. Don't re-parse the file — just copy it.
    $resolved = $Source
    if (Test-Path -PathType Container $Source) {
        $candidate = Join-Path $Source 'SKILL.md'
        if (Test-Path $candidate) {
            $resolved = $candidate
        } else {
            throw "SKILL.md not found at $candidate"
        }
    } elseif (-not (Test-Path $resolved)) {
        throw "SKILL.md not found at $Source"
    }

    $dest = Join-Path $RepoRoot "plugins/pitt-skills/skills/$SkillName"
    if (Test-Path $dest) {
        $existingFiles = Get-ChildItem $dest -Force -ErrorAction SilentlyContinue
        if ($existingFiles -and -not $Force) {
            throw "Destination '$dest' already exists and is non-empty. Re-run with -Force to overwrite."
        }
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    Copy-Item $resolved (Join-Path $dest 'SKILL.md') -Force

    $vendoredOn = Get-Date -Format 'yyyy-MM-dd'
    $upstream = @"
# Upstream source

- **Repo:** https://github.com/$UpstreamRepo
- **Commit SHA at vendoring:** $UpstreamSha
- **Original license:** $License
- **Vendored on:** $vendoredOn

## My changes

(none yet — record changes here as you make them)
"@
    Set-Content -Path (Join-Path $dest 'UPSTREAM.md') -Value $upstream

    Write-Host "Vendored $SkillName from $UpstreamRepo@$UpstreamSha"
}

if (-not $DotSource) {
    if (-not $Source)        { throw "-Source is required" }
    if (-not $SkillName)     { throw "-SkillName is required" }
    if (-not $UpstreamRepo)  { throw "-UpstreamRepo is required" }
    if (-not $UpstreamSha)   { throw "-UpstreamSha is required" }

    Invoke-VendorSkill `
        -Source $Source `
        -SkillName $SkillName `
        -UpstreamRepo $UpstreamRepo `
        -UpstreamSha $UpstreamSha `
        -License $License `
        -RepoRoot $RepoRoot `
        -Force:$Force
}
