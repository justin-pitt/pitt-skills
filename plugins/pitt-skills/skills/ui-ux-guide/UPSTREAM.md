# Upstream source

- **Repo:** https://github.com/oil-oil/oiloil-ui-ux-guide
- **Commit SHA at vendoring:** 79afe4a7e035cdbffceeedc18cc623a159ff9b28
- **Original license:** Apache-2.0
- **Vendored on:** 2026-04-29

## My changes

- Added `license: Apache-2.0` to YAML frontmatter so the skill validates against Copilot CLI / marketplace tooling. Body content is byte-identical to upstream.
- Renamed frontmatter `name:` from `oiloil-ui-ux-guide` to `ui-ux-guide` so the YAML field matches the skill directory (Claude/Copilot skill resolvers key on this).
- Corrected the recorded license from MIT to Apache-2.0 to match the upstream `LICENSE.txt` file at the vendored SHA.
