# Upstream source

- **Repo:** https://github.com/obra/superpowers
- **Path within repo:** `skills/dispatching-parallel-agents/`
- **Commit SHA at vendoring:** 6efe32c9e2dd002d0c394e861e0529675d1ab32e
- **Original license:** MIT (Copyright 2025 Jesse Vincent — see https://github.com/obra/superpowers/blob/main/LICENSE)
- **Vendored on:** 2026-04-29

## My changes

- Added `license: MIT` to the frontmatter so the Copilot CLI marketplace validator accepts it. Upstream omits the field but the parent repo's `LICENSE` is MIT. The skill body and all other frontmatter fields are preserved verbatim.
- The bundle vendored from `skills/dispatching-parallel-agents/` is byte-identical to upstream at the SHA above (apart from the frontmatter `license:` insertion noted above).
