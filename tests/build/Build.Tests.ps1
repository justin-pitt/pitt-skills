# Pester 5 tests for scripts/build.ps1 (Task 21).
#
# Strategy: copy the input fixture tree into a temp WorkDir, run build.ps1 -RepoRoot $WorkDir,
# then byte-compare WorkDir against the expected fixture tree using `git diff --no-index`.
#
# Notes for whoever updates this test:
#   - Copy-Item -Recurse "input" $WorkDir copies the *contents* of input into a new WorkDir
#     when WorkDir does not exist. The input fixture tree is therefore structured as
#     `input/plugins/pitt-skills/skills/...` (mirroring repo layout) so build.ps1 can find
#     SKILL.md files at $WorkDir/plugins/pitt-skills/skills/ as it expects.
#   - We invoke `git -c core.autocrlf=false diff --no-index` to suppress autocrlf warnings
#     that would otherwise pollute stderr on Windows machines with autocrlf enabled.
#   - Get-FileHash does not have a -Recurse parameter; we feed it file paths via
#     Get-ChildItem -Recurse -File.

BeforeAll {
    $script:RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
}

Describe "build.ps1 -- golden file" {
    BeforeEach {
        $script:WorkDir = Join-Path $env:TEMP "pitt-build-test-$(New-Guid)"
        # WorkDir does not exist yet; Copy-Item -Recurse copies contents of input/ into it.
        Copy-Item -Recurse "$script:Fixtures/input" $script:WorkDir
    }
    AfterEach {
        if (Test-Path $script:WorkDir) {
            Remove-Item $script:WorkDir -Recurse -Force
        }
    }

    It "generates expected .github/instructions/, prompts/, agents/, JSON manifests" {
        & "$script:RepoRoot/scripts/build.ps1" -RepoRoot $script:WorkDir
        $diff = git -c core.autocrlf=false diff --no-index "$script:Fixtures/expected" $script:WorkDir 2>&1
        $diff | Should -BeNullOrEmpty -Because "build output should match golden fixtures exactly. Diff:`n$($diff -join "`n")"
    }

    It "is idempotent -- second run produces no change" {
        & "$script:RepoRoot/scripts/build.ps1" -RepoRoot $script:WorkDir
        $firstHash = Get-ChildItem -Recurse -File "$script:WorkDir/.github" |
            Get-FileHash | Sort-Object Path
        & "$script:RepoRoot/scripts/build.ps1" -RepoRoot $script:WorkDir
        $secondHash = Get-ChildItem -Recurse -File "$script:WorkDir/.github" |
            Get-FileHash | Sort-Object Path
        Compare-Object $firstHash $secondHash -Property Path, Hash | Should -BeNullOrEmpty
    }
}
