# pitt-skills

Justin Pitt's personal collection of Claude Code and Copilot skills, distributed as a Claude Code marketplace and (after Milestone 3) as Copilot Chat instructions.

## Quick install — paste into your AI assistant

### Universal prompt (works in any of: Claude Code, Copilot CLI, Copilot Chat, Copilot Desktop)

> Clone `https://github.com/justin-pitt/pitt-skills` into `~/Code/pitt-skills` (or `%USERPROFILE%\Code\pitt-skills` on Windows). After cloning, run `./scripts/install.ps1` on Windows or `./scripts/install.sh` on macOS/Linux. Show me the installer's summary output, then tell me which tools were detected and wired up. If anything failed, propose a fix before retrying.

Append one of these depending on your tool:
- **Claude Code:** "When done, also tell me to restart Claude Code so the new pitt-skills marketplace gets registered."
- **Copilot CLI:** "When done, run `/skills reload` and confirm pitt-skills entries appear."
- **VS Code Copilot Chat:** "When done, remind me to reload the VS Code window (Ctrl+Shift+P → Developer: Reload Window)."
- **Copilot Desktop App:** "When done, remind me to fully quit and reopen the Copilot desktop app."

## Manual install

```bash
git clone https://github.com/justin-pitt/pitt-skills ~/Code/pitt-skills
cd ~/Code/pitt-skills
pwsh ./scripts/install.ps1     # Windows
./scripts/install.sh           # macOS / Linux
```

## VS Code Chat — manual fallback (no symlinks)

If your environment blocks symlinks, add to your VS Code user settings.json:
```json
"chat.instructionsFilesLocations": ["${userHome}/Code/pitt-skills/.github/instructions"],
"chat.promptFilesLocations": ["${userHome}/Code/pitt-skills/.github/prompts"]
```

## What's inside

See [catalog/](catalog/) for the list of skills and the upstream marketplaces this repo points at.

## Authoring

See [docs/authoring-a-skill.md](docs/authoring-a-skill.md).

## License

MIT — see [LICENSE](LICENSE).
