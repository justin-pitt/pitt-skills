# pitt-skills

[![build](https://github.com/justin-pitt/pitt-skills/actions/workflows/build.yml/badge.svg)](https://github.com/justin-pitt/pitt-skills/actions/workflows/build.yml)
[![release](https://img.shields.io/github/v/release/justin-pitt/pitt-skills)](https://github.com/justin-pitt/pitt-skills/releases/latest)

Justin Pitt's personal collection of Claude Code and Copilot skills, distributed as a Claude Code marketplace, as Copilot Chat instructions, and as a Hermes skill bundle.

> **Already running Claude Code in a project folder?** Skip to [Quick install](#quick-install--paste-into-your-ai-assistant). Otherwise, see [First time using Claude Code? Start here](#first-time-using-claude-code-start-here) below.

## First time using Claude Code? Start here

If you've never used a coding AI assistant before, do these five steps in order. None of them need git, Python, or PowerShell — just Claude Code itself.

1. **Install Node.js** from [nodejs.org](https://nodejs.org/). Pick the LTS version, run the installer, accept the defaults.
   *Don't have an Anthropic API key but have access to GitHub Copilot through work? See [claude-code-over-github-copilot](https://github.com/justin-pitt/claude-code-over-github-copilot) first — it lets you run Claude Code through your Copilot subscription.*
2. **Install Claude Code.** Open a terminal (Command Prompt or PowerShell on Windows; Terminal on Mac/Linux) and run:
   ```
   npm install -g @anthropic-ai/claude-code
   ```
3. **Make a project folder anywhere on your machine, then `cd` into it.** Claude Code is per-folder — it remembers context for whichever folder you start it in. A throwaway folder for trying things out is fine:
   ```
   mkdir ~/Code/pitt-skills-host
   cd ~/Code/pitt-skills-host
   ```
   On Windows in Command Prompt, use `mkdir %USERPROFILE%\Code\pitt-skills-host` then `cd /d %USERPROFILE%\Code\pitt-skills-host`.
4. **Start Claude Code** by running `claude` from inside that folder. You'll see the chat prompt.
5. **In the Claude Code chat, type these two slash commands one at a time:**
   ```
   /plugin marketplace add https://github.com/justin-pitt/pitt-skills.git
   /plugin install pitt-skills@pitt-skills
   ```
   Then `/exit` and start `claude` again. Skills are now available in any folder you start Claude Code in.

**Want Copilot CLI, VS Code Copilot Chat, or Hermes wired up too?** Once Claude Code is working, paste the [universal install prompt](#universal-prompt-works-in-any-of-claude-code-copilot-cli-copilot-chat-copilot-desktop-hermes) below into the chat — Claude Code will install any extra prerequisites (git, PowerShell 7, etc.) and wire those tools up too.

## Quick install — paste into your AI assistant

### Universal prompt (works in any of: Claude Code, Copilot CLI, Copilot Chat, Copilot Desktop, Hermes)

> Clone `https://github.com/justin-pitt/pitt-skills` into `~/Code/pitt-skills` (or `%USERPROFILE%\Code\pitt-skills` on Windows). After cloning, run `./scripts/install.ps1` on Windows or `./scripts/install.sh` on macOS/Linux. Show me the installer's summary output, then tell me which tools were detected and wired up. If anything failed, propose a fix before retrying.

Append one of these depending on your tool:
- **Claude Code:** "When done, also tell me to restart Claude Code so the new pitt-skills marketplace gets registered."
- **Copilot CLI:** "When done, run `/skills reload` and confirm pitt-skills entries appear."
- **VS Code Copilot Chat:** "When done, remind me to reload the VS Code window (Ctrl+Shift+P → Developer: Reload Window)."
- **Copilot Desktop App:** "When done, remind me to fully quit and reopen the Copilot desktop app."
- **Hermes:** "When done, remind me that the new skills are auto-discovered under `pitt-skills/<skill>` on the next message — no restart needed."

## Manual install

```bash
git clone https://github.com/justin-pitt/pitt-skills ~/Code/pitt-skills
cd ~/Code/pitt-skills
pwsh ./scripts/install.ps1     # Windows
./scripts/install.sh           # macOS / Linux
```

To remove the wiring later, pass `-Uninstall` (PowerShell) or `--uninstall` (Bash). It removes the symlinks and strips the `pitt-skills` keys from `settings.json`, leaving everything else alone.

## Updating

New installs always pull the latest. Existing installs need a refresh when a new version ships:

- **Claude Code**: `/plugin marketplace update pitt-skills`, then restart any open sessions. Without this, Claude Code keeps reading from the cache directory that was populated at first install (`~/.claude/plugins/cache/pitt-skills/pitt-skills/<version>/`) and never sees the new content.
- **Copilot CLI**: `git -C ~/Code/pitt-skills pull`. The `~/.copilot/instructions/` symlink points at the cloned working copy, so a checkout refresh is all that's needed.
- **Hermes**: `git -C ~/Code/pitt-skills pull`. Same as Copilot CLI — the `<HERMES_HOME>/skills/pitt-skills` symlink points at the cloned working copy. Hermes auto-discovers on the next message, no restart needed.

## Troubleshooting

### SSH host-key error during `/plugin marketplace add` or `/plugin install`

If you see:
```
Failed to clone marketplace repository: SSH host key is not in your known_hosts file.
No ED25519 host key is known for github.com and you have requested strict checking.
```

You're using an old shorthand that resolves to SSH. Two ways to fix:

**Recommended — use the HTTPS URL form:**
```
/plugin marketplace add https://github.com/justin-pitt/pitt-skills.git
```

That's the form documented above and it skips SSH entirely.

**Alternative — accept GitHub's SSH host key once:**
```bash
ssh-keyscan -t ed25519,rsa github.com >> ~/.ssh/known_hosts
```

That writes GitHub's host keys non-interactively. Then retry the marketplace add. (Some users prefer this if they reuse SSH for other GitHub auth.)

### I already added the marketplace via the old SSH shorthand — how do I switch to HTTPS?

Edit `~/.claude/settings.json` directly. Find the `extraKnownMarketplaces.pitt-skills` entry and change its `source` block from the SSH form (often `{"source": "github", "repo": "justin-pitt/pitt-skills"}`) to:

```json
"pitt-skills": {
  "source": { "source": "git", "url": "https://github.com/justin-pitt/pitt-skills.git" }
}
```

Then refresh the marketplace catalog:
```
/plugin marketplace update pitt-skills
```

Your enabled plugins persist across the URL change — `enabledPlugins` is keyed by `<plugin>@<marketplace-name>`, not by the URL.

### Other issues

If a plugin's hook or setup script doesn't behave correctly, check:
- The hook file is at `~/.claude/hooks/<name>.sh` and is executable (`chmod +x`)
- `~/.claude/settings.json` has the corresponding `"hooks"` entry
- Per-skill `setup.sh` / `setup.ps1` (where shipped) is the canonical install path — re-run it idempotently

## VS Code Chat — manual fallback (no symlinks)

If your environment blocks symlinks, add to your VS Code user settings.json:
```json
"chat.instructionsFilesLocations": ["${userHome}/Code/pitt-skills/.github/instructions"],
"chat.promptFilesLocations": ["${userHome}/Code/pitt-skills/.github/prompts"]
```

## What's inside

See [catalog/](catalog/) for the list of skills and the upstream marketplaces this repo points at.

Includes 14 skills vendored from [obra/superpowers](https://github.com/obra/superpowers) by Jesse Vincent (MIT). Claude Code users also get the live upstream marketplace via the install script; Copilot users use the vendored snapshot.

## Authoring

See [docs/authoring-a-skill.md](docs/authoring-a-skill.md).

## Contributing

After cloning, enable the build-verify pre-commit hook so SKILL.md edits never ship without their regenerated Copilot mirrors:

```bash
git config core.hooksPath .githooks
```

The hook needs `pwsh` 7+ on `PATH` (or at one of the standard Windows install locations). Skip it for an individual commit with `git commit --no-verify`.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).
