#!/usr/bin/env bash
# scripts/install.sh - symlink-based installer for macOS / Linux
# Bash mirror of install.ps1. Wires up claude / copilotCli / vscode integrations.
# --uninstall reverses the wiring (settings.json edits + symlink removal).
# --what-if is reserved for a future milestone and is currently a no-op.
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
    echo "--what-if: ignored; performing real action (planned for a future milestone)" >&2
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

remove_claude_settings() {
    local claude_home="${CLAUDE_HOME:-$HOME/.claude}"
    local settings="$claude_home/settings.json"
    if [[ ! -f "$settings" ]]; then
        echo "Claude settings: nothing to remove (no $settings)."
        return 0
    fi
    cp "$settings" "$settings.bak"
    # Only remove the pitt-skills entry. The other marketplaces in settings.snippet.json
    # (superpowers-dev, anthropic-agent-skills, superpowers-marketplace) reference upstream
    # marketplaces a user might want independently of this plugin - leave them alone.
    if ! jq '
            del(.extraKnownMarketplaces["pitt-skills"])
            | del(.enabledPlugins["pitt-skills@pitt-skills"])
            | if (.extraKnownMarketplaces // {}) == {} then del(.extraKnownMarketplaces) else . end
            | if (.enabledPlugins // {}) == {} then del(.enabledPlugins) else . end
        ' "$settings" > "$settings.tmp"; then
        rm -f "$settings.tmp"
        echo "Failed to edit $settings. Original backed up at $settings.bak. Fix the JSON manually and re-run." >&2
        exit 1
    fi
    mv "$settings.tmp" "$settings"
    echo "Claude settings: removed pitt-skills entries from $settings (backup at $settings.bak)."
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

remove_symlink() {
    local link="$1"
    if [[ -L "$link" ]]; then
        rm "$link"
        echo "  removed symlink $link"
    elif [[ -e "$link" ]]; then
        echo "Refusing to delete non-symlink at '$link'. Looks like real content; remove manually if intended." >&2
    fi
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

uninstall_copilot_cli() {
    remove_symlink "$HOME/.copilot/skills"
    echo "Copilot CLI: ~/.copilot/skills uninstalled"
}

uninstall_copilot_chat() {
    remove_symlink "$HOME/.copilot/instructions"
    remove_symlink "$HOME/.copilot/prompts"
    echo "Copilot Chat: ~/.copilot/{instructions,prompts} uninstalled"
}

IFS=',' read -ra TOOL_LIST <<< "$TOOLS"
for tool in "${TOOL_LIST[@]}"; do
    case "$tool" in
        claude)
            if command -v claude >/dev/null 2>&1; then
                if [[ $UNINSTALL -eq 1 ]]; then
                    remove_claude_settings
                else
                    merge_claude_settings
                fi
            else
                echo "claude not installed, skipping" >&2
            fi
            ;;
        copilotCli)
            if [[ $UNINSTALL -eq 1 ]]; then uninstall_copilot_cli; else install_copilot_cli; fi
            ;;
        vscode)
            if [[ $UNINSTALL -eq 1 ]]; then uninstall_copilot_chat; else install_copilot_chat; fi
            ;;
        *) echo "Unknown tool '$tool' - skipping. Valid: claude, copilotCli, vscode" >&2 ;;
    esac
done

echo "Done."
