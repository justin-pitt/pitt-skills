# Upstream source

- **Repo:** https://github.com/BehiSecc/VibeSec-Skill
- **Commit SHA at vendoring:** 0590993b35ad51961f65a4d01cf1196dfead05bb
- **Original license:** Apache-2.0
- **Vendored on:** 2026-04-29

## My changes

- Added `license: Apache-2.0` to YAML frontmatter so the skill validates against Copilot CLI / marketplace tooling. Body content is byte-identical to upstream.
- Renamed frontmatter `name:` from `VibeSec-Skill` to `vibesec` so the YAML field matches the skill directory (Claude/Copilot skill resolvers key on this).
- Corrected the recorded license from MIT to Apache-2.0 to match the upstream `LICENSE` file at the vendored SHA.
