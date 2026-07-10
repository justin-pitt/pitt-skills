# README "First time using Claude Code? Start here" — design

**Status:** approved 2026-05-02 (brainstorm phase complete)
**Branch:** `docs/readme-first-time-section` (off main)
**Trigger:** Justin's brother tried installing pitt-skills, got stuck because he didn't know Claude Code is per-folder and you have to start it inside a project directory.

## Goal

Add a clearly-titled "first time" onboarding section to README.md so a non-technical newcomer can go from "I just installed Claude Code" to "skills are wired up" without guessing at prerequisites.

## Approach

Docs-only. Add one new H2 section at the top of README.md (right after the H1 + tagline + badges), before "Quick install — paste into your AI assistant". Walks through the four prerequisites the existing flow assumes:

1. Install Claude Code (with link to Anthropic's official setup guide).
2. Make a project folder anywhere on the user's machine.
3. `cd` into the folder and run `claude`.
4. Paste the universal install prompt that's already in the README — anchor link forward to the existing section.

Add a one-line "Already running Claude Code in a project folder? Skip to [Quick install]" hint right after the tagline so experienced users aren't slowed down.

## Scope cap

- README.md changes only. No new files. No script changes. No version bump (no SKILL.md touched). No CHANGELOG entry — UX-doc, not a release-noted feature.
- No screenshots / GIFs — keeps the file portable.
- No "what is Claude Code" explainer — link to Anthropic's docs handles orientation.
- No per-OS branching beyond what Anthropic's install guide already covers.
- No troubleshooting / FAQ section — premature; expand only if the brother (or another newcomer) hits a *new* gap.
- No analogous "first time" sections for Copilot CLI / VS Code Chat / Hermes — Justin's brother specifically tried Claude Code, and the existing four audience hints already cover those tools' steady-state install. Adding parallel newcomer sections for all four would dilute focus.

## Content sketch

```markdown
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
```

The exact heading slug for the anchor link depends on the existing universal-prompt H3. Verify before final placement.

## Testing plan

Manual: hand the updated README to Justin's brother. He tries again. If he succeeds, ship as-is. If he hits a *new* snag, that becomes the next iteration.

## Out of scope

- A bootstrap one-liner script (option (b) from brainstorm). Justin chose docs-only because curl-pipe-bash is a tough sell to security-conscious coworkers.
- Detecting "no project folder" / pre-install doctor logic.
- Onboarding videos or asset-hosted screenshots.
- Per-audience first-time onboarding for Copilot / VS Code / Hermes.

## Open questions

None blocking. Proceed to writing-plans.
