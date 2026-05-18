---
name: playwright-core
description: Internal sub-index for the Playwright core reference guides. Use the parent playwright-testing skill instead.
user-invocable: false
disable-model-invocation: true
---

# playwright-core (sub-index)

This file used to be a near-duplicate of the parent `playwright-testing/SKILL.md` index. It is kept as a tiny alias only so existing links into `core/SKILL.md` keep resolving.

## Where the content lives

The canonical Playwright skill is the parent: [`../SKILL.md`](../SKILL.md). Every reference markdown file in this `core/` folder is already linked from there (see the "Writing Tests", "Debugging & Fixing", "Framework Recipes", and "Specialized Topics" tables in the parent index).

## What to do

- If you reached here from a parent-skill link, open the specific reference file you intended (e.g. `locators.md`, `assertions-and-waiting.md`).
- If you reached here looking for the Playwright skill itself, invoke `playwright-testing` instead.

The `disable-model-invocation` and `user-invocable: false` frontmatter prevent Claude from auto-firing this stub or showing it in the `/` menu.
