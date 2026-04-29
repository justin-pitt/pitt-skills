# Upstream source

- **Repo:** https://github.com/rawveg/skillsforge-marketplace
- **Path within repo:** `openrouter/` (SKILL.md + plugin.json + references/)
- **Commit SHA at vendoring:** 9561ce20885bada1d6012d24d9b598d69c097ef2
- **Original license:** MIT (declared in this skill's own `plugin.json`)
- **Vendored on:** 2026-04-29

## My changes

- Added `license: MIT` to the YAML frontmatter of `SKILL.md` so it validates against the Copilot CLI marketplace tooling. Upstream's `SKILL.md` frontmatter omits the field, but the skill's own `plugin.json` declares `"license": "MIT"`.
- All content (`SKILL.md` body, `plugin.json`, `references/index.md`, `references/llms.md`, `references/llms-small.md`, `references/llms-full.md`, `references/other.md`) is byte-identical to upstream at the SHA above.

## License note

The parent repository `rawveg/skillsforge-marketplace` does not have a top-level `LICENSE` file — GitHub's license API returns no SPDX identifier for the repo. The MIT declaration we honor here comes from this individual skill's `plugin.json`, which is the author's explicit license intent for this skill. The skill's original author per `plugin.json` is Tim Green (`rawveg@gmail.com`).

The earlier name of this marketplace was `rawveg/claude-skills-marketplace` (now 404 — the repo was renamed to `skillsforge-marketplace`).
