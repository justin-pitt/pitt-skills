# One-shot script to author golden-file fixtures with byte-exact output.
# Mirrors what `scripts/build.ps1` (Task 21) is intended to produce, so:
#   - Text files: LF interior newlines, trailing CRLF (Set-Content default on Windows pwsh)
#   - JSON files: ConvertTo-Json -Depth 8, 2-space indent, CRLF separators, trailing CRLF
#
# The fixtures are the source of truth — Task 21 must iterate the build script until its
# output matches these byte-for-byte. Two known issues the implementer will hit:
#   1. PowerShell @{} hashtables iterate in non-deterministic order, so the plan's @{}
#      manifests will produce randomly-ordered JSON. Fix: use [ordered]@{}.
#   2. The plan's body-template "---`napplyTo:...`n---`n`n$Body" combined with a parsed
#      body that starts with a leading "`n" produces THREE consecutive newlines between
#      the closing `---` and the first body line. Fix: trim leading `\r?\n` from the
#      parsed body before interpolation, OR drop one of the `n in the template.
#
# Run from anywhere: pwsh ./tests/build/fixtures/write-fixtures.ps1

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot").Path
$inputDir = Join-Path $root 'input'
$expectedDir = Join-Path $root 'expected'

# ---- Input SKILL.md fixtures ----

$alwaysOn = @'
---
name: example-always-on
description: A skill that always applies
license: MIT
---

# Body content for always-on skill.
'@

$tsOnly = @'
---
name: example-typescript-only
description: A skill scoped to TypeScript files
license: MIT
copilot-chat:
  applyTo: "**/*.ts,**/*.tsx"
---

# TS-only body.
'@

$withPrompt = @'
---
name: example-with-prompt
description: A skill that should also emit a slash-invokable prompt
license: MIT
copilot-chat:
  prompt: true
---

# Slash-invokable body.
'@

$asAgent = @'
---
name: example-as-agent
description: A persistent persona, not an instruction file
license: MIT
copilot-chat:
  agent: true
---

# Persona body.
'@

# Inputs live under input/plugins/pitt-skills/skills/ so that after Copy-Item -Recurse
# input -> WorkDir, the build script finds them at $WorkDir/plugins/pitt-skills/skills/
# (build.ps1 reads from $RepoRoot/plugins/pitt-skills/skills/ per Task 21).
Set-Content (Join-Path $inputDir 'plugins/pitt-skills/skills/example-always-on/SKILL.md') $alwaysOn
Set-Content (Join-Path $inputDir 'plugins/pitt-skills/skills/example-typescript-only/SKILL.md') $tsOnly
Set-Content (Join-Path $inputDir 'plugins/pitt-skills/skills/example-with-prompt/SKILL.md') $withPrompt
Set-Content (Join-Path $inputDir 'plugins/pitt-skills/skills/example-as-agent/SKILL.md') $asAgent

# Mirror the input tree under expected/ — the test copies input -> WorkDir, then runs build there,
# so WorkDir ends up containing both inputs and generated outputs. Expected must mirror that.
Set-Content (Join-Path $expectedDir 'plugins/pitt-skills/skills/example-always-on/SKILL.md') $alwaysOn
Set-Content (Join-Path $expectedDir 'plugins/pitt-skills/skills/example-typescript-only/SKILL.md') $tsOnly
Set-Content (Join-Path $expectedDir 'plugins/pitt-skills/skills/example-with-prompt/SKILL.md') $withPrompt
Set-Content (Join-Path $expectedDir 'plugins/pitt-skills/skills/example-as-agent/SKILL.md') $asAgent

# ---- Generated .github/instructions/*.instructions.md ----
# Format: frontmatter (applyTo + description), blank line, body.

$alwaysOnInstr = @'
---
applyTo: "**"
description: A skill that always applies
---

# Body content for always-on skill.
'@
Set-Content (Join-Path $expectedDir '.github/instructions/example-always-on.instructions.md') $alwaysOnInstr

$tsOnlyInstr = @'
---
applyTo: "**/*.ts,**/*.tsx"
description: A skill scoped to TypeScript files
---

# TS-only body.
'@
Set-Content (Join-Path $expectedDir '.github/instructions/example-typescript-only.instructions.md') $tsOnlyInstr

# example-with-prompt: gets BOTH .instructions.md (default applyTo="**") AND .prompt.md
# Per plan line 1066-1080: $emitAgent skips instructions; $emitPrompt always emits an
# additional prompt file regardless of agent.
$withPromptInstr = @'
---
applyTo: "**"
description: A skill that should also emit a slash-invokable prompt
---

# Slash-invokable body.
'@
Set-Content (Join-Path $expectedDir '.github/instructions/example-with-prompt.instructions.md') $withPromptInstr

$withPromptPrompt = @'
---
description: A skill that should also emit a slash-invokable prompt
---

# Slash-invokable body.
'@
Set-Content (Join-Path $expectedDir '.github/prompts/example-with-prompt.prompt.md') $withPromptPrompt

# example-as-agent: ONLY .agent.md — the build script's `if ($emitAgent)` branch skips
# the .instructions.md emit (plan line 1066).
$asAgentAgent = @'
---
name: example-as-agent
description: A persistent persona, not an instruction file
---

# Persona body.
'@
Set-Content (Join-Path $expectedDir '.github/agents/example-as-agent.agent.md') $asAgentAgent

# ---- copilot-instructions.md preamble (plan line 1083) ----
$preamble = "# Copilot custom instructions`n`nThis repo's Copilot Chat instructions are generated from skills in ``plugins/pitt-skills/skills/``. See [README](../README.md) for usage."
Set-Content (Join-Path $expectedDir '.github/copilot-instructions.md') $preamble

# ---- JSON manifests ----
# IMPORTANT: PowerShell @{} hashtable iteration is non-deterministic. Task 21's plan uses @{},
# which means its output keys come out in random order — that breaks the idempotency test too.
# Task 21's implementer MUST switch to [ordered]@{} for deterministic output. We author these
# fixtures using [ordered]@{} with the documented intended insertion order: name, description,
# version, author for plugin.json; name, owner, plugins for marketplace.json.

$pluginManifest = [ordered]@{
    name = 'pitt-skills'
    description = "Justin Pitt's personal collection of Claude Code and Copilot skills"
    version = '0.1.0'
    author = [ordered]@{ name = 'Justin Pitt'; email = 'justin@pittnet.net' }
}
$pluginManifest | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $expectedDir 'plugins/pitt-skills/.claude-plugin/plugin.json')

$marketplace = [ordered]@{
    name = 'pitt-skills'
    owner = [ordered]@{ name = 'Justin Pitt'; email = 'justin@pittnet.net' }
    plugins = @([ordered]@{
        name = 'pitt-skills'
        source = './plugins/pitt-skills'
        description = "Justin Pitt's personal collection of Claude Code and Copilot skills"
    })
}
$marketplace | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $expectedDir '.claude-plugin/marketplace.json')

Write-Host "Fixtures written under $root"
