# Upstream source

- **Repo:** https://github.com/obra/superpowers
- **Path within repo:** `skills/test-driven-development/`
- **Commit SHA at vendoring:** 2ce8aa15d05bd57213e6f746f953aafb7ded7a8b (refreshed 2026-11-03 from 6efe32c)
- **Original license:** MIT (Copyright 2025 Jesse Vincent — see https://github.com/obra/superpowers/blob/main/LICENSE)
- **Vendored on:** 2026-04-29

## My changes

- Added `license: MIT` to the frontmatter so the Copilot CLI marketplace validator accepts it. Upstream omits the field but the parent repo's `LICENSE` is MIT. The skill body and all other frontmatter fields are preserved verbatim.
- The bundle vendored from `skills/test-driven-development/` is byte-identical to upstream at the SHA above (apart from the frontmatter `license:` insertion noted above).
- Refreshed on 2026-11-03: re-vendored this skill alone from obra/superpowers v7.0.1. The other superpowers skills stay at 6efe32c because they carry local edits (see CHANGELOG 1.15.0) or would point at new executables. Frontmatter edits above re-applied; body byte-identical to upstream at the new SHA. Upstream renamed `testing-anti-patterns.md` to `writing-good-tests.md` and the new `SKILL.md` links it, so that companion file is vendored here too (byte-identical).
