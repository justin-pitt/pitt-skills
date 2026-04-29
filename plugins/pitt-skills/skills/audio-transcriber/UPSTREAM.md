# Upstream source

- **Repo:** https://github.com/sickn33/antigravity-awesome-skills
- **Path within repo:** `skills/audio-transcriber/` (SKILL.md + scripts/ + references/ + examples/)
- **Commit SHA at vendoring:** bae2be5a35e887e9d5cf2cda6cd0e66b06f3bfdd
- **Original license:** MIT
- **Vendored on:** 2026-04-29

## My changes

- Added `license: MIT` to the YAML frontmatter so it validates against the Copilot CLI marketplace tooling. Upstream's frontmatter omits the field but the parent repo's top-level `LICENSE` is MIT.
- Preserved the upstream's non-standard top-level frontmatter keys (`category`, `risk`, `source`, `tags`, `date_added`) verbatim — these are informational metadata from the upstream author. The pitt-skills build pipeline ignores fields it doesn't recognize, so they cause no harm.
- Vendored the SKILL.md plus the `scripts/`, `references/`, and `examples/` subdirectories (all byte-identical to upstream at the SHA above). Did not vendor the upstream's `README.md` and `CHANGELOG.md` since those documented authorship/version history that's now captured in this `UPSTREAM.md` and in pitt-skills' git log.
