# Upstream source

- **Repo:** https://github.com/ComposioHQ/awesome-claude-skills
- **Path within repo:** `file-organizer/SKILL.md`
- **Commit SHA at vendoring:** 337b19e0ed1260790cdfa9c5229e74db2dc6c811
- **Original license:** Apache-2.0
- **Vendored on:** 2026-04-29

## My changes

- Added `license: Apache-2.0` to the YAML frontmatter so it validates against the Copilot CLI marketplace tooling. Upstream's frontmatter omits the field; the parent repo's `README.md` declares Apache-2.0 via badge (no top-level `LICENSE` file is present, which is why GitHub's license API returns nothing — but the README is unambiguous).
- All other content is byte-identical to upstream at the SHA above.
