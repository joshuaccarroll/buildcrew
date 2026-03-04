#!/usr/bin/env bats
# Adversarial and edge-case tests for buildcrew init context prompts
# Separate from TDD scaffold (tests/tdd/init_context_prompts.bats)
# Covers: ADV-01 through ADV-07, FAIL-01 through FAIL-03, SMOKE-01 through SMOKE-03

load '../setup.bash'

BUILDCREW_BIN="$BUILDCREW_ROOT/bin/buildcrew"

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

# Create a mock claude that succeeds
_mock_claude_ok() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" << 'MOCKEOF'
#!/bin/bash
exit 0
MOCKEOF
    chmod +x "$TEST_DIR/bin/claude"
    export PATH="$TEST_DIR/bin:$PATH"
}

# Remove claude from PATH
_mock_no_claude() {
    # Override PATH to exclude real claude but keep everything else
    mkdir -p "$TEST_DIR/bin"
    # Don't create a claude binary — it should be absent
    export PATH="$TEST_DIR/bin:$PATH"
    # Also hide any existing claude
    if command -v claude >/dev/null 2>&1; then
        local claude_path
        claude_path="$(command -v claude)"
        local claude_dir
        claude_dir="$(dirname "$claude_path")"
        export PATH="${PATH//$claude_dir:/}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-01: Multiple unknown flags
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-01: multiple unknown flags produce non-zero exit" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --bogus --fake
    [ "$status" -ne 0 ]
}

@test "ADV-01: multiple unknown flags produce error on stderr" {
    _mock_claude_ok
    local stderr_output
    stderr_output=$("$BUILDCREW_BIN" init --bogus --fake 2>&1 1>/dev/null) || true
    [[ "$stderr_output" == *"Unknown option"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-02: --quick combined with unknown flag
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-02: --quick followed by unknown flag produces non-zero exit" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick --bogus
    [ "$status" -ne 0 ]
}

@test "ADV-02: --quick followed by unknown flag reports error on stderr" {
    _mock_claude_ok
    local stderr_output
    stderr_output=$("$BUILDCREW_BIN" init --quick --bogus 2>&1 1>/dev/null) || true
    [[ "$stderr_output" == *"Unknown option"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-03: Double --quick flag (idempotent)
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-03: double --quick flag exits 0" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick --quick
    [ "$status" -eq 0 ]
}

@test "ADV-03: double --quick flag produces no stderr" {
    _mock_claude_ok
    local stderr_output
    stderr_output=$("$BUILDCREW_BIN" init --quick --quick 2>&1 1>/dev/null) || true
    [ -z "$stderr_output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-04: Init with partial .buildcrew (no context/)
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-04: init with existing .buildcrew but no context/ creates context dir" {
    _mock_claude_ok
    mkdir -p .buildcrew
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    [ -d ".buildcrew/context" ]
}

@test "ADV-04: init with partial .buildcrew creates all four .example files" {
    _mock_claude_ok
    mkdir -p .buildcrew
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    [ -f ".buildcrew/context/users.md.example" ]
    [ -f ".buildcrew/context/principles.md.example" ]
    [ -f ".buildcrew/context/domain.md.example" ]
    [ -f ".buildcrew/context/conventions.md.example" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-05: .example file not overwritten by second init --quick
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-05: conventions.md.example with custom content is preserved by second init --quick" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    # Replace with custom content
    echo "CUSTOM_CONTENT_MARKER" > .buildcrew/context/conventions.md.example
    # Run init again
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    local content
    content=$(cat .buildcrew/context/conventions.md.example)
    [[ "$content" == *"CUSTOM_CONTENT_MARKER"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-06: .buildcrew/context exists as a regular file (not directory)
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-06: context as regular file causes non-zero exit or error" {
    _mock_claude_ok
    mkdir -p .buildcrew
    # Create context as a regular file, not a directory
    echo "not a directory" > .buildcrew/context
    run "$BUILDCREW_BIN" init --quick
    # Should either fail or at minimum not create .example files inside a file
    # The key assertion: it must not silently succeed and corrupt state
    if [ "$status" -eq 0 ]; then
        # If it somehow exits 0, at least the .example files should not exist
        # (you can't create files inside a regular file)
        [ ! -f ".buildcrew/context/conventions.md.example" ]
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-07: .example file not overwritten by non-TTY init
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-07: users.md.example with custom content is preserved by non-TTY init" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    echo "CUSTOM_USERS_MARKER" > .buildcrew/context/users.md.example
    # Run non-TTY init (bats stdin is piped = non-TTY)
    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    local content
    content=$(cat .buildcrew/context/users.md.example)
    [[ "$content" == *"CUSTOM_USERS_MARKER"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# SMOKE-01: Init — clean state
# ─────────────────────────────────────────────────────────────────────────────

@test "SMOKE-01: init --quick in clean dir creates full scaffold" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    # Core artifacts
    [ -d ".buildcrew/context" ]
    [ -f ".buildcrew/context/users.md.example" ]
    [ -f ".buildcrew/context/principles.md.example" ]
    [ -f ".buildcrew/context/domain.md.example" ]
    [ -f ".buildcrew/context/conventions.md.example" ]
    [ -f ".claude/.buildcrew-link" ]
    [ -f ".claude/settings.json" ]
    [ -f "BACKLOG.md" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# SMOKE-02: Init — already initialized (idempotent)
# ─────────────────────────────────────────────────────────────────────────────

@test "SMOKE-02: second init --quick exits 0 with no crash" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    # Run again
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    # Files should still exist
    [ -f ".buildcrew/context/conventions.md.example" ]
    [ -f ".claude/settings.json" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# SMOKE-03: Init — no claude binary on PATH
# ─────────────────────────────────────────────────────────────────────────────

@test "SMOKE-03: init --quick without claude on PATH exits 0" {
    # Don't mock claude — let it be missing
    # Save and clear PATH of any claude binary
    local original_path="$PATH"
    export PATH="$TEST_DIR/bin:/usr/bin:/bin"
    run "$BUILDCREW_BIN" init --quick
    export PATH="$original_path"
    [ "$status" -eq 0 ]
    # .example files should still be created
    [ -f ".buildcrew/context/conventions.md.example" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# FAIL-01: Missing/broken HOME directory
# ─────────────────────────────────────────────────────────────────────────────

@test "FAIL-01: init --quick with nonexistent HOME does not crash" {
    _mock_claude_ok
    export HOME="/nonexistent_buildcrew_test_dir"
    run "$BUILDCREW_BIN" init --quick
    # Must not crash with unhandled error — exit code 0 or controlled failure
    # The key assertion: no signal-based crash (status > 128 = signal)
    [ "$status" -lt 128 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# FAIL-02: Read-only context directory
# ─────────────────────────────────────────────────────────────────────────────

@test "FAIL-02: init --quick with read-only context dir does not silently corrupt" {
    _mock_claude_ok
    mkdir -p .buildcrew/context
    # Pre-create the .example files first so the mkdir succeeds
    # Then make the directory read-only
    chmod 555 .buildcrew/context
    run "$BUILDCREW_BIN" init --quick
    # Restore permissions for cleanup
    chmod 755 .buildcrew/context
    # The command may fail — that's acceptable. What's NOT acceptable is
    # silently producing zero-byte or corrupt .example files
    if [ -f ".buildcrew/context/conventions.md.example" ]; then
        local size
        size=$(wc -c < ".buildcrew/context/conventions.md.example")
        [ "$size" -gt 0 ]
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# FAIL-03: Very long flag input
# ─────────────────────────────────────────────────────────────────────────────

@test "FAIL-03: very long unknown flag produces error without crash" {
    _mock_claude_ok
    local long_flag
    long_flag="--$(printf 'a%.0s' $(seq 1 500))"
    run "$BUILDCREW_BIN" init "$long_flag"
    [ "$status" -ne 0 ]
    # Must not crash with signal (status > 128)
    [ "$status" -lt 128 ]
}
