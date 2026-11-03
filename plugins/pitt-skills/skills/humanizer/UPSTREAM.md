# Upstream source

- **Repo:** https://github.com/blader/humanizer
- **Commit SHA at vendoring:** 0ef9fe5bc3572734fd3ae6c448fe00a30cd5dcf0 (refreshed 2026-11-03 from 8b3a178)
- **Original license:** MIT
- **Vendored on:** 2026-04-29

## My changes

- None. `SKILL.md` is byte-identical to upstream `SKILL.md` at the SHA above.
- Note: a stale local copy (v2.1.1) was sitting in `skills-audit/humanizer/` before vendoring; the version that landed here is the latest upstream (v2.5.1), which adds a "final anti-AI pass" step and a "Voice Calibration" section.
- Refreshed on 2026-11-03: upstream v2.5.1 to v3.1.0 (rewritten pattern list, version moved under metadata, `compatibility` and `allowed-tools` dropped upstream). `SKILL.md` is still byte-identical to upstream; upstream now carries `license: MIT` itself. Upstream also became a Claude Code plugin; only `SKILL.md` is vendored.
