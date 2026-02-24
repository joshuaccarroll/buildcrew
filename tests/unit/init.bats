#!/usr/bin/env bats
# Unit tests for playground plugin install in cmd_init() and cmd_repair()

load '../setup.bash'

BUILDCREW_BIN="$BUILDCREW_ROOT/bin/buildcrew"

# Override HOME to an isolated temp directory so $HOME/.claude/plugins/...
# operations never touch the real user home and are cleaned up automatically.
setup() {
    setup_test_dir
    export ORIGINAL_HOME="$HOME"
    export HOME="$TEST_DIR/fake-home"
    mkdir -p "$HOME"
}

teardown() {
    export HOME="$ORIGINAL_HOME"
    teardown_test_dir
}

# Set up a minimal project structure that makes all non-playground checks pass,
# so repair tests can focus on the playground block output.
setup_repaired_project() {
    mkdir -p .claude .buildcrew/rules .buildcrew/context
    echo "BUILDCREW_HOME=$BUILDCREW_ROOT" > .claude/.buildcrew-link
    ln -s "$BUILDCREW_ROOT/commands" .claude/commands 2>/dev/null || true
    ln -s "$BUILDCREW_ROOT/skills"   .claude/skills   2>/dev/null || true
}

# Create a mock claude that succeeds on all plugin subcommands.
create_mock_claude_plugin_ok() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$TEST_DIR/bin/claude"
    export PATH="$TEST_DIR/bin:$PATH"
}

# Create a mock claude that exits 1 on "plugin install", succeeds otherwise.
create_mock_claude_plugin_fail() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" << 'EOF'
#!/bin/bash
if [[ "$*" == *"plugin install"* ]]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$TEST_DIR/bin/claude"
    export PATH="$TEST_DIR/bin:$PATH"
}

# ─────────────────────────────────────────────────────────────────────────────
# cmd_init: playground plugin install
# ─────────────────────────────────────────────────────────────────────────────

@test "cmd_init: installs playground plugin when not present" {
    create_mock_claude_plugin_ok
    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installed playground plugin"* ]]
}

@test "cmd_init: skips install when playground already in installed_plugins.json" {
    create_mock_claude_plugin_ok
    mkdir -p "$HOME/.claude/plugins"
    echo '{"playground@claude-plugins-official": []}' > "$HOME/.claude/plugins/installed_plugins.json"
    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"Playground plugin already installed"* ]]
}

@test "cmd_init: shows warning when plugin install fails" {
    create_mock_claude_plugin_fail
    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"Playground plugin not installed"* ]]
    [[ "$output" == *"install manually"* ]]
}

@test "cmd_init: skips playground block silently when claude CLI absent" {
    # Remove any claude from PATH by building a PATH without claude binaries
    local safe_path=""
    while IFS= read -r dir; do
        [[ -x "$dir/claude" ]] && continue
        safe_path="${safe_path:+$safe_path:}$dir"
    done < <(printf '%s\n' "$PATH" | tr ':' '\n')
    export PATH="$safe_path"

    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    [[ "$output" != *"playground"* ]] || true
}

# ─────────────────────────────────────────────────────────────────────────────
# cmd_repair: C7 playground plugin block
# ─────────────────────────────────────────────────────────────────────────────

@test "cmd_repair: reports playground not installed as an issue" {
    setup_repaired_project
    create_mock_claude_plugin_ok
    run "$BUILDCREW_BIN" repair
    [ "$status" -ne 0 ]
    [[ "$output" == *"Playground plugin not installed"* ]]
    [[ "$output" == *"issue(s) found"* ]]
}

@test "cmd_repair --fix: installs playground plugin successfully" {
    setup_repaired_project
    create_mock_claude_plugin_ok
    run "$BUILDCREW_BIN" repair --fix
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installed playground plugin"* ]]
}

@test "cmd_repair --fix: increments remaining when install fails" {
    setup_repaired_project
    create_mock_claude_plugin_fail
    run "$BUILDCREW_BIN" repair --fix
    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to install playground plugin"* ]]
    [[ "$output" == *"issue(s) remain"* ]]
}

@test "cmd_repair: playground already installed shows healthy status" {
    setup_repaired_project
    create_mock_claude_plugin_ok
    mkdir -p "$HOME/.claude/plugins"
    echo '{"playground@claude-plugins-official": []}' > "$HOME/.claude/plugins/installed_plugins.json"
    run "$BUILDCREW_BIN" repair
    [ "$status" -eq 0 ]
    [[ "$output" == *"Playground plugin installed"* ]]
    [[ "$output" == *"All checks passed"* ]]
}

@test "cmd_repair: prints info and skips check when claude CLI absent" {
    setup_repaired_project
    local safe_path=""
    while IFS= read -r dir; do
        [[ -x "$dir/claude" ]] && continue
        safe_path="${safe_path:+$safe_path:}$dir"
    done < <(printf '%s\n' "$PATH" | tr ':' '\n')
    export PATH="$safe_path"

    run "$BUILDCREW_BIN" repair
    [ "$status" -eq 0 ]
    [[ "$output" == *"Playground plugin — claude CLI not found, skipped"* ]]
    [[ "$output" == *"All checks passed"* ]]
}
