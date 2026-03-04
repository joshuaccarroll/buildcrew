#!/usr/bin/env bats
# TDD Scaffold: Interactive context-file prompts for buildcrew init
# Covers: AC-03, AC-04, AC-05, AC-06, AC-08, AC-09
# TDD-exempt: AC-01 (TTY), AC-02 (TTY), AC-07 (meta), AC-10 (TTY)

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

# Create a mock claude that succeeds (needed because cmd_init installs playground plugin)
_mock_claude_ok() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" << 'MOCKEOF'
#!/bin/bash
exit 0
MOCKEOF
    chmod +x "$TEST_DIR/bin/claude"
    export PATH="$TEST_DIR/bin:$PATH"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: buildcrew init --quick creates .example files (incl. conventions),
#         no prompts on stdout, no non-example context files
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04: --quick creates conventions.md.example" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    [ -f ".buildcrew/context/conventions.md.example" ]
}

@test "AC-04: --quick creates all four .example context files" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    [ -f ".buildcrew/context/users.md.example" ]
    [ -f ".buildcrew/context/principles.md.example" ]
    [ -f ".buildcrew/context/domain.md.example" ]
    [ -f ".buildcrew/context/conventions.md.example" ]
}

@test "AC-04: --quick produces zero prompt strings in output" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    [[ "$output" != *"Who are the primary users"* ]]
    [[ "$output" != *"What are the key domain terms"* ]]
    [[ "$output" != *"What core principles guide"* ]]
    [[ "$output" != *"What coding conventions"* ]]
}

@test "AC-04: --quick creates zero non-example context files" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    [ ! -f ".buildcrew/context/users.md" ]
    [ ! -f ".buildcrew/context/domain.md" ]
    [ ! -f ".buildcrew/context/principles.md" ]
    [ ! -f ".buildcrew/context/conventions.md" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-06: conventions.md.example content validation
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-06: conventions.md.example contains # Conventions header" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    grep -q "^# Conventions" ".buildcrew/context/conventions.md.example"
}

@test "AC-06: conventions.md.example contains copy instruction" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    grep -qi "copy.*conventions\.md" ".buildcrew/context/conventions.md.example"
}

@test "AC-06: conventions.md.example contains placeholder for coding style" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    grep -qi "coding style\|code style" ".buildcrew/context/conventions.md.example"
}

@test "AC-06: conventions.md.example contains placeholder for naming patterns" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    grep -qi "naming" ".buildcrew/context/conventions.md.example"
}

@test "AC-06: conventions.md.example contains placeholder for formatting rules" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    grep -qi "formatting\|format" ".buildcrew/context/conventions.md.example"
}

@test "AC-06: conventions.md.example contains placeholder for tooling preferences" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    grep -qi "tooling\|tools" ".buildcrew/context/conventions.md.example"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-08: --quick flag parsing — exits 0, no stderr, rejects unknown flags
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-08: --quick exits with code 0" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
}

@test "AC-08: --quick produces no error output on stderr" {
    _mock_claude_ok
    local stderr_output
    stderr_output=$("$BUILDCREW_BIN" init --quick 2>&1 1>/dev/null) || true
    [ -z "$stderr_output" ]
}

@test "AC-08: unknown flag --bogus is rejected with non-zero exit" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --bogus
    [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-09: Non-TTY stdin skips prompt loop entirely
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-09: non-TTY stdin (piped) produces zero prompt strings" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    [[ "$output" != *"Who are the primary users"* ]]
    [[ "$output" != *"What are the key domain terms"* ]]
    [[ "$output" != *"What core principles guide"* ]]
    [[ "$output" != *"What coding conventions"* ]]
}

@test "AC-09: non-TTY stdin creates no non-example context files" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    [ ! -f ".buildcrew/context/users.md" ]
    [ ! -f ".buildcrew/context/domain.md" ]
    [ ! -f ".buildcrew/context/principles.md" ]
    [ ! -f ".buildcrew/context/conventions.md" ]
}

@test "AC-09: non-TTY stdin still creates all .example files including conventions" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    [ -f ".buildcrew/context/users.md.example" ]
    [ -f ".buildcrew/context/principles.md.example" ]
    [ -f ".buildcrew/context/domain.md.example" ]
    [ -f ".buildcrew/context/conventions.md.example" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: Blank input → no file created (non-TTY variant)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03: non-TTY stdin does not create users.md" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    [ ! -f ".buildcrew/context/users.md" ]
}

@test "AC-03: non-TTY stdin does not create domain.md" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    [ ! -f ".buildcrew/context/domain.md" ]
}

@test "AC-03: non-TTY stdin does not create principles.md" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    [ ! -f ".buildcrew/context/principles.md" ]
}

@test "AC-03: non-TTY stdin does not create conventions.md" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    [ ! -f ".buildcrew/context/conventions.md" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: Pre-existing context file is not modified
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-05: pre-existing users.md is preserved after init" {
    _mock_claude_ok
    mkdir -p .buildcrew/context
    printf 'original' > .buildcrew/context/users.md
    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    local content
    content=$(cat .buildcrew/context/users.md)
    [ "$content" = "original" ]
}

@test "AC-05: pre-existing domain.md is preserved after init" {
    _mock_claude_ok
    mkdir -p .buildcrew/context
    printf 'original' > .buildcrew/context/domain.md
    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    local content
    content=$(cat .buildcrew/context/domain.md)
    [ "$content" = "original" ]
}

@test "AC-05: pre-existing principles.md is preserved after init --quick" {
    _mock_claude_ok
    mkdir -p .buildcrew/context
    printf 'original' > .buildcrew/context/principles.md
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    local content
    content=$(cat .buildcrew/context/principles.md)
    [ "$content" = "original" ]
}

@test "AC-05: pre-existing conventions.md is preserved after init --quick" {
    _mock_claude_ok
    mkdir -p .buildcrew/context
    printf 'original' > .buildcrew/context/conventions.md
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    local content
    content=$(cat .buildcrew/context/conventions.md)
    [ "$content" = "original" ]
}
