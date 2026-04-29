BeforeAll {
    $script:RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    . "$script:RepoRoot/scripts/install.ps1" -DotSource
}

Describe "Merge-ClaudeSettings" {
    BeforeEach {
        $script:TempHome = New-Item -ItemType Directory -Path "$env:TEMP/pitt-skills-test-$(New-Guid)"
        $script:OrigClaudeHome = $env:CLAUDE_HOME
        $env:CLAUDE_HOME = $script:TempHome.FullName
    }
    AfterEach {
        $env:CLAUDE_HOME = $script:OrigClaudeHome
        Remove-Item $script:TempHome -Recurse -Force
    }

    It "creates settings.json if absent, with snippet contents" {
        Merge-ClaudeSettings -SnippetPath "$script:RepoRoot/settings.snippet.json"
        $result = Get-Content "$($script:TempHome.FullName)/settings.json" -Raw | ConvertFrom-Json
        $result.extraKnownMarketplaces.'pitt-skills'.source.repo | Should -Be "justin-pitt/pitt-skills"
    }

    It "preserves existing keys when merging" {
        $existing = @{ theme = "dark"; extraKnownMarketplaces = @{ other = @{ source = @{ repo = "x/y" } } } } | ConvertTo-Json -Depth 10
        $existing | Set-Content "$($script:TempHome.FullName)/settings.json"
        Merge-ClaudeSettings -SnippetPath "$script:RepoRoot/settings.snippet.json"
        $result = Get-Content "$($script:TempHome.FullName)/settings.json" -Raw | ConvertFrom-Json
        $result.theme | Should -Be "dark"
        $result.extraKnownMarketplaces.other.source.repo | Should -Be "x/y"
        $result.extraKnownMarketplaces.'pitt-skills'.source.repo | Should -Be "justin-pitt/pitt-skills"
    }

    It "writes a backup before modifying an existing file" {
        '{"theme":"dark"}' | Set-Content "$($script:TempHome.FullName)/settings.json"
        Merge-ClaudeSettings -SnippetPath "$script:RepoRoot/settings.snippet.json"
        Test-Path "$($script:TempHome.FullName)/settings.json.bak" | Should -BeTrue
    }
}

Describe "Get-ShadowingSkills" {
    BeforeEach {
        $script:TempHome = New-Item -ItemType Directory -Path "$env:TEMP/pitt-skills-test-$(New-Guid)"
        $script:OrigClaudeHome = $env:CLAUDE_HOME
        $env:CLAUDE_HOME = $script:TempHome.FullName
        # Pretend two skills exist in the plugin
        $script:FakePluginSkills = New-Item -ItemType Directory -Path "$($script:TempHome.FullName)/fake-repo/plugins/pitt-skills/skills"
        New-Item -ItemType Directory -Path "$($script:FakePluginSkills.FullName)/threatconnect-polarity" | Out-Null
        New-Item -ItemType Directory -Path "$($script:FakePluginSkills.FullName)/owasp-security" | Out-Null
    }
    AfterEach {
        $env:CLAUDE_HOME = $script:OrigClaudeHome
        Remove-Item $script:TempHome -Recurse -Force
    }

    It "returns empty when ~/.claude/skills does not exist" {
        $repoRoot = "$($script:TempHome.FullName)/fake-repo"
        $result = Get-ShadowingSkills -RepoRoot $repoRoot
        $result | Should -BeNullOrEmpty
        $result -is [array] | Should -BeTrue
        $result.Count | Should -Be 0
    }

    It "returns names that exist in both standalone and plugin" {
        $standalone = New-Item -ItemType Directory -Path "$($script:TempHome.FullName)/skills/threatconnect-polarity"
        New-Item -ItemType Directory -Path "$($script:TempHome.FullName)/skills/unrelated-skill" | Out-Null
        $repoRoot = "$($script:TempHome.FullName)/fake-repo"
        $shadowing = Get-ShadowingSkills -RepoRoot $repoRoot
        $shadowing -is [array] | Should -BeTrue
        $shadowing.Count | Should -Be 1
        $shadowing | Should -Contain 'threatconnect-polarity'
        $shadowing | Should -Not -Contain 'unrelated-skill'
        $shadowing | Should -Not -Contain 'owasp-security'  # not standalone, only plugin
    }
}

Describe "Remove-ShadowingSkills" {
    BeforeEach {
        $script:TempHome = New-Item -ItemType Directory -Path "$env:TEMP/pitt-skills-test-$(New-Guid)"
        $script:OrigClaudeHome = $env:CLAUDE_HOME
        $env:CLAUDE_HOME = $script:TempHome.FullName
        $script:FakeRepoRoot = "$($script:TempHome.FullName)/fake-repo"
        New-Item -ItemType Directory -Path "$script:FakeRepoRoot/plugins/pitt-skills/skills/threatconnect-polarity" -Force | Out-Null
        $script:Standalone = New-Item -ItemType Directory -Path "$($script:TempHome.FullName)/skills/threatconnect-polarity"
        'sentinel' | Set-Content "$($script:Standalone.FullName)/SKILL.md"
    }
    AfterEach {
        $env:CLAUDE_HOME = $script:OrigClaudeHome
        Remove-Item $script:TempHome -Recurse -Force
    }

    It "moves shadowing skill to a timestamped backup dir, leaving plugin path intact" {
        Remove-ShadowingSkills -RepoRoot $script:FakeRepoRoot
        Test-Path $script:Standalone.FullName | Should -BeFalse
        $backups = Get-ChildItem "$($script:TempHome.FullName)/skills" -Directory -Filter '.shadow-backup-*'
        $backups.Count | Should -BeGreaterThan 0
        $sentinel = Get-Content "$($backups[0].FullName)/threatconnect-polarity/SKILL.md" -Raw
        $sentinel.Trim() | Should -Be 'sentinel'
    }
}

Describe "Install-Symlinks" {
    BeforeEach {
        $script:TempHome = New-Item -ItemType Directory -Path "$env:TEMP/pitt-skills-test-$(New-Guid)"
        $script:OrigHome = $env:HOME
        $script:OrigUserProfile = $env:USERPROFILE
        $env:USERPROFILE = $script:TempHome.FullName
        $env:HOME = $script:TempHome.FullName
    }
    AfterEach {
        $env:HOME = $script:OrigHome
        $env:USERPROFILE = $script:OrigUserProfile
        Remove-Item $script:TempHome -Recurse -Force
    }

    It "creates ~/.copilot/skills symlink to repo's skills dir" {
        Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        $link = Join-Path $script:TempHome.FullName '.copilot/skills'
        Test-Path $link | Should -BeTrue
        (Get-Item $link).Target | Should -Match 'plugins[/\\]pitt-skills[/\\]skills'
    }

    It "creates ~/.copilot/instructions symlink to repo's .github/instructions" {
        Install-CopilotChatSymlinks -RepoRoot $script:RepoRoot
        Test-Path (Join-Path $script:TempHome.FullName '.copilot/instructions') | Should -BeTrue
    }
}
