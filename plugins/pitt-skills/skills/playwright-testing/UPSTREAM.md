# Upstream source

- **Repo:** https://github.com/testdino-hq/playwright-skill
- **Commit SHA at vendoring:** 815b86b3a02e29164a4a7288002559237860db5e
- **Original license:** MIT
- **Vendored on:** 2026-04-29

## My changes

- Renamed local skill folder from `playwright-skill` (upstream) to `playwright-testing` to match the standalone install already in use at `~/.claude/skills/playwright-testing/`. SKILL.md content is byte-identical to upstream.
- Added `license: MIT` to YAML frontmatter so the skill validates against Copilot CLI / marketplace tooling.
- Renamed frontmatter `name:` from `playwright-skill` to `playwright-testing` so the YAML field matches the skill directory (Claude/Copilot skill resolvers key on this).
- Vendored the full reference tree (core/, ci/, advanced/, etc.) at the recorded SHA so the SKILL.md hub-and-spokes links remain functional inside the plugin.
