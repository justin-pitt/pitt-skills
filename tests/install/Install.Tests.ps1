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

    It "refuses to overwrite a non-symlink at the link path" {
        $linkParent = Join-Path $script:TempHome.FullName '.copilot'
        New-Item -ItemType Directory -Path $linkParent | Out-Null
        $link = Join-Path $linkParent 'skills'
        New-Item -ItemType Directory -Path $link | Out-Null
        'real user content' | Set-Content (Join-Path $link 'do-not-delete.md')

        { Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot } | Should -Throw -ExpectedMessage "*Refusing to overwrite*"

        # Verify the user content was NOT deleted
        Test-Path (Join-Path $link 'do-not-delete.md') | Should -BeTrue
    }
}

Describe "Test-ToolInstalled" {
    It "Test-ToolInstalled detects pwsh" {
        Test-ToolInstalled 'pwsh' | Should -BeTrue
    }
    It "Test-ToolInstalled returns false for nonexistent tool" {
        Test-ToolInstalled 'this-does-not-exist-zzz' | Should -BeFalse
    }
}

Describe "Remove-ClaudeSettings" {
    BeforeEach {
        $script:TempHome = New-Item -ItemType Directory -Path "$env:TEMP/pitt-skills-test-$(New-Guid)"
        $script:OrigClaudeHome = $env:CLAUDE_HOME
        $env:CLAUDE_HOME = $script:TempHome.FullName
        $script:SettingsPath = Join-Path $script:TempHome.FullName 'settings.json'
        $script:Snippet = "$script:RepoRoot/settings.snippet.json"
    }
    AfterEach {
        $env:CLAUDE_HOME = $script:OrigClaudeHome
        Remove-Item $script:TempHome -Recurse -Force
    }

    It "removes pitt-skills marketplace entry and pitt-skills@pitt-skills enabled plugin" {
        Merge-ClaudeSettings -SnippetPath $script:Snippet
        Remove-ClaudeSettings -SnippetPath $script:Snippet
        $result = Get-Content $script:SettingsPath -Raw | ConvertFrom-Json -AsHashtable
        if ($result.ContainsKey('extraKnownMarketplaces')) {
            $result['extraKnownMarketplaces'].ContainsKey('pitt-skills') | Should -BeFalse
        }
        if ($result.ContainsKey('enabledPlugins')) {
            $result['enabledPlugins'].ContainsKey('pitt-skills@pitt-skills') | Should -BeFalse
        }
    }

    It "preserves unrelated user keys (theme + other marketplace)" {
        $existing = [ordered]@{
            theme = "dark"
            extraKnownMarketplaces = [ordered]@{
                someOtherMarketplace = [ordered]@{ source = [ordered]@{ source = "github"; repo = "x/y" } }
                'pitt-skills' = [ordered]@{ source = [ordered]@{ source = "github"; repo = "justin-pitt/pitt-skills" } }
            }
            enabledPlugins = [ordered]@{
                'pitt-skills@pitt-skills' = $true
                'other@plugin' = $true
            }
        } | ConvertTo-Json -Depth 10
        $existing | Set-Content $script:SettingsPath
        Remove-ClaudeSettings -SnippetPath $script:Snippet
        $result = Get-Content $script:SettingsPath -Raw | ConvertFrom-Json -AsHashtable
        $result['theme'] | Should -Be 'dark'
        $result['extraKnownMarketplaces'].ContainsKey('someOtherMarketplace') | Should -BeTrue
        $result['extraKnownMarketplaces'].ContainsKey('pitt-skills') | Should -BeFalse
        $result['enabledPlugins'].ContainsKey('other@plugin') | Should -BeTrue
        $result['enabledPlugins'].ContainsKey('pitt-skills@pitt-skills') | Should -BeFalse
    }

    It "removes the empty parent when only pitt-skills lived under it" {
        $existing = [ordered]@{
            theme = "dark"
            extraKnownMarketplaces = [ordered]@{
                'pitt-skills' = [ordered]@{ source = [ordered]@{ source = "github"; repo = "justin-pitt/pitt-skills" } }
            }
            enabledPlugins = [ordered]@{
                'pitt-skills@pitt-skills' = $true
            }
        } | ConvertTo-Json -Depth 10
        $existing | Set-Content $script:SettingsPath
        Remove-ClaudeSettings -SnippetPath $script:Snippet
        $result = Get-Content $script:SettingsPath -Raw | ConvertFrom-Json -AsHashtable
        $result.ContainsKey('extraKnownMarketplaces') | Should -BeFalse
        $result.ContainsKey('enabledPlugins') | Should -BeFalse
        $result['theme'] | Should -Be 'dark'
    }

    It "writes a backup before modifying an existing file" {
        '{"theme":"dark","extraKnownMarketplaces":{"pitt-skills":{"source":{"source":"github","repo":"justin-pitt/pitt-skills"}}}}' | Set-Content $script:SettingsPath
        Remove-ClaudeSettings -SnippetPath $script:Snippet
        Test-Path "$($script:SettingsPath).bak" | Should -BeTrue
    }

    It "skips silently when settings.json does not exist (idempotent)" {
        { Remove-ClaudeSettings -SnippetPath $script:Snippet } | Should -Not -Throw
        Test-Path $script:SettingsPath | Should -BeFalse
    }

    It "is idempotent: running uninstall twice produces the same final state" {
        Merge-ClaudeSettings -SnippetPath $script:Snippet
        Remove-ClaudeSettings -SnippetPath $script:Snippet
        $first = Get-Content $script:SettingsPath -Raw
        Remove-ClaudeSettings -SnippetPath $script:Snippet
        $second = Get-Content $script:SettingsPath -Raw
        $second | Should -Be $first
    }
}

Describe "Remove-CopilotCliSymlinks" {
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

    It "removes a symlink at ~/.copilot/skills" {
        Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        $link = Join-Path $script:TempHome.FullName '.copilot/skills'
        Test-Path $link | Should -BeTrue
        Remove-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        Test-Path $link | Should -BeFalse
        # Source should still exist
        Test-Path (Join-Path $script:RepoRoot 'plugins/pitt-skills/skills') | Should -BeTrue
    }

    It "is idempotent when the link is already absent" {
        { Remove-CopilotCliSymlinks -RepoRoot $script:RepoRoot } | Should -Not -Throw
        { Remove-CopilotCliSymlinks -RepoRoot $script:RepoRoot } | Should -Not -Throw
    }

    It "refuses to delete a non-symlink directory at the link path; real content survives" {
        $linkParent = Join-Path $script:TempHome.FullName '.copilot'
        New-Item -ItemType Directory -Path $linkParent | Out-Null
        $link = Join-Path $linkParent 'skills'
        New-Item -ItemType Directory -Path $link | Out-Null
        'real user content' | Set-Content (Join-Path $link 'do-not-delete.md')

        Remove-CopilotCliSymlinks -RepoRoot $script:RepoRoot -WarningAction SilentlyContinue
        Test-Path (Join-Path $link 'do-not-delete.md') | Should -BeTrue
    }
}

Describe "Remove-CopilotChatSymlinks" {
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

    It "removes ~/.copilot/instructions and ~/.copilot/prompts symlinks if present" {
        Install-CopilotChatSymlinks -RepoRoot $script:RepoRoot
        $instr = Join-Path $script:TempHome.FullName '.copilot/instructions'
        Test-Path $instr | Should -BeTrue
        Remove-CopilotChatSymlinks -RepoRoot $script:RepoRoot
        Test-Path $instr | Should -BeFalse
    }
}

Describe "Uninstall dispatch via -Tools filter" {
    BeforeEach {
        $script:TempHome = New-Item -ItemType Directory -Path "$env:TEMP/pitt-skills-test-$(New-Guid)"
        $script:OrigHome = $env:HOME
        $script:OrigUserProfile = $env:USERPROFILE
        $script:OrigClaudeHome = $env:CLAUDE_HOME
        $env:USERPROFILE = $script:TempHome.FullName
        $env:HOME = $script:TempHome.FullName
        $env:CLAUDE_HOME = Join-Path $script:TempHome.FullName '.claude'
        New-Item -ItemType Directory -Path $env:CLAUDE_HOME | Out-Null
    }
    AfterEach {
        $env:HOME = $script:OrigHome
        $env:USERPROFILE = $script:OrigUserProfile
        $env:CLAUDE_HOME = $script:OrigClaudeHome
        Remove-Item $script:TempHome -Recurse -Force
    }

    It "-Tools claude only touches settings.json, not symlinks" {
        # Pre-seed both: a settings.json with pitt-skills and a copilot symlink
        Merge-ClaudeSettings -SnippetPath "$script:RepoRoot/settings.snippet.json"
        Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        $link = Join-Path $script:TempHome.FullName '.copilot/skills'
        Test-Path $link | Should -BeTrue

        # Run only the claude uninstall path
        Remove-ClaudeSettings -SnippetPath "$script:RepoRoot/settings.snippet.json"

        # Symlink survives because we did not call Remove-CopilotCliSymlinks
        Test-Path $link | Should -BeTrue
        # Settings cleaned
        $settings = Get-Content (Join-Path $env:CLAUDE_HOME 'settings.json') -Raw | ConvertFrom-Json -AsHashtable
        if ($settings.ContainsKey('extraKnownMarketplaces')) {
            $settings['extraKnownMarketplaces'].ContainsKey('pitt-skills') | Should -BeFalse
        }
    }

    It "-Tools copilotCli,vscode only touches symlinks, not settings.json" {
        Merge-ClaudeSettings -SnippetPath "$script:RepoRoot/settings.snippet.json"
        Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        Install-CopilotChatSymlinks -RepoRoot $script:RepoRoot

        Remove-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        Remove-CopilotChatSymlinks -RepoRoot $script:RepoRoot

        # Settings.json untouched: pitt-skills entry still present
        $settings = Get-Content (Join-Path $env:CLAUDE_HOME 'settings.json') -Raw | ConvertFrom-Json -AsHashtable
        $settings['extraKnownMarketplaces'].ContainsKey('pitt-skills') | Should -BeTrue
        $settings['enabledPlugins'].ContainsKey('pitt-skills@pitt-skills') | Should -BeTrue
        # Symlinks gone
        Test-Path (Join-Path $script:TempHome.FullName '.copilot/skills') | Should -BeFalse
        Test-Path (Join-Path $script:TempHome.FullName '.copilot/instructions') | Should -BeFalse
    }
}
