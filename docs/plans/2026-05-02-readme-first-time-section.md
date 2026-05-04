# README "First time using Claude Code? Start here" Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "First time using Claude Code? Start here" onboarding section to README.md so a non-technical newcomer can install Claude Code, make a project folder, and paste the universal install prompt without guessing at prerequisites.

**Architecture:** Pure docs. One new H2 section inserted near the top of README.md (after the H1/tagline/badges, before "Quick install — paste into your AI assistant"). One new "Already running Claude Code?" hint line right under the tagline so experienced users skip past.

**Tech Stack:** Markdown only. No code, no scripts, no tests.

**Reference design:** `docs/plans/2026-05-02-readme-first-time-section-design.md` (commit `8134db0`).

**Branch:** `docs/readme-first-time-section` (off main; design doc already committed there).

---

### Lessons that apply

- Justin's commit style: terse lowercase prefix (`docs: ...`).
- NEVER include "Claude" / "Co-Authored-By: Claude..." / "Generated with [Claude Code]" / robot emoji in commit messages or PR bodies.
- The version-bump CI rule won't fire on this PR (no `SKILL.md` changes).
- The pre-commit hook fires only when `plugins/pitt-skills/skills/*/SKILL.md` or `scripts/build.(ps1|sh)` is staged. README-only commits skip it.
- The repo's existing universal-prompt section heading is `### Universal prompt (works in any of: Claude Code, Copilot CLI, Copilot Chat, Copilot Desktop, Hermes)`. GitHub auto-generates anchor slugs from headings: lowercase, replace spaces and punctuation with hyphens, drop apostrophes/parentheses/colons/commas. The anchor for that heading should be `#universal-prompt-works-in-any-of-claude-code-copilot-cli-copilot-chat-copilot-desktop-hermes`. Verify by reading `README.md` and computing.

---

## Task 1: Edit README.md

**Files:**
- Modify: `c:\Code\pitt-skills\README.md`

**Step 1: Read README.md and confirm the universal-prompt H3 heading text**

Run a quick check to make sure the anchor target hasn't drifted since the design was written:

```bash
grep -n '^### Universal prompt' README.md
```

Expected: a single match, line near 10. The exact heading text is `### Universal prompt (works in any of: Claude Code, Copilot CLI, Copilot Chat, Copilot Desktop, Hermes)`. If the heading differs, recompute the anchor slug per GitHub's rules (lowercase, hyphens for spaces, drop punctuation).

**Step 2: Add the "skip to" hint right under the tagline**

Find this block in `README.md` (around lines 6–8):

```markdown
Justin Pitt's personal collection of Claude Code and Copilot skills, distributed as a Claude Code marketplace, as Copilot Chat instructions, and as a Hermes skill bundle.

## Quick install — paste into your AI assistant
```

Insert ONE new line between them so the result reads:

```markdown
Justin Pitt's personal collection of Claude Code and Copilot skills, distributed as a Claude Code marketplace, as Copilot Chat instructions, and as a Hermes skill bundle.

> **Already running Claude Code in a project folder?** Skip to [Quick install](#quick-install--paste-into-your-ai-assistant). Otherwise, see [First time using Claude Code? Start here](#first-time-using-claude-code-start-here) below.

## First time using Claude Code? Start here

If you've never used a coding AI assistant before, do these four steps in order:

1. **Install Claude Code** — see [Anthropic's install guide](https://docs.claude.com/en/docs/claude-code/setup). On Mac/Linux: `npm install -g @anthropic-ai/claude-code`. On Windows: same command in PowerShell after installing [Node.js](https://nodejs.org/).
2. **Make a project folder anywhere on your machine.** Claude Code is per-folder — it remembers context for whichever folder you start it in. A first-time folder for trying things out is fine:
   ```bash
   mkdir ~/Code/pitt-skills-host
   cd ~/Code/pitt-skills-host
   ```
3. **Start Claude Code** by running `claude` from inside that folder. You'll see the chat prompt.
4. **Paste the [universal install prompt](#universal-prompt-works-in-any-of-claude-code-copilot-cli-copilot-chat-copilot-desktop-hermes) below into the chat.** Claude Code will clone this repo, run the installer, and tell you what got wired up. Restart Claude Code when it tells you to.

That's it — your skills are now available in any folder you start Claude Code in.

## Quick install — paste into your AI assistant
```

Notes on the insertion:
- The blockquote line is the experienced-user shortcut. Two anchor links: forward to "Quick install" (the existing H2) and forward to the new H2 below it. Both links use GitHub's auto-generated anchor slugs.
- The new H2 is `## First time using Claude Code? Start here`. GitHub's auto-anchor for it: lowercase, drop the `?`, replace spaces with hyphens → `#first-time-using-claude-code-start-here`. (Note: GitHub drops a single trailing punctuation but keeps internal hyphens.)
- The fenced bash block inside step 2 needs to be indented 3 spaces (so it nests inside the numbered list item) — Markdown's "lazy continuation" requires the fence to align with the list-item content.

**Step 3: Verify anchor links resolve**

After saving, render-check by reading the file back. Run:

```bash
grep -n '## First time' README.md
grep -n '## Quick install' README.md
grep -n '### Universal prompt' README.md
```

Expected: each grep returns exactly one match. If any returns 0 or 2+, the structure is wrong — re-check.

Also visually confirm the four numbered steps appear under "First time using Claude Code? Start here" in the right order with the bash block correctly indented inside step 2.

**Step 4: Commit**

```bash
git add README.md
git commit -m "docs(readme): add first-time onboarding section for new Claude Code users"
```

---

## Task 2: Push and open PR

**Step 1: Push the branch**

```bash
git push -u origin docs/readme-first-time-section
```

**Step 2: Open the PR**

```bash
gh pr create --base main --head docs/readme-first-time-section --title "docs(readme): first-time onboarding section for new Claude Code users" --body "$(cat <<'EOF'
## Summary

Adds a "First time using Claude Code? Start here" section to the top of the README so a non-technical newcomer can go from "I just installed Claude Code" to "skills are wired up" without guessing at prerequisites.

Trigger: Justin's brother tried installing pitt-skills, got stuck because he didn't know Claude Code is per-folder and you have to start it inside a project directory.

## What it adds

- A four-step numbered list at the top of the README covering: install Claude Code, make a project folder, run \`claude\` inside it, paste the universal install prompt.
- A one-line "Already running Claude Code?" blockquote right under the tagline so experienced users skip past with one click.

## Out of scope

- A bootstrap one-liner script (rejected during brainstorm — curl-pipe-bash is a tough sell to security-conscious coworkers).
- Per-audience first-time onboarding for Copilot CLI / VS Code Chat / Hermes (the existing four audience hints already cover steady-state install).
- Screenshots, GIFs, troubleshooting / FAQ.

## Verify

- [ ] Justin's brother can follow the new section successfully end-to-end on his machine
- [ ] CI green (build / pester / bats / version-bump — no SKILL.md changes, version-bump won't fire)

## Plan + design

- Design: \`docs/plans/2026-05-02-readme-first-time-section-design.md\`
- Plan: \`docs/plans/2026-05-02-readme-first-time-section.md\`
EOF
)"
```

**Step 3: Watch CI**

```bash
gh pr checks <PR-number> --watch
```

All four jobs (build / pester / bats / version-bump) should pass. version-bump only runs on PRs and short-circuits when no `SKILL.md` files changed.

**Step 4: Stop**

Don't merge. Don't tag. Per Justin's pattern (per-memory `feedback_defer_release_tag_post_merge.md`), version tagging is post-merge and only happens when a numbered release is being cut — README-only changes don't trigger one.

---

## Notes for the executor

- This is a single-file docs change. No tests to write, no version bump, no script regen.
- The pre-commit hook (`.githooks/pre-commit`) doesn't fire for README-only commits — the hook only runs when `SKILL.md` or `scripts/build.(ps1|sh)` is staged.
- If the universal-prompt heading text in `README.md` has drifted since the design was written, recompute the anchor slug. GitHub's slug rules: lowercase, replace spaces with hyphens, drop punctuation (apostrophes, parentheses, colons, commas, question marks).
- If something about the bash block indentation is rendered wrong on GitHub, the fix is to indent the fence 3 spaces (matches the "1. " prefix + 2 spaces of body indent).
