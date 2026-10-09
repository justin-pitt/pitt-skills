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
        $result.extraKnownMarketplaces.'pitt-skills'.source.url | Should -Be "https://github.com/justin-pitt/pitt-skills.git"
    }

    It "preserves existing keys when merging" {
        $existing = @{ theme = "dark"; extraKnownMarketplaces = @{ other = @{ source = @{ repo = "x/y" } } } } | ConvertTo-Json -Depth 10
        $existing | Set-Content "$($script:TempHome.FullName)/settings.json"
        Merge-ClaudeSettings -SnippetPath "$script:RepoRoot/settings.snippet.json"
        $result = Get-Content "$($script:TempHome.FullName)/settings.json" -Raw | ConvertFrom-Json
        $result.theme | Should -Be "dark"
        $result.extraKnownMarketplaces.other.source.repo | Should -Be "x/y"
        $result.extraKnownMarketplaces.'pitt-skills'.source.url | Should -Be "https://github.com/justin-pitt/pitt-skills.git"
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

    It "links each skill from the plugin and the vendored superpowers folder into a real ~/.copilot/skills" {
        Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        $skillsHome = Join-Path $script:TempHome.FullName '.copilot/skills'
        (Get-Item -Force $skillsHome).LinkType | Should -BeNullOrEmpty
        (Get-Item -Force (Join-Path $skillsHome 'tines')).Target | Should -Match 'plugins[/\\]pitt-skills[/\\]skills[/\\]tines$'
        (Get-Item -Force (Join-Path $skillsHome 'brainstorming')).Target | Should -Match 'vendor[/\\]superpowers[/\\]brainstorming$'
        @(Get-ChildItem -Force $skillsHome).Count | Should -Be (Get-CopilotSkillDirs -RepoRoot $script:RepoRoot).Count
    }

    It "replaces the whole-directory link an earlier release created and leaves the repo intact" {
        $skillsHome = Join-Path $script:TempHome.FullName '.copilot/skills'
        New-DirectorySymlink -Link $skillsHome -Target (Join-Path $script:RepoRoot 'plugins/pitt-skills/skills')
        Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        (Get-Item -Force $skillsHome).LinkType | Should -BeNullOrEmpty
        Test-Path (Join-Path $script:RepoRoot 'plugins/pitt-skills/skills/tines/SKILL.md') | Should -BeTrue
        (Get-Item -Force (Join-Path $skillsHome 'tines')).LinkType | Should -Not -BeNullOrEmpty
    }

    It "drops links into the repo for skills that no longer exist, and only those" {
        Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        $skillsHome = Join-Path $script:TempHome.FullName '.copilot/skills'
        New-DirectorySymlink -Link (Join-Path $skillsHome 'retired-skill') -Target (Join-Path $script:RepoRoot 'scripts')
        $outside = New-Item -ItemType Directory -Path (Join-Path $script:TempHome.FullName 'elsewhere/kept-skill') -Force
        New-DirectorySymlink -Link (Join-Path $skillsHome 'kept-skill') -Target $outside.FullName
        Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        Get-Item -Force (Join-Path $skillsHome 'retired-skill') -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        (Get-Item -Force (Join-Path $skillsHome 'kept-skill')).LinkType | Should -Not -BeNullOrEmpty
        Test-Path (Join-Path $script:RepoRoot 'scripts/install.ps1') | Should -BeTrue
    }

    It "creates ~/.copilot/instructions symlink to repo's .github/instructions" {
        Install-CopilotChatSymlinks -RepoRoot $script:RepoRoot
        Test-Path (Join-Path $script:TempHome.FullName '.copilot/instructions') | Should -BeTrue
    }

    It "adds its links into an existing real ~/.copilot/skills and keeps the user's own content" {
        $skillsHome = Join-Path $script:TempHome.FullName '.copilot/skills'
        New-Item -ItemType Directory -Path (Join-Path $skillsHome 'my-own-skill') -Force | Out-Null
        'real user content' | Set-Content (Join-Path $skillsHome 'my-own-skill/SKILL.md')

        Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot

        Test-Path (Join-Path $skillsHome 'my-own-skill/SKILL.md') | Should -BeTrue
        (Get-Item -Force (Join-Path $skillsHome 'brainstorming')).LinkType | Should -Not -BeNullOrEmpty
    }

    It "refuses, before changing anything, when one of the user's own folders has a pitt-skills name" {
        $skillsHome = Join-Path $script:TempHome.FullName '.copilot/skills'
        New-Item -ItemType Directory -Path (Join-Path $skillsHome 'brainstorming') -Force | Out-Null
        'real user content' | Set-Content (Join-Path $skillsHome 'brainstorming/do-not-delete.md')

        { Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot } | Should -Throw -ExpectedMessage "*Refusing to overwrite*brainstorming*"

        # The user's folder survives and nothing was linked beside it.
        Test-Path (Join-Path $skillsHome 'brainstorming/do-not-delete.md') | Should -BeTrue
        @(Get-ChildItem -Force $skillsHome).Count | Should -Be 1
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

Describe "Hermes integration" {
    BeforeEach {
        $script:TempHome = New-Item -ItemType Directory -Path "$env:TEMP/pitt-skills-test-$(New-Guid)"
        $script:OrigHome = $env:HOME
        $script:OrigUserProfile = $env:USERPROFILE
        $script:OrigHermesHome = $env:HERMES_HOME
        $env:USERPROFILE = $script:TempHome.FullName
        $env:HOME = $script:TempHome.FullName
        $env:HERMES_HOME = Join-Path $script:TempHome.FullName '.hermes'
    }
    AfterEach {
        $env:HOME = $script:OrigHome
        $env:USERPROFILE = $script:OrigUserProfile
        $env:HERMES_HOME = $script:OrigHermesHome
        Remove-Item $script:TempHome -Recurse -Force
    }

    It "Get-HermesHome honors HERMES_HOME" {
        Get-HermesHome | Should -Be $env:HERMES_HOME
    }

    It "Get-HermesHome falls back to <home>/.hermes when HERMES_HOME is unset" {
        $env:HERMES_HOME = $null
        Get-HermesHome | Should -Be (Join-Path $script:TempHome.FullName '.hermes')
    }

    It "Install-HermesSymlinks mounts the plugin skills and the vendored superpowers snapshot" {
        Install-HermesSymlinks -RepoRoot $script:RepoRoot
        $link = Join-Path $env:HERMES_HOME 'skills/pitt-skills'
        Test-Path $link | Should -BeTrue
        (Get-Item $link).Target | Should -Match 'plugins[/\\]pitt-skills[/\\]skills'
        $vendored = Join-Path $env:HERMES_HOME 'skills/pitt-skills-superpowers'
        Test-Path $vendored | Should -BeTrue
        (Get-Item $vendored).Target | Should -Match 'vendor[/\\]superpowers'
    }

    It "Install-HermesSymlinks refuses to overwrite a non-symlink at the link path" {
        $linkParent = Join-Path $env:HERMES_HOME 'skills'
        New-Item -ItemType Directory -Path $linkParent -Force | Out-Null
        $link = Join-Path $linkParent 'pitt-skills'
        New-Item -ItemType Directory -Path $link | Out-Null
        'real user content' | Set-Content (Join-Path $link 'do-not-delete.md')

        { Install-HermesSymlinks -RepoRoot $script:RepoRoot } | Should -Throw -ExpectedMessage "*Refusing to overwrite*"
        Test-Path (Join-Path $link 'do-not-delete.md') | Should -BeTrue
    }

    It "Remove-HermesSymlinks removes the symlink and is idempotent" {
        Install-HermesSymlinks -RepoRoot $script:RepoRoot
        $link = Join-Path $env:HERMES_HOME 'skills/pitt-skills'
        Test-Path $link | Should -BeTrue
        Remove-HermesSymlinks -RepoRoot $script:RepoRoot
        Test-Path $link | Should -BeFalse
        Test-Path (Join-Path $env:HERMES_HOME 'skills/pitt-skills-superpowers') | Should -BeFalse
        # Idempotent
        { Remove-HermesSymlinks -RepoRoot $script:RepoRoot } | Should -Not -Throw
    }

    It "Remove-HermesSymlinks refuses to delete a real directory at the link path" {
        $linkParent = Join-Path $env:HERMES_HOME 'skills'
        New-Item -ItemType Directory -Path $linkParent -Force | Out-Null
        $link = Join-Path $linkParent 'pitt-skills'
        New-Item -ItemType Directory -Path $link | Out-Null
        'real user content' | Set-Content (Join-Path $link 'do-not-delete.md')

        { Remove-HermesSymlinks -RepoRoot $script:RepoRoot -WarningAction SilentlyContinue } | Should -Not -Throw
        Test-Path (Join-Path $link 'do-not-delete.md') | Should -BeTrue
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

    It "removes its skill links and then the empty ~/.copilot/skills, leaving the repo intact" {
        Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        $link = Join-Path $script:TempHome.FullName '.copilot/skills'
        Test-Path $link | Should -BeTrue
        Remove-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        Test-Path $link | Should -BeFalse
        # Sources should still exist
        Test-Path (Join-Path $script:RepoRoot 'plugins/pitt-skills/skills/tines/SKILL.md') | Should -BeTrue
        Test-Path (Join-Path $script:RepoRoot 'vendor/superpowers/brainstorming/SKILL.md') | Should -BeTrue
    }

    It "removes the whole-directory link an earlier release created" {
        $link = Join-Path $script:TempHome.FullName '.copilot/skills'
        New-DirectorySymlink -Link $link -Target (Join-Path $script:RepoRoot 'plugins/pitt-skills/skills')
        Remove-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        Get-Item -Force $link -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Test-Path (Join-Path $script:RepoRoot 'plugins/pitt-skills/skills/tines/SKILL.md') | Should -BeTrue
    }

    It "removes only its own links and keeps the directory when the user's content remains" {
        $skillsHome = Join-Path $script:TempHome.FullName '.copilot/skills'
        New-Item -ItemType Directory -Path (Join-Path $skillsHome 'my-own-skill') -Force | Out-Null
        'real user content' | Set-Content (Join-Path $skillsHome 'my-own-skill/SKILL.md')
        Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot

        Remove-CopilotCliSymlinks -RepoRoot $script:RepoRoot -WarningAction SilentlyContinue

        Test-Path (Join-Path $skillsHome 'my-own-skill/SKILL.md') | Should -BeTrue
        Get-Item -Force (Join-Path $skillsHome 'brainstorming') -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        @(Get-ChildItem -Force $skillsHome).Count | Should -Be 1
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

        { Remove-CopilotCliSymlinks -RepoRoot $script:RepoRoot -WarningAction SilentlyContinue } | Should -Not -Throw
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
        Merge-ClaudeSettings -SnippetPath "$script:RepoRoot/settings.snippet.json"
        Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        $link = Join-Path $script:TempHome.FullName '.copilot/skills'
        Test-Path $link | Should -BeTrue

        # Invoke the script's dispatch path explicitly.
        & "$script:RepoRoot/scripts/install.ps1" -Uninstall -Tools claude

        Test-Path $link | Should -BeTrue   # symlink survives
        $settings = Get-Content (Join-Path $env:CLAUDE_HOME 'settings.json') -Raw | ConvertFrom-Json -AsHashtable
        if ($settings.ContainsKey('extraKnownMarketplaces')) {
            $settings['extraKnownMarketplaces'].ContainsKey('pitt-skills') | Should -BeFalse
        }
    }

    It "-Tools copilotCli,vscode only touches symlinks, not settings.json" {
        Merge-ClaudeSettings -SnippetPath "$script:RepoRoot/settings.snippet.json"
        Install-CopilotCliSymlinks -RepoRoot $script:RepoRoot
        Install-CopilotChatSymlinks -RepoRoot $script:RepoRoot

        & "$script:RepoRoot/scripts/install.ps1" -Uninstall -Tools copilotCli,vscode

        $settings = Get-Content (Join-Path $env:CLAUDE_HOME 'settings.json') -Raw | ConvertFrom-Json -AsHashtable
        $settings['extraKnownMarketplaces'].ContainsKey('pitt-skills') | Should -BeTrue
        $settings['enabledPlugins'].ContainsKey('pitt-skills@pitt-skills') | Should -BeTrue
        Test-Path (Join-Path $script:TempHome.FullName '.copilot/skills') | Should -BeFalse
        Test-Path (Join-Path $script:TempHome.FullName '.copilot/instructions') | Should -BeFalse
    }
}
