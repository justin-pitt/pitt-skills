#!/usr/bin/env bats
# tests/install/install.bats - bats-core tests for scripts/install.sh
# Runs on macOS/Linux; CI executes these on Ubuntu.

setup() {
    export TEST_HOME="$(mktemp -d)"
    export ORIG_HOME="$HOME"
    export ORIG_PATH="$PATH"
    export HOME="$TEST_HOME"
    export REPO_ROOT="$(git rev-parse --show-toplevel)"

    # Stub `claude` on PATH so tests don't depend on whether the host has Claude
    # installed. install.sh skips the merge step when `command -v claude` fails,
    # which would make the merge test flaky on a bare CI runner.
    mkdir -p "$TEST_HOME/bin"
    cat > "$TEST_HOME/bin/claude" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$TEST_HOME/bin/claude"
    export PATH="$TEST_HOME/bin:$PATH"
}

teardown() {
    export HOME="$ORIG_HOME"
    export PATH="$ORIG_PATH"
    rm -rf "$TEST_HOME"
}

@test "install.sh creates ~/.copilot/skills symlink" {
    "$REPO_ROOT/scripts/install.sh" --tools copilotCli
    [ -L "$HOME/.copilot/skills" ]
}

@test "install.sh merges settings.json with backup" {
    mkdir -p "$HOME/.claude"
    echo '{"theme":"dark"}' > "$HOME/.claude/settings.json"
    "$REPO_ROOT/scripts/install.sh" --tools claude
    [ -f "$HOME/.claude/settings.json.bak" ]
    grep -q "pitt-skills" "$HOME/.claude/settings.json"
    grep -q "dark" "$HOME/.claude/settings.json"
    # Atomic-mv post-condition: no stray .tmp file
    [ ! -f "$HOME/.claude/settings.json.tmp" ]
}

@test "install.sh refuses to overwrite a non-symlink at the link path" {
    mkdir -p "$HOME/.copilot/skills"
    echo "real content" > "$HOME/.copilot/skills/do-not-delete.md"
    run "$REPO_ROOT/scripts/install.sh" --tools copilotCli
    [ "$status" -ne 0 ]
    [[ "$output" == *"Refusing to overwrite"* ]]
    # User content must not be deleted
    [ -f "$HOME/.copilot/skills/do-not-delete.md" ]
}

@test "install.sh warns on unknown tool" {
    run "$REPO_ROOT/scripts/install.sh" --tools bogus-tool
    [[ "$output" == *"Unknown tool 'bogus-tool'"* ]]
}

@test "install.sh creates HERMES_HOME/skills/pitt-skills symlink" {
    export HERMES_HOME="$TEST_HOME/.hermes"
    # Stub `hermes` so the gate passes on hosts without Hermes installed.
    cat > "$TEST_HOME/bin/hermes" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$TEST_HOME/bin/hermes"
    "$REPO_ROOT/scripts/install.sh" --tools hermes
    [ -L "$HERMES_HOME/skills/pitt-skills" ]
    target="$(readlink "$HERMES_HOME/skills/pitt-skills")"
    [[ "$target" == *"plugins/pitt-skills/skills" ]]
}

@test "install.sh --uninstall removes the hermes symlink" {
    export HERMES_HOME="$TEST_HOME/.hermes"
    cat > "$TEST_HOME/bin/hermes" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$TEST_HOME/bin/hermes"
    "$REPO_ROOT/scripts/install.sh" --tools hermes
    [ -L "$HERMES_HOME/skills/pitt-skills" ]
    "$REPO_ROOT/scripts/install.sh" --tools hermes --uninstall
    [ ! -L "$HERMES_HOME/skills/pitt-skills" ]
}

@test "install.sh hermes refuses to overwrite a non-symlink" {
    export HERMES_HOME="$TEST_HOME/.hermes"
    cat > "$TEST_HOME/bin/hermes" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$TEST_HOME/bin/hermes"
    mkdir -p "$HERMES_HOME/skills/pitt-skills"
    echo "real" > "$HERMES_HOME/skills/pitt-skills/keep.md"
    run "$REPO_ROOT/scripts/install.sh" --tools hermes
    [ "$status" -ne 0 ]
    [[ "$output" == *"Refusing to overwrite"* ]]
    [ -f "$HERMES_HOME/skills/pitt-skills/keep.md" ]
}

@test "install.sh skips hermes when binary is missing" {
    # No hermes stub in $TEST_HOME/bin. Curate PATH to system utility dirs so
    # install.sh's preamble (dirname, etc.) still works, but exclude any host
    # location that might have a real hermes installed.
    export PATH="$TEST_HOME/bin:/usr/bin:/bin"
    export HERMES_HOME="$TEST_HOME/.hermes"
    run "$REPO_ROOT/scripts/install.sh" --tools hermes
    [ "$status" -eq 0 ]
    [[ "$output" == *"hermes not installed"* ]]
    [ ! -L "$HERMES_HOME/skills/pitt-skills" ]
}

@test "install.sh --uninstall --tools claude removes pitt-skills keys and preserves user keys" {
    mkdir -p "$HOME/.claude"
    cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "theme": "dark",
  "extraKnownMarketplaces": {
    "pitt-skills": { "source": { "source": "github", "repo": "justin-pitt/pitt-skills" } },
    "someOtherMarketplace": { "source": { "source": "github", "repo": "x/y" } }
  },
  "enabledPlugins": {
    "pitt-skills@pitt-skills": true,
    "other@plugin": true
  }
}
JSON
    "$REPO_ROOT/scripts/install.sh" --uninstall --tools claude
    [ -f "$HOME/.claude/settings.json.bak" ]
    grep -q '"theme": "dark"' "$HOME/.claude/settings.json"
    grep -q "someOtherMarketplace" "$HOME/.claude/settings.json"
    grep -q "other@plugin" "$HOME/.claude/settings.json"
    ! grep -q '"pitt-skills":' "$HOME/.claude/settings.json"
    ! grep -q '"pitt-skills@pitt-skills"' "$HOME/.claude/settings.json"
}

@test "install.sh --uninstall --tools claude drops empty parents" {
    mkdir -p "$HOME/.claude"
    cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "theme": "dark",
  "extraKnownMarketplaces": {
    "pitt-skills": { "source": { "source": "github", "repo": "justin-pitt/pitt-skills" } }
  },
  "enabledPlugins": { "pitt-skills@pitt-skills": true }
}
JSON
    "$REPO_ROOT/scripts/install.sh" --uninstall --tools claude
    ! grep -q "extraKnownMarketplaces" "$HOME/.claude/settings.json"
    ! grep -q "enabledPlugins" "$HOME/.claude/settings.json"
    grep -q '"theme": "dark"' "$HOME/.claude/settings.json"
}

@test "install.sh --uninstall --tools copilotCli removes symlink and is idempotent" {
    "$REPO_ROOT/scripts/install.sh" --tools copilotCli
    [ -L "$HOME/.copilot/skills" ]
    "$REPO_ROOT/scripts/install.sh" --uninstall --tools copilotCli
    [ ! -e "$HOME/.copilot/skills" ]
    # Idempotent second run
    run "$REPO_ROOT/scripts/install.sh" --uninstall --tools copilotCli
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.copilot/skills" ]
}

@test "install.sh --uninstall --tools copilotCli refuses to delete a real directory" {
    mkdir -p "$HOME/.copilot/skills"
    echo "real content" > "$HOME/.copilot/skills/do-not-delete.md"
    run "$REPO_ROOT/scripts/install.sh" --uninstall --tools copilotCli
    [ "$status" -eq 0 ]
    # Real dir should still be there with its content intact
    [ -d "$HOME/.copilot/skills" ]
    [ -f "$HOME/.copilot/skills/do-not-delete.md" ]
    [[ "$output" == *"Refusing to delete non-symlink"* ]]
}

@test "install.sh --uninstall is idempotent when settings.json is absent" {
    [ ! -e "$HOME/.claude/settings.json" ]
    run "$REPO_ROOT/scripts/install.sh" --uninstall --tools claude
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.claude/settings.json" ]
}

@test "install.sh --uninstall --tools hermes removes symlink even when hermes binary is absent" {
    export HERMES_HOME="$TEST_HOME/.hermes"
    # Install with hermes stubbed.
    cat > "$TEST_HOME/bin/hermes" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$TEST_HOME/bin/hermes"
    "$REPO_ROOT/scripts/install.sh" --tools hermes
    [ -L "$HERMES_HOME/skills/pitt-skills" ]

    # Simulate the user uninstalling hermes from their system after pitt-skills was wired up.
    rm "$TEST_HOME/bin/hermes"

    # Uninstall must still clean up the symlink — it does not need the binary.
    "$REPO_ROOT/scripts/install.sh" --uninstall --tools hermes
    [ ! -L "$HERMES_HOME/skills/pitt-skills" ]
}

