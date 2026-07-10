# Upstream source

- **Repo:** https://github.com/vercel-labs/agent-browser
- **Path within repo:** `skill-data/core/` (SKILL.md + references/ + templates/)
- **Commit SHA at vendoring:** 7ada3384e2afb5f3c43d9106389da86d8f807dca
- **Original license:** Apache-2.0
- **Vendored on:** 2026-04-29

## My changes

- Renamed `name: core` → `name: agent-browser` in the YAML frontmatter so the skill name matches its directory and the install path users will refer to. The body and all other frontmatter fields are preserved verbatim.
- Added `license: Apache-2.0` to the frontmatter so it validates against the Copilot CLI marketplace tooling. Upstream's frontmatter omits the field but the parent repo's top-level `LICENSE` is Apache-2.0.
- The bundle vendored from `skill-data/core/` (8 reference files, 3 template scripts) is byte-identical to upstream at the SHA above. Note: the upstream also ships a separate, top-level `skills/agent-browser/SKILL.md` which is a thin entry-point variant (`hidden: true`); we did not vendor that one — `skill-data/core/` is the substantive guide.
- Note: a pre-vendoring local copy in `skills-audit/agent-browser/` was a hybrid of both upstream variants and was missing `references/trust-boundaries.md`; this canonical bundle includes it.
