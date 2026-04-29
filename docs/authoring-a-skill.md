# Authoring a skill

## Create a new skill

1. Use the `skill-creator` skill to scaffold:
   ```
   I want to write a new skill called <name>. <describe trigger>
   ```
   It creates `~/.claude/skills/<name>/SKILL.md`.
2. Author and test until satisfied.
3. Move into the repo:
   ```bash
   mv ~/.claude/skills/<name> plugins/pitt-skills/skills/<name>
   ```
4. Add `license: MIT` to frontmatter (Copilot CLI requires it).
5. Run `pwsh scripts/build.ps1`.
6. Bump `plugins/pitt-skills/.claude-plugin/plugin.json` version (or include `[skip-bump]` in commit).
7. Commit and push.

## Vendor a third-party skill

```bash
pwsh scripts/vendor-skill.ps1 `
  -Source ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/skills/<name> `
  -SkillName <name> `
  -UpstreamRepo <owner>/<repo> `
  -UpstreamSha <commit-sha>
```

Then edit `UPSTREAM.md` to record any changes you make.

## Frontmatter reference

```yaml
---
name: my-skill                          # required
description: One-line trigger desc.     # required
license: MIT                            # required (Copilot CLI validator)
allowed-tools: [Read, Write, Bash]      # optional
copilot-chat:                           # all optional
  applyTo: "**/*.ts,**/*.tsx"           # default: "**" (always-on)
  prompt: false                         # also emit a slash-invokable .prompt.md
  agent: false                          # emit a persistent .agent.md persona instead of .instructions.md
---
```
