# Upstream source

- **Repo:** https://github.com/nextlevelbuilder/ui-ux-pro-max-skill
- **Path within repo:** `.claude/skills/ui-ux-pro-max/` (SKILL.md + data/ + references/ + scripts/)
- **Commit SHA at vendoring:** 713eef51b04efc98d6fa565323b495f7c9c89fd4 (plugin version 2.15.0)
- **Original license:** MIT (Copyright (c) 2024 Next Level Builder, see https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/blob/main/LICENSE)
- **Vendored on:** 2026-11-03

## Why this lives in vendor/ and not in the plugin

Upstream publishes this skill as a Claude Code marketplace (`ui-ux-pro-max@ui-ux-pro-max-skill`), and `settings.snippet.json` registers it, so Claude Code users get it live from upstream along with the six companion skills in that plugin (banner-design, brand, design, design-system, slides, ui-styling). A copy inside the pitt-skills plugin would list the skill twice, which is the same reason the superpowers snapshot moved to `vendor/superpowers/` in 1.25.0. Copilot and Hermes read this snapshot.

## My changes

- Added `license: MIT` to the YAML frontmatter so it validates against the Copilot CLI marketplace tooling. Upstream's frontmatter omits the field but the repo's `LICENSE` is MIT.
- Replaced `${CLAUDE_PLUGIN_ROOT}/.claude/skills/ui-ux-pro-max` with `<skill-dir>` in the 11 `search.py` command examples, and added one sentence defining `<skill-dir>` as the folder holding SKILL.md. The upstream path only resolves inside its own Claude Code plugin; Copilot and Hermes do not set `CLAUDE_PLUGIN_ROOT` and see the skill at a different path.
- Did not vendor `scripts/tests/` or `scripts/validate_data.py`. They are the maintainers' test suite and data validator; `search.py`, `core.py`, `design_system.py` and `reasoning_contract.py` do not import them.
- Everything else (`data/`, `references/`, the four runtime scripts) is byte-identical to upstream at the SHA above. The files are stored with LF endings and marked `-text` in `.gitattributes`, because upstream's `data/catalog-summary.json` records sha256 hashes over LF bytes.

## Refreshing

Re-extract from a clone with `git -c core.autocrlf=false archive <sha> .claude/skills/ui-ux-pro-max`, drop the two items above, then re-apply the frontmatter and path edits. `rg 'CLAUDE_PLUGIN_ROOT' vendor/ui-ux-pro-max` should come back empty afterwards.
