# pitt-skills

Justin Pitt's personal collection of Claude Code and Copilot skills, distributed as a Claude Code marketplace and (after Milestone 3) as Copilot Chat instructions.

## Quick install

### For Claude Code

```
/plugin marketplace add justin-pitt/pitt-skills
/plugin install pitt-skills@pitt-skills
```

### For Copilot CLI / VS Code Copilot Chat

Clone the repo, then run the installer that matches your platform — it auto-detects which of `claude` / `copilot` / `code` is on `PATH` and wires up only what's installed:

```bash
# macOS / Linux
git clone https://github.com/justin-pitt/pitt-skills.git
./pitt-skills/scripts/install.sh
```

```powershell
# Windows
git clone https://github.com/justin-pitt/pitt-skills.git
pwsh ./pitt-skills/scripts/install.ps1
```

Pass `-Tools` / `--tools` (comma-separated: `claude`, `copilotCli`, `vscode`) to override auto-detection. Re-running is safe — the installer refuses to overwrite real directories at the symlink targets and backs up `~/.claude/settings.json` to `.bak` before merging.

A polished install guide with troubleshooting lands in M4.

## What's inside

See [catalog/](catalog/) for the list of skills and the upstream marketplaces this repo points at.

## Authoring

See [docs/authoring-a-skill.md](docs/authoring-a-skill.md).

## License

MIT — see [LICENSE](LICENSE).
