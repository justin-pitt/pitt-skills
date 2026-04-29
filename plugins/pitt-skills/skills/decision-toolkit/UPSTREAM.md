# Upstream source

- **Repo:** https://github.com/naveedharri/benai-skills (BenAI Skills marketplace)
- **Path within repo:** `plugins/meta/skills/decision-toolkit/` (SKILL.md + references/ + templates/)
- **Commit SHA at vendoring:** 8ae84980a677cc92f6f0b833061c9b1a8ac34ebb
- **Original license:** MIT (declared at repo root)
- **Vendored on:** 2026-04-29
- **Distribution context:** received as part of BenAI92's free Claude Code skills bundle (YouTube channel: https://www.youtube.com/@BenAI92, video: https://www.youtube.com/watch?v=bXnRA3pJavE). The MIT license on `naveedharri/benai-skills` covers the redistribution.

## My changes

- Added `license: MIT` to the YAML frontmatter so it validates against the Copilot CLI marketplace tooling. Upstream's frontmatter omits the field but the parent repo's top-level `LICENSE` is MIT.
- All other content (`SKILL.md` body, `references/bias-encyclopedia.md`, `references/framework-deep-dives.md`, `templates/decision-export-template.md`, `templates/decision-framework.md`, `templates/decision-guide-template.html`, `templates/decision-voice-summary.md`) is byte-identical to BenAI's distribution at the SHA above.

## Original-author attribution

Although vendored from `naveedharri/benai-skills` (which carries the redistributable MIT license), the actual content of this skill is byte-identical to https://github.com/glebis/claude-skills/tree/main/decision-toolkit. The `glebis/claude-skills` repo has no `LICENSE` file, which is why we vendor through BenAI's MIT-licensed redistribution rather than directly from glebis. Original-author credit goes to **glebis**; we redistribute under the MIT terms granted by BenAI.
