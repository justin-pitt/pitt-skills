#!/usr/bin/env bash
# scripts/install.sh - symlink-based installer for macOS / Linux
# Bash mirror of install.ps1. M3 wires up claude / copilotCli / vscode integrations.
# --what-if and --uninstall flags exist but are no-op for now (reserved for M4).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="claude,copilotCli,vscode"
WHATIF=0
UNINSTALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tools) TOOLS="$2"; shift 2 ;;
        --what-if) WHATIF=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ $WHATIF -eq 1 ]]; then
    echo "--what-if: not yet implemented (reserved for M4)" >&2
fi
if [[ $UNINSTALL -eq 1 ]]; then
    echo "--uninstall: not yet implemented (reserved for M4)" >&2
fi

merge_claude_settings() {
    local claude_home="${CLAUDE_HOME:-$HOME/.claude}"
    mkdir -p "$claude_home"
    local settings="$claude_home/settings.json"
    local snippet="$REPO_ROOT/settings.snippet.json"
    if [[ -f "$settings" ]]; then
        cp "$settings" "$settings.bak"
        # Merge via jq - preserves existing keys; snippet wins on conflict
        if ! jq -s '.[0] * .[1]' "$settings" "$snippet" > "$settings.tmp"; then
            rm -f "$settings.tmp"
            echo "Failed to merge $settings with $snippet. Original backed up at $settings.bak. Fix the JSON manually and re-run." >&2
            exit 1
        fi
        mv "$settings.tmp" "$settings"
    else
        cp "$snippet" "$settings"
    fi
    echo "Claude settings merged at $settings"
}

ensure_symlink() {
    local link="$1" target="$2"
    mkdir -p "$(dirname "$link")"
    if [[ -L "$link" ]]; then
        rm "$link"
    elif [[ -e "$link" ]]; then
        echo "Refusing to overwrite non-symlink at '$link'. Move or remove it manually, then re-run." >&2
        exit 1
    fi
    ln -s "$target" "$link"
}

install_copilot_cli() {
    ensure_symlink "$HOME/.copilot/skills" "$REPO_ROOT/plugins/pitt-skills/skills"
    echo "Copilot CLI: ~/.copilot/skills -> repo"
}

install_copilot_chat() {
    ensure_symlink "$HOME/.copilot/instructions" "$REPO_ROOT/.github/instructions"
    if [[ -d "$REPO_ROOT/.github/prompts" ]]; then
        ensure_symlink "$HOME/.copilot/prompts" "$REPO_ROOT/.github/prompts"
    fi
    echo "Copilot Chat: ~/.copilot/{instructions,prompts} -> repo"
}

IFS=',' read -ra TOOL_LIST <<< "$TOOLS"
for tool in "${TOOL_LIST[@]}"; do
    case "$tool" in
        claude)
            if command -v claude >/dev/null 2>&1; then
                merge_claude_settings
            else
                echo "claude not installed, skipping"
            fi
            ;;
        copilotCli) install_copilot_cli ;;
        vscode) install_copilot_chat ;;
        *) echo "Unknown tool '$tool' - skipping. Valid: claude, copilotCli, vscode" >&2 ;;
    esac
done

echo "Done."
