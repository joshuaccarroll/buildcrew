#!/usr/bin/env bats
# TDD Scaffold: Post-init context completeness summary
# Covers: AC-01, AC-02, AC-03, AC-04, AC-05, AC-06

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
# AC-01: All four files missing → four ✗ lines with cp commands
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01: init --quick shows Context files: header" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context files:"* ]]
}

@test "AC-01: init --quick shows ✗ users.md with cp command when missing" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    # Line must contain ✗, users.md, and the cp command
    local line
    line=$(echo "$output" | grep "users.md" | grep "✗")
    [[ "$line" == *"✗"* ]]
    [[ "$line" == *"cp .buildcrew/context/users.md.example .buildcrew/context/users.md"* ]]
}

@test "AC-01: init --quick shows ✗ principles.md with cp command when missing" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    local line
    line=$(echo "$output" | grep "principles.md" | grep "✗" | tail -1)
    [[ "$line" == *"✗"* ]]
    [[ "$line" == *"cp .buildcrew/context/principles.md.example .buildcrew/context/principles.md"* ]]
}

@test "AC-01: init --quick shows ✗ domain.md with cp command when missing" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    local line
    line=$(echo "$output" | grep "domain.md" | grep "✗" | tail -1)
    [[ "$line" == *"✗"* ]]
    [[ "$line" == *"cp .buildcrew/context/domain.md.example .buildcrew/context/domain.md"* ]]
}

@test "AC-01: init --quick shows ✗ conventions.md with cp command when missing" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    local line
    line=$(echo "$output" | grep "conventions.md" | grep "✗" | tail -1)
    [[ "$line" == *"✗"* ]]
    [[ "$line" == *"cp .buildcrew/context/conventions.md.example .buildcrew/context/conventions.md"* ]]
}

@test "AC-01: summary shows files in order: users, principles, domain, conventions" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    # First verify Context files: header exists
    [[ "$output" == *"Context files:"* ]]
    # Extract lines after "Context files:" and check order
    local summary
    summary=$(echo "$output" | sed -n '/Context files:/,$ p')
    local users_line principles_line domain_line conventions_line
    users_line=$(echo "$summary" | grep -n "users.md" | head -1 | cut -d: -f1)
    principles_line=$(echo "$summary" | grep -n "principles.md" | head -1 | cut -d: -f1)
    domain_line=$(echo "$summary" | grep -n "domain.md" | head -1 | cut -d: -f1)
    conventions_line=$(echo "$summary" | grep -n "conventions.md" | head -1 | cut -d: -f1)
    # All four must be present
    [ -n "$users_line" ]
    [ -n "$principles_line" ]
    [ -n "$domain_line" ]
    [ -n "$conventions_line" ]
    # Order: users < principles < domain < conventions
    [ "$users_line" -lt "$principles_line" ]
    [ "$principles_line" -lt "$domain_line" ]
    [ "$domain_line" -lt "$conventions_line" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: Mix of existing and missing files → ✓ with bytes, ✗ with cp
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02: pre-existing users.md shows ✓ with byte size" {
    _mock_claude_ok
    mkdir -p .buildcrew/context
    printf 'test' > .buildcrew/context/users.md
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    local line
    line=$(echo "$output" | grep "users.md" | grep -v ".example")
    [[ "$line" == *"✓"* ]]
    [[ "$line" == *"(4 bytes)"* ]]
}

@test "AC-02: pre-existing domain.md shows ✓ with byte size" {
    _mock_claude_ok
    mkdir -p .buildcrew/context
    printf 'test2' > .buildcrew/context/domain.md
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    local line
    line=$(echo "$output" | grep "domain.md" | grep -v ".example")
    [[ "$line" == *"✓"* ]]
    [[ "$line" == *"(5 bytes)"* ]]
}

@test "AC-02: missing principles.md shows ✗ with cp command when users.md exists" {
    _mock_claude_ok
    command mkdir -p .buildcrew/context
    printf 'test' > .buildcrew/context/users.md
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    local line
    line=$(echo "$output" | grep "principles.md" | grep "✗" | tail -1)
    [[ "$line" == *"✗"* ]]
    [[ "$line" == *"cp .buildcrew/context/principles.md.example .buildcrew/context/principles.md"* ]]
}

@test "AC-02: missing conventions.md shows ✗ with cp command when domain.md exists" {
    _mock_claude_ok
    mkdir -p .buildcrew/context
    printf 'test2' > .buildcrew/context/domain.md
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    local line
    line=$(echo "$output" | grep "conventions.md" | grep "✗" | tail -1)
    [[ "$line" == *"✗"* ]]
    [[ "$line" == *"cp .buildcrew/context/conventions.md.example .buildcrew/context/conventions.md"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: cp commands use relative paths (no / or ~ prefix)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03: cp commands use relative paths not absolute" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    # Extract all cp commands from output
    local cp_lines
    cp_lines=$(echo "$output" | grep "cp .buildcrew/context/" || true)
    [ -n "$cp_lines" ]
    # None should start with / or ~ in the path arguments
    local bad_lines
    bad_lines=$(echo "$cp_lines" | grep -E "cp (/|~)" || true)
    [ -z "$bad_lines" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: Summary on stdout, not stderr; appears after init output
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04: summary appears on stdout not stderr (--quick mode)" {
    _mock_claude_ok
    # Capture stdout and stderr separately in a single run
    local stdout_file="$TEST_DIR/stdout.txt"
    local stderr_file="$TEST_DIR/stderr.txt"
    "$BUILDCREW_BIN" init --quick >"$stdout_file" 2>"$stderr_file" || true
    # Context files header must be in stdout
    grep -q "Context files:" "$stdout_file"
    # Context files header must NOT be in stderr
    ! grep -q "Context files:" "$stderr_file"
}

@test "AC-04: summary appears after BuildCrew initialized! text" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    local init_line context_line
    init_line=$(echo "$output" | grep -n "BuildCrew initialized!" | head -1 | cut -d: -f1)
    context_line=$(echo "$output" | grep -n "Context files:" | head -1 | cut -d: -f1)
    [ -n "$init_line" ]
    [ -n "$context_line" ]
    [ "$context_line" -gt "$init_line" ]
}

@test "AC-04: summary appears in non-TTY (piped) init mode" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context files:"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: Missing .example file → shows "missing" instead of cp command
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-05: missing .example file shows ✗ with missing label" {
    _mock_claude_ok
    # First init to create .example files
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    # Delete principles.md.example to simulate corrupt state
    rm -f .buildcrew/context/principles.md.example
    # Re-run init
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    local line
    line=$(echo "$output" | grep "principles.md" | grep -v ".example" | tail -1)
    [[ "$line" == *"✗"* ]]
    [[ "$line" == *"missing"* ]]
}

@test "AC-05: missing .example shows ✗ missing and no cp command" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    rm -f .buildcrew/context/principles.md.example
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    # The Context files: summary must exist
    [[ "$output" == *"Context files:"* ]]
    # Extract the principles.md line from the summary section
    local line
    line=$(echo "$output" | grep "principles.md" | grep -v ".example" | tail -1)
    # Line must exist (not empty)
    [ -n "$line" ]
    # Must contain ✗ and "missing"
    [[ "$line" == *"✗"* ]]
    [[ "$line" == *"missing"* ]]
    # Must NOT contain a cp command
    [[ "$line" != *"cp "* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-06: Existing test suite still passes (tested via test.sh, not here)
#        This test verifies our tests don't break the test runner
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-06: init --quick exits cleanly with summary present" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    # Verify both the normal init output and the summary coexist
    [[ "$output" == *"BuildCrew initialized!"* ]]
    [[ "$output" == *"Context files:"* ]]
}
