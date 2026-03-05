#!/usr/bin/env bats
# Additional tests for check_context_health — edge cases, error handling, adversarial, smoke
# Separate from TDD scaffold tests in tests/tdd/context_health.bats

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "common.sh"
}

teardown() {
    teardown_test_dir
    __LOG_FILE=""
}

# ─────────────────────────────────────────────────────────────────────────────
# ERR-01: .buildcrew/context missing but lessons.md present
# ─────────────────────────────────────────────────────────────────────────────

@test "ERR-01: context dir missing but lessons.md present warns only about 3 context files" {
    mkdir -p .buildcrew
    echo "x" > .buildcrew/lessons.md

    run check_context_health
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/users.md"* ]]
    [[ "$output" == *"context/principles.md"* ]]
    [[ "$output" == *"context/domain.md"* ]]
    # lessons.md is present — must NOT appear
    [[ "$output" != *"lessons.md"*"touch"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# EDGE-01: Empty files (zero bytes) count as present
# ─────────────────────────────────────────────────────────────────────────────

@test "EDGE-01: empty zero-byte files produce no warning" {
    mkdir -p .buildcrew/context
    touch .buildcrew/context/users.md
    touch .buildcrew/context/principles.md
    touch .buildcrew/context/domain.md
    touch .buildcrew/lessons.md

    run check_context_health
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# EDGE-02: Directory at expected file path
# ─────────────────────────────────────────────────────────────────────────────

@test "EDGE-02: directory at file path triggers warning for that path" {
    mkdir -p .buildcrew/context
    echo "users" > .buildcrew/context/users.md
    echo "principles" > .buildcrew/context/principles.md
    echo "domain" > .buildcrew/context/domain.md
    # Create a directory instead of a file for lessons.md
    mkdir -p .buildcrew/lessons.md

    run check_context_health
    [ "$status" -eq 0 ]
    [[ "$output" == *".buildcrew/lessons.md"* ]]
    [[ "$output" == *"touch .buildcrew/lessons.md"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# EDGE-03: Broken symlink at expected path
# ─────────────────────────────────────────────────────────────────────────────

@test "EDGE-03: broken symlink triggers warning for that path" {
    mkdir -p .buildcrew/context
    echo "users" > .buildcrew/context/users.md
    echo "principles" > .buildcrew/context/principles.md
    echo "domain" > .buildcrew/context/domain.md
    # Create a broken symlink
    ln -s /nonexistent_target_for_test .buildcrew/lessons.md

    run check_context_health
    [ "$status" -eq 0 ]
    [[ "$output" == *".buildcrew/lessons.md"* ]]
    [[ "$output" == *"touch .buildcrew/lessons.md"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-01: PWD with spaces in path
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-01: function works when PWD contains spaces" {
    # Move to a path with spaces
    local space_dir="$TEST_DIR/bc test dir"
    mkdir -p "$space_dir/.buildcrew/context"
    echo "users" > "$space_dir/.buildcrew/context/users.md"
    # principles.md, domain.md, lessons.md missing
    cd "$space_dir"

    run check_context_health
    [ "$status" -eq 0 ]
    [[ "$output" == *".buildcrew/context/principles.md"* ]]
    [[ "$output" == *".buildcrew/context/domain.md"* ]]
    [[ "$output" == *".buildcrew/lessons.md"* ]]
    # Must NOT contain the absolute tmpdir path
    [[ "$output" != *"$space_dir"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# SMOKE-01: Call site wiring in workflow.sh (AC-04)
# ─────────────────────────────────────────────────────────────────────────────

@test "SMOKE-01: check_context_health appears exactly once in workflow.sh" {
    local count
    count=$(grep -c 'check_context_health' "$BUILDCREW_ROOT/lib/workflow.sh")
    [ "$count" -eq 1 ]
}

@test "SMOKE-01: call site is between check_prerequisites and clear_stop_signal" {
    # Extract a wider window to capture both surrounding calls
    local context
    context=$(grep -B3 -A5 'check_context_health' "$BUILDCREW_ROOT/lib/workflow.sh")
    [[ "$context" == *"check_prerequisites"* ]]
    [[ "$context" == *"clear_stop_signal"* ]]
}

@test "SMOKE-01: call site is not inside a conditional block" {
    # check_context_health and check_prerequisites should share indentation level
    local indent_health indent_prereq
    indent_health=$(grep 'check_context_health' "$BUILDCREW_ROOT/lib/workflow.sh" | sed 's/[^ ].*//')
    indent_prereq=$(grep 'check_prerequisites$' "$BUILDCREW_ROOT/lib/workflow.sh" | head -1 | sed 's/[^ ].*//')
    [ "$indent_health" = "$indent_prereq" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# SMOKE-02: Batch mode bypasses check_context_health (AC-04)
# ─────────────────────────────────────────────────────────────────────────────

@test "SMOKE-02: enter_batch_mode precedes check_context_health in main()" {
    local batch_line health_line
    batch_line=$(grep -n 'enter_batch_mode' "$BUILDCREW_ROOT/lib/workflow.sh" | head -1 | cut -d: -f1)
    health_line=$(grep -n 'check_context_health' "$BUILDCREW_ROOT/lib/workflow.sh" | head -1 | cut -d: -f1)
    [ -n "$batch_line" ]
    [ -n "$health_line" ]
    [ "$batch_line" -lt "$health_line" ]
}

@test "SMOKE-02: batch mode comment confirms control does not return" {
    # The comment after the enter_batch_mode call in main() should indicate no return
    local after_batch
    after_batch=$(grep -A1 'enter_batch_mode "\$task_list"' "$BUILDCREW_ROOT/lib/workflow.sh" | tail -1)
    [[ "$after_batch" == *"does not return"* ]] || [[ "$after_batch" == *"exit"* ]]
}
