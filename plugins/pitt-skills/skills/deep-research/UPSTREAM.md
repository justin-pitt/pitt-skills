# Upstream source

- **Repo:** https://github.com/naveedharri/benai-skills (BenAI Skills marketplace)
- **Path within repo:** `plugins/meta/skills/deep-research/` (SKILL.md + CHANGELOG.md + references/ + scripts/ + assets/)
- **Commit SHA at vendoring:** 8ae84980a677cc92f6f0b833061c9b1a8ac34ebb
- **Original license:** MIT (declared at repo root)
- **Vendored on:** 2026-04-29
- **Distribution context:** received as part of BenAI92's free Claude Code skills bundle (YouTube channel: https://www.youtube.com/@BenAI92, video: https://www.youtube.com/watch?v=bXnRA3pJavE). The MIT license on `naveedharri/benai-skills` covers the redistribution.

## My changes

- Added `license: MIT` to the YAML frontmatter so it validates against the Copilot CLI marketplace tooling. Upstream's frontmatter omits the field but the parent repo's top-level `LICENSE` is MIT.
- **2026-05-08 — vendor-agnostic refactor (v3.0).** Significant divergence from upstream. The skill no longer hard-codes the OpenAI Deep Research API. `assets/deep_research.py` is rewritten to dispatch through one of three provider backends (OpenAI, Anthropic Messages with `web_search`, Perplexity `sonar-deep-research`). Provider is selected via `--provider`, `DEEP_RESEARCH_PROVIDER`, or auto-detected from which API key is set. SDK imports are lazy. `scripts/run_deep_research.py` gained `--provider`, dropped its hard-coded `o4-mini-deep-research` default. `SKILL.md`, `references/workflow.md`, and `CHANGELOG.md` updated accordingly. See `CHANGELOG.md` v3.0 for the full diff and migration notes.

## Original-author attribution

Although vendored from `naveedharri/benai-skills` (which carries the redistributable MIT license), the actual content of this skill is byte-identical to https://github.com/glebis/claude-skills/tree/main/deep-research. The `glebis/claude-skills` repo has no `LICENSE` file, which is why we vendor through BenAI's MIT-licensed redistribution rather than directly from glebis. Original-author credit goes to **glebis**; we redistribute under the MIT terms granted by BenAI.
