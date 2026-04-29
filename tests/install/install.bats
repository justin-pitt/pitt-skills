#!/usr/bin/env bats
# tests/install/install.bats - bats-core tests for scripts/install.sh
# Runs on macOS/Linux; CI executes these on Ubuntu.

setup() {
    export TEST_HOME="$(mktemp -d)"
    export ORIG_HOME="$HOME"
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
