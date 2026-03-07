#!/usr/bin/env bats
# Additional tests for post-init context completeness summary
# Covers scenarios NOT already in TDD scaffold: edge cases, adversarial, smoke

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
# HP-03: All four context files pre-created → all show ✓ with byte sizes
# ─────────────────────────────────────────────────────────────────────────────

@test "HP-03: all four context files pre-created show ✓ with byte sizes" {
    _mock_claude_ok
    mkdir -p .buildcrew/context
    printf 'alice' > .buildcrew/context/users.md
    printf 'be kind' > .buildcrew/context/principles.md
    printf 'widgets' > .buildcrew/context/domain.md
    printf 'tabs' > .buildcrew/context/conventions.md
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    # All four should show ✓
    local line
    line=$(echo "$output" | grep "users.md" | grep -v ".example")
    [[ "$line" == *"✓"* ]]
    [[ "$line" == *"(5 bytes)"* ]]
    line=$(echo "$output" | grep "principles.md" | grep -v ".example")
    [[ "$line" == *"✓"* ]]
    [[ "$line" == *"(7 bytes)"* ]]
    line=$(echo "$output" | grep "domain.md" | grep -v ".example")
    [[ "$line" == *"✓"* ]]
    [[ "$line" == *"(7 bytes)"* ]]
    line=$(echo "$output" | grep "conventions.md" | grep -v ".example")
    [[ "$line" == *"✓"* ]]
    [[ "$line" == *"(4 bytes)"* ]]
    # None should show ✗
    local summary
    summary=$(echo "$output" | sed -n '/Context files:/,/^$/p')
    ! echo "$summary" | grep -q "✗"
}

# ─────────────────────────────────────────────────────────────────────────────
# ERR-02: Empty context file shows ✓ with (0 bytes)
# ─────────────────────────────────────────────────────────────────────────────

@test "ERR-02: empty context file shows ✓ with 0 bytes" {
    _mock_claude_ok
    command mkdir -p .buildcrew/context
    : > .buildcrew/context/users.md
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    local line
    line=$(echo "$output" | grep "users.md" | grep -v ".example")
    [[ "$line" == *"✓"* ]]
    [[ "$line" == *"(0 bytes)"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# EDGE-01: Large context file shows correct byte count
# ─────────────────────────────────────────────────────────────────────────────

@test "EDGE-01: large context file shows correct byte count" {
    _mock_claude_ok
    mkdir -p .buildcrew/context
    dd if=/dev/zero of=.buildcrew/context/users.md bs=1024 count=10 2>/dev/null
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    local line
    line=$(echo "$output" | grep "users.md" | grep -v ".example")
    [[ "$line" == *"✓"* ]]
    [[ "$line" == *"(10240 bytes)"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# EDGE-02: Re-init shows summary both times
# ─────────────────────────────────────────────────────────────────────────────

@test "EDGE-02: re-init shows summary both times" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context files:"* ]]
    # Run again
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context files:"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-01: All .example files deleted → all show ✗ missing
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-01: all .example files deleted shows ✗ missing for all" {
    _mock_claude_ok
    # First init to create .example files
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    # Delete all .example files
    rm -f .buildcrew/context/*.example
    # Re-init
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    # All four should show missing
    for name in users.md principles.md domain.md conventions.md; do
        local line
        line=$(echo "$output" | grep "$name" | grep -v ".example" | tail -1)
        [[ "$line" == *"✗"* ]]
        [[ "$line" == *"missing"* ]]
        [[ "$line" != *"cp "* ]]
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-02: Context file path is a directory, not a file
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-02: context path that is a directory shows ✗ not ✓" {
    _mock_claude_ok
    mkdir -p .buildcrew/context/users.md
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    # Extract lines from the Context files: summary section
    local summary
    summary=$(echo "$output" | sed -n '/Context files:/,/^$/p')
    local line
    line=$(echo "$summary" | grep "users.md" | head -1)
    # Should show ✗ — directories are not valid context files
    [[ "$line" == *"✗"* ]]
    [[ "$line" != *"✓"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# SMOKE-01: Init in clean state exits 0 with summary
# ─────────────────────────────────────────────────────────────────────────────

@test "SMOKE-01: init --quick in clean state exits 0 with summary" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context files:"* ]]
    [[ "$output" == *"users.md"* ]]
    [[ "$output" == *"principles.md"* ]]
    [[ "$output" == *"domain.md"* ]]
    [[ "$output" == *"conventions.md"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# SMOKE-02: Init with existing .buildcrew dir exits 0 with summary
# ─────────────────────────────────────────────────────────────────────────────

@test "SMOKE-02: init --quick with existing .buildcrew dir exits 0 with summary" {
    _mock_claude_ok
    mkdir -p .buildcrew/context
    printf 'test' > .buildcrew/context/users.md
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context files:"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# SMOKE-03: End-to-end init produces complete output
# ─────────────────────────────────────────────────────────────────────────────

@test "SMOKE-03: end-to-end init --quick produces init message and summary" {
    _mock_claude_ok
    run "$BUILDCREW_BIN" init --quick
    [ "$status" -eq 0 ]
    [[ "$output" == *"BuildCrew initialized!"* ]]
    [[ "$output" == *"Context files:"* ]]
    [[ "$output" == *"Next steps:"* ]]
}
