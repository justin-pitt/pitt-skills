# Upstream marketplaces I rely on

This file is a curated list of upstream Claude Code marketplaces I trust and recommend, but do not redistribute through pitt-skills directly. Their plugins are installed unmodified from their original sources, so any updates flow through normally without going through this repo. The `settings.snippet.json` (registered by `scripts/install.ps1`) wires these marketplaces in automatically on a fresh machine.

## obra/superpowers

A workflow-focused marketplace by Jesse Vincent (obra) covering core Claude Code development practices: brainstorming, writing-plans, executing-plans, test-driven development, systematic debugging, code review, finishing branches, working with git worktrees, and more. These are the day-to-day "how to drive Claude Code well" skills.

```
/plugin marketplace add obra/superpowers
/plugin install superpowers@superpowers-dev
```

## anthropics/skills

Anthropic's official skills marketplace. Provides: `docx`, `pdf`, `pptx`, `xlsx`, `frontend-design`, `skill-creator`, `mcp-builder`, `claude-api`, `webapp-testing`, and other document/artifact authoring skills.

Note: `webapp-testing` was deferred here per M2's hybrid vendoring policy. Rather than vendor a copy of Anthropic's `webapp-testing` skill into pitt-skills, I install it directly from this upstream so it stays current with Anthropic's updates. The browser-testing skill I do vendor (`playwright-testing`) is vendored from a separate non-Anthropic upstream (`testdino-hq/playwright-skill`); see its `UPSTREAM.md` for attribution.

```
/plugin marketplace add anthropics/skills
/plugin install document-skills@anthropic-agent-skills
/plugin install claude-api@anthropic-agent-skills
```

## obra/superpowers-marketplace

A companion marketplace to `obra/superpowers` that hosts adjacent plugins. Provides: `elements-of-style` (Strunk-style writing review), `claude-session-driver` (multi-session orchestration), and `superpowers-developing-for-claude-code` (Claude Code plugin/hook/MCP authoring guidance).

```
/plugin marketplace add obra/superpowers-marketplace
```
