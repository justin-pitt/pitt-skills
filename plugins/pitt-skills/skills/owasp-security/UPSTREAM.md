# Upstream source

- **Repo:** https://github.com/agamm/claude-code-owasp
- **Commit SHA at vendoring:** 41d16d86684e09ce69b946ce6dcd17ea9e9ce68a
- **Original license:** MIT
- **Vendored on:** 2026-04-29

## My changes

- Added YAML frontmatter (`name`, `description`, `license: MIT`) at the top of `SKILL.md` so the skill validates against Copilot CLI / marketplace tooling. Body content is byte-identical to upstream.
- The body of our `SKILL.md` is sourced from upstream's `OWASP-2025-2026-Report.md` (the substantive content), not from upstream's `.claude/skills/owasp-security/SKILL.md` (which is a thin wrapper that points at the report).
- The `description` field in our YAML frontmatter is author-written, since upstream's `OWASP-2025-2026-Report.md` had no frontmatter to copy.
