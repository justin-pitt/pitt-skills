# Upstream source

- **Repo:** https://github.com/naveedharri/benai-skills (BenAI Skills marketplace)
- **Path within repo:** `plugins/meta/skills/process-interviewer/` (SKILL.md + references/)
- **Commit SHA at vendoring:** 8ae84980a677cc92f6f0b833061c9b1a8ac34ebb
- **Original license:** MIT (declared at repo root)
- **Vendored on:** 2026-04-29
- **Distribution context:** received as part of BenAI92's free Claude Code skills bundle (YouTube channel: https://www.youtube.com/@BenAI92, video: https://www.youtube.com/watch?v=bXnRA3pJavE). The MIT license on `naveedharri/benai-skills` covers the redistribution.

## My changes

- Added `license: MIT` to the YAML frontmatter so it validates against the Copilot CLI marketplace tooling. Upstream's frontmatter omits the field but the parent repo's top-level `LICENSE` is MIT.
- All other content (`SKILL.md` body, `references/plan-output-template.md`, `references/skill-output-template.md`) is byte-identical to BenAI's distribution at the SHA above.

## Original-author attribution

The original author of this skill could not be conclusively identified. The same content surfaces publicly as rendered HTML on `dmwasielewski/portfolio` (a Quartz-built personal portfolio site at https://www.dmwasielewski.me/braindump/11-AI-skills/meta-skills/process-interviewer/), but no markdown source repo from that author was located. We vendor through BenAI's MIT-licensed redistribution and credit BenAI's bundle as the immediate source. If the original author is identified later, attribution should be amended here.
