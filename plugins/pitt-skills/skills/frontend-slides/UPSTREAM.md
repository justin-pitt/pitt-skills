# Upstream source

- **Repo:** https://github.com/affaan-m/everything-claude-code
- **Path within repo:** `.agents/skills/frontend-slides/` (SKILL.md + STYLE_PRESETS.md)
- **Commit SHA at vendoring:** c7c7d37f2946d7497577408d19adaee6a8341ddc
- **Original license:** MIT
- **Vendored on:** 2026-04-29

## My changes

- Added `license: MIT` to the YAML frontmatter so it validates against the Copilot CLI marketplace tooling. Upstream's frontmatter omits the field but the parent repo's top-level `LICENSE` is MIT.
- All content (`SKILL.md` body and `STYLE_PRESETS.md`) is byte-identical to upstream at the SHA above.
- Note: a pre-vendoring local copy in `skills-audit/frontend-slides/` carried a non-standard `origin: ECC` frontmatter key (referring to "Everything Claude Code" — the upstream repo's name); that key was dropped here since upstream doesn't carry it.
