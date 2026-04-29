# M2 Migration Checklist

> Source-of-truth inventory for the 8 skills being ported into `plugins/pitt-skills/skills/` during Milestone 2 of the marketplace plan. Delete this file at the end of M2.

## Inventory

| Skill | Author-modified? | Upstream repo | Upstream commit SHA |
|---|---|---|---|
| `owasp-security` | no | https://github.com/agamm/claude-code-owasp.git | `41d16d86684e09ce69b946ce6dcd17ea9e9ce68a` |
| `playwright-testing` | no | https://github.com/testdino-hq/playwright-skill.git | `815b86b3a02e29164a4a7288002559237860db5e` |
| `ui-ux-guide` | no | https://github.com/oil-oil/oiloil-ui-ux-guide.git | `79afe4a7e035cdbffceeedc18cc623a159ff9b28` |
| `vibesec` | no | https://github.com/BehiSecc/VibeSec-Skill.git | `0590993b35ad51961f65a4d01cf1196dfead05bb` |
| `webapp-testing` | no | https://github.com/anthropics/skills.git | `b0cbd3df1533b396d281a6886d5132f623393a9c` |
| `cortex-xsiam` | N/A | (none — author-original) | — |
| `tines` | N/A | (none — author-original) | — |
| `tufin` | N/A | (none — author-original) | — |

`threatconnect-polarity` is excluded — already ported as the M1 canary (commits `c2fea3a`, `87a9f0c`).

## Per-skill notes

### `owasp-security`
- **Upstream local clone:** `c:/Code/claude-skills/owasp-security/` (tracks `https://github.com/agamm/claude-code-owasp.git`)
- **Upstream file:** `OWASP-2025-2026-Report.md` (the repo's `SKILL.md` is unconventionally named after the report)
- **Diff vs `~/.claude/skills/owasp-security/SKILL.md`:** byte-identical (792 lines, no diff output). Not author-modified — port to the catalog without `UPSTREAM.md`.

### `playwright-testing`
- **Upstream local clone:** `c:/Code/claude-skills/playwright-skill/` (tracks `https://github.com/testdino-hq/playwright-skill.git`)
- **Upstream file:** `SKILL.md` at repo root
- **Diff vs `~/.claude/skills/playwright-testing/SKILL.md`:** byte-identical (no diff output). Not author-modified. Note: standalone is named `playwright-testing` while upstream repo is `playwright-skill`; only the local skill folder name differs from upstream repo name. Port without `UPSTREAM.md`.

### `ui-ux-guide`
- **Upstream local clone:** `c:/Code/claude-skills/ui-ux-guide/` (tracks `https://github.com/oil-oil/oiloil-ui-ux-guide.git`)
- **Upstream file:** `skills/oiloil-ui-ux-guide/SKILL.md`
- **Diff vs `~/.claude/skills/ui-ux-guide/SKILL.md`:** byte-identical (no diff output). Not author-modified. Port without `UPSTREAM.md`.

### `vibesec`
- **Upstream local clone:** `c:/Code/claude-skills/vibesec/` (tracks `https://github.com/BehiSecc/VibeSec-Skill.git`)
- **Upstream file:** `SKILL.md` at repo root
- **Diff vs `~/.claude/skills/vibesec/SKILL.md`:** byte-identical (no diff output). Not author-modified. Port without `UPSTREAM.md`.

### `webapp-testing`
- **Upstream local clone:** `c:/Code/claude-skills/anthropic-skills/` (tracks `https://github.com/anthropics/skills.git`)
- **Upstream file:** `skills/webapp-testing/SKILL.md`
- **Diff vs `~/.claude/skills/webapp-testing/SKILL.md`:** byte-identical (no diff output). Not author-modified. Last-touching commit for the file specifically: `ef740771ac901e03fbca3ce4e1c453a96010f30a`; HEAD listed in the table is the repo head. Port without `UPSTREAM.md`.

### `cortex-xsiam`, `tines`, `tufin`
- Author-original skills (Justin's own work). Not vendored from any upstream repository.
- Standalone source: `~/.claude/skills/<name>/SKILL.md` (and any sibling files in those directories).
- Ported under Tasks 16a/b/c without `UPSTREAM.md` (no upstream to track).

## Vendoring decision summary

All 5 upstream-derived skills (`owasp-security`, `playwright-testing`, `ui-ux-guide`, `vibesec`, `webapp-testing`) are byte-identical to their upstreams. Per the plan (Task 17 + line 421 of `2026-04-28-pitt-skills-marketplace.md`), **none of them require an `UPSTREAM.md`**. The plan's "skip unmodified — reference don't vendor" rule applies — they go in `catalog/upstream.md` (Task 17) rather than being copied into `plugins/pitt-skills/skills/`.

The 3 author-original skills (`cortex-xsiam`, `tines`, `tufin`) are first-party content; they get vendored under Tasks 16a/b/c without `UPSTREAM.md` and have no catalog entry.

If, during the per-skill port tasks, an executor finds a delta missed here (e.g., line-ending or whitespace differences `diff -q` flagged as identical), they should re-run a byte-level comparison and update this file before committing the port.
