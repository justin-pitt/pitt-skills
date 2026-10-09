#!/usr/bin/env bash
# scripts/install.sh - symlink-based installer for macOS / Linux
# Bash mirror of install.ps1. Wires up claude / copilotCli / vscode / hermes integrations.
# --uninstall reverses the wiring (settings.json edits + symlink removal).
# --what-if is reserved for a future milestone and is currently a no-op.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="claude,copilotCli,vscode,hermes"
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

# Every skill Copilot CLI should see: the plugin's own skills and the vendored superpowers
# snapshot, which lives outside the plugin so Claude Code does not load it twice.
copilot_skill_dirs() {
    local dir skill
    for dir in "$REPO_ROOT/plugins/pitt-skills/skills" "$REPO_ROOT/vendor/superpowers"; do
        if [[ -d "$dir" ]]; then
            for skill in "$dir"/*/; do
                if [[ -d "$skill" ]]; then
                    echo "${skill%/}"
                fi
            done
        fi
    done
}

# True when $1 is a symlink whose target is inside this repo.
links_into_repo() {
    [[ -L "$1" ]] && [[ "$(readlink "$1")" == "$REPO_ROOT"/* ]]
}

install_copilot_cli() {
    # Copilot CLI finds skills one folder below ~/.copilot/skills, and they come from two repo
    # folders, so ~/.copilot/skills is a real directory holding one link per skill. Earlier
    # releases linked the whole directory to the repo; that link is replaced here.
    local skills_home="$HOME/.copilot/skills" skill name
    local -a skills=() conflicts=() current=()
    while IFS= read -r skill; do
        skills+=("$skill")
    done < <(copilot_skill_dirs)

    if [[ -L "$skills_home" ]]; then
        rm "$skills_home"
    elif [[ -d "$skills_home" ]]; then
        # A real directory may hold the user's own skills. Refuse before changing anything if
        # one of them has the name of a pitt-skills skill.
        for skill in "${skills[@]}"; do
            name="$(basename "$skill")"
            if [[ -e "$skills_home/$name" && ! -L "$skills_home/$name" ]]; then
                conflicts+=("$name")
            fi
        done
        if [[ ${#conflicts[@]} -gt 0 ]]; then
            echo "Refusing to overwrite non-symlink skill folder(s) in '$skills_home': ${conflicts[*]}. Move or remove them manually, then re-run." >&2
            exit 1
        fi
    fi
    mkdir -p "$skills_home"

    for skill in "${skills[@]}"; do
        name="$(basename "$skill")"
        current+=("$name")
        ensure_symlink "$skills_home/$name" "$skill"
    done

    # Drop links into this repo for skills that no longer exist, such as a renamed skill.
    for skill in "$skills_home"/*; do
        if links_into_repo "$skill" && [[ ! " ${current[*]} " == *" $(basename "$skill") "* ]]; then
            rm "$skill"
        fi
    done
    echo "Copilot CLI: ${#skills[@]} skill links in ~/.copilot/skills -> repo"
}

install_copilot_chat() {
    ensure_symlink "$HOME/.copilot/instructions" "$REPO_ROOT/.github/instructions"
    if [[ -d "$REPO_ROOT/.github/prompts" ]]; then
        ensure_symlink "$HOME/.copilot/prompts" "$REPO_ROOT/.github/prompts"
    fi
    echo "Copilot Chat: ~/.copilot/{instructions,prompts} -> repo"
}

uninstall_copilot_cli() {
    # Removes the per-skill links that point into this repo, then ~/.copilot/skills itself if
    # nothing else is left in it. The user's own skills and files are never touched.
    local skills_home="$HOME/.copilot/skills" entry removed=0
    if [[ -L "$skills_home" ]]; then
        # The whole-directory link an earlier release created.
        remove_symlink "$skills_home"
        echo "Copilot CLI: ~/.copilot/skills uninstalled"
        return 0
    fi
    if [[ ! -d "$skills_home" ]]; then
        echo "Copilot CLI: ~/.copilot/skills absent"
        return 0
    fi
    for entry in "$skills_home"/*; do
        if links_into_repo "$entry"; then
            rm "$entry"
            removed=$((removed + 1))
        fi
    done
    if rmdir "$skills_home" 2>/dev/null; then
        echo "Copilot CLI: removed $removed skill link(s) and the empty ~/.copilot/skills"
    else
        echo "Copilot CLI: removed $removed skill link(s); kept ~/.copilot/skills because it holds other content." >&2
    fi
}

uninstall_copilot_chat() {
    remove_symlink "$HOME/.copilot/instructions"
    remove_symlink "$HOME/.copilot/prompts"
    echo "Copilot Chat: ~/.copilot/{instructions,prompts} uninstalled"
}

install_hermes() {
    # Hermes auto-discovers SKILL.md files recursively under ~/.hermes/skills/.
    # Mounting the plugin's skills dir as ~/.hermes/skills/pitt-skills gives
    # users a `pitt-skills/<name>` namespace that won't collide with any of
    # their own skills. HERMES_HOME is honored for non-default installs.
    local hermes_home="${HERMES_HOME:-$HOME/.hermes}"
    ensure_symlink "$hermes_home/skills/pitt-skills" "$REPO_ROOT/plugins/pitt-skills/skills"
    echo "Hermes: $hermes_home/skills/pitt-skills -> repo"
    # The vendored superpowers snapshot lives outside the plugin; mount it beside it.
    if [[ -d "$REPO_ROOT/vendor/superpowers" ]]; then
        ensure_symlink "$hermes_home/skills/pitt-skills-superpowers" "$REPO_ROOT/vendor/superpowers"
        echo "Hermes: $hermes_home/skills/pitt-skills-superpowers -> repo"
    fi
}

uninstall_hermes() {
    local hermes_home="${HERMES_HOME:-$HOME/.hermes}"
    remove_symlink "$hermes_home/skills/pitt-skills"
    remove_symlink "$hermes_home/skills/pitt-skills-superpowers"
    echo "Hermes: $hermes_home/skills/pitt-skills{,-superpowers} uninstalled"
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
        hermes)
            if [[ $UNINSTALL -eq 1 ]]; then
                # Uninstall is symlink-only; run even if the hermes binary is gone
                # so a user who removed hermes can still clean up the orphaned symlink.
                uninstall_hermes
            elif command -v hermes >/dev/null 2>&1; then
                install_hermes
            else
                echo "hermes not installed, skipping" >&2
            fi
            ;;
        *) echo "Unknown tool '$tool' - skipping. Valid: claude, copilotCli, vscode, hermes" >&2 ;;
    esac
done

echo "Done."
