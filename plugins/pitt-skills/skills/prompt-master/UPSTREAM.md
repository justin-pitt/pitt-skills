# Upstream source

- **Repo:** https://github.com/nidhinjs/prompt-master
- **Commit SHA at vendoring:** 49b3a72469b1e7287d66387004ccfcca90e5968a (refreshed 2026-11-03 from a4ebda7)
- **Original license:** MIT
- **Vendored on:** 2026-04-29

## My changes

- Added `license: MIT` to the YAML frontmatter of `SKILL.md` so it validates against the Copilot CLI marketplace tooling. Upstream's frontmatter omits the field but the repo's `LICENSE` file is MIT.
- All other content (`SKILL.md` body, `references/patterns.md`, `references/templates.md`) is byte-identical to upstream at the SHA above.
- Note: a stale local copy (v1.5.0) was sitting in `skills-audit/prompt-master/` before vendoring; the version that landed here is the latest upstream (v1.6.0), which adds Opus 4.7-specific guidance.
- Refreshed on 2026-11-03: upstream v1.6.0 to v1.8.2 (narrower activation description, new reference-editing, ComfyUI and Prompt Decompiler templates). Re-added `license: MIT`; `SKILL.md` body and both `references/` files are byte-identical to upstream.
