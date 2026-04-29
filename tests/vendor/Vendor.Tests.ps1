#requires -Version 7.0
BeforeAll {
    $script:RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    . "$script:RepoRoot/scripts/vendor-skill.ps1" -DotSource
}

Describe "Invoke-VendorSkill" {
    BeforeEach {
        $script:WorkDir = New-Item -ItemType Directory -Path "$env:TEMP/pitt-skills-vendor-test-$(New-Guid)"
        $script:SrcDir  = New-Item -ItemType Directory -Path "$($script:WorkDir.FullName)/upstream"
        $script:SkillBody = @'
---
name: foo
description: A test skill
---

# Foo

Body content here.
'@
        Set-Content -Path "$($script:SrcDir.FullName)/SKILL.md" -Value $script:SkillBody -NoNewline
    }
    AfterEach {
        if (Test-Path $script:WorkDir) {
            Remove-Item $script:WorkDir -Recurse -Force
        }
    }

    It "accepts Source as a directory containing SKILL.md" {
        Invoke-VendorSkill -Source $script:SrcDir.FullName -SkillName 'foo' -UpstreamRepo 'obra/superpowers' -UpstreamSha 'abc1234' -RepoRoot $script:WorkDir.FullName
        $dest = Join-Path $script:WorkDir.FullName 'plugins/pitt-skills/skills/foo/SKILL.md'
        Test-Path $dest | Should -BeTrue
    }

    It "accepts Source as a direct path to SKILL.md" {
        $directPath = Join-Path $script:SrcDir.FullName 'SKILL.md'
        Invoke-VendorSkill -Source $directPath -SkillName 'foo' -UpstreamRepo 'obra/superpowers' -UpstreamSha 'abc1234' -RepoRoot $script:WorkDir.FullName
        $dest = Join-Path $script:WorkDir.FullName 'plugins/pitt-skills/skills/foo/SKILL.md'
        Test-Path $dest | Should -BeTrue
    }

    It "writes UPSTREAM.md with repo, SHA, license, and date" {
        Invoke-VendorSkill -Source $script:SrcDir.FullName -SkillName 'foo' -UpstreamRepo 'obra/superpowers' -UpstreamSha 'abc1234' -License 'Apache-2.0' -RepoRoot $script:WorkDir.FullName
        $upstreamPath = Join-Path $script:WorkDir.FullName 'plugins/pitt-skills/skills/foo/UPSTREAM.md'
        $body = Get-Content $upstreamPath -Raw
        $body | Should -Match 'github\.com/obra/superpowers'
        $body | Should -Match 'abc1234'
        $body | Should -Match 'Apache-2\.0'
        $body | Should -Match '\d{4}-\d{2}-\d{2}'
    }

    It "defaults License to MIT when not passed" {
        Invoke-VendorSkill -Source $script:SrcDir.FullName -SkillName 'foo' -UpstreamRepo 'obra/superpowers' -UpstreamSha 'abc1234' -RepoRoot $script:WorkDir.FullName
        $body = Get-Content (Join-Path $script:WorkDir.FullName 'plugins/pitt-skills/skills/foo/UPSTREAM.md') -Raw
        $body | Should -Match 'MIT'
    }

    It "throws when SKILL.md is missing" {
        $emptyDir = New-Item -ItemType Directory -Path "$($script:WorkDir.FullName)/empty"
        { Invoke-VendorSkill -Source $emptyDir.FullName -SkillName 'foo' -UpstreamRepo 'obra/superpowers' -UpstreamSha 'abc1234' -RepoRoot $script:WorkDir.FullName } | Should -Throw -ExpectedMessage '*SKILL.md not found*'
    }

    It "refuses to overwrite an existing populated skill dir without -Force" {
        $existing = New-Item -ItemType Directory -Path "$($script:WorkDir.FullName)/plugins/pitt-skills/skills/foo" -Force
        'sentinel' | Set-Content (Join-Path $existing.FullName 'SKILL.md')
        { Invoke-VendorSkill -Source $script:SrcDir.FullName -SkillName 'foo' -UpstreamRepo 'obra/superpowers' -UpstreamSha 'abc1234' -RepoRoot $script:WorkDir.FullName } | Should -Throw -ExpectedMessage '*already exists*'
        (Get-Content (Join-Path $existing.FullName 'SKILL.md') -Raw).Trim() | Should -Be 'sentinel'
    }

    It "overwrites an existing skill dir when -Force is passed" {
        $existing = New-Item -ItemType Directory -Path "$($script:WorkDir.FullName)/plugins/pitt-skills/skills/foo" -Force
        'stale' | Set-Content (Join-Path $existing.FullName 'SKILL.md')
        Invoke-VendorSkill -Source $script:SrcDir.FullName -SkillName 'foo' -UpstreamRepo 'obra/superpowers' -UpstreamSha 'abc1234' -RepoRoot $script:WorkDir.FullName -Force
        $copied = Get-Content (Join-Path $existing.FullName 'SKILL.md') -Raw
        $copied | Should -Be $script:SkillBody
    }
}
