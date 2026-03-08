#!/usr/bin/env bats
# TDD Scaffold: Runtime context health check
# Covers: AC-01, AC-02, AC-03, AC-05, AC-07

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "common.sh"
}

teardown() {
    teardown_test_dir
    __LOG_FILE=""
}

# Helper: assert string contains substring (fails properly under set -e)
assert_contains() {
    local haystack="$1" needle="$2"
    case "$haystack" in
        *"$needle"*) return 0 ;;
        *) echo "Expected output to contain: $needle"; echo "Actual output: $haystack"; return 1 ;;
    esac
}

# Helper: assert string does NOT contain substring
assert_not_contains() {
    local haystack="$1" needle="$2"
    case "$haystack" in
        *"$needle"*) echo "Expected output NOT to contain: $needle"; echo "Actual output: $haystack"; return 1 ;;
        *) return 0 ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: check_context_health is a function
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01: check_context_health is a function" {
    run bash -c 'source "'"$BUILDCREW_ROOT"'/lib/common.sh" && type check_context_health'
    [ "$status" -eq 0 ]
    assert_contains "$output" "is a function"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: all four files present -> no output, returns 0
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03: all files present produces no output" {
    mkdir -p .buildcrew/context
    echo "users" > .buildcrew/context/users.md
    echo "principles" > .buildcrew/context/principles.md
    echo "domain" > .buildcrew/context/domain.md
    echo "lessons" > .buildcrew/lessons.md

    run check_context_health
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-07: always returns 0 regardless of missing files
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-07: returns 0 when all files missing" {
    run check_context_health
    [ "$status" -eq 0 ]
    # Must also produce output (warning) when files are missing
    [ -n "$output" ]
}

@test "AC-07: returns 0 with mixed present/missing" {
    mkdir -p .buildcrew/context
    echo "users" > .buildcrew/context/users.md

    run check_context_health
    [ "$status" -eq 0 ]
    # Must produce output since some files are missing
    [ -n "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: missing files produce warning with paths and suggested commands
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02: single missing file shows path and suggested command" {
    mkdir -p .buildcrew/context
    echo "users" > .buildcrew/context/users.md
    echo "principles" > .buildcrew/context/principles.md
    echo "domain" > .buildcrew/context/domain.md
    # lessons.md missing

    run check_context_health
    [ "$status" -eq 0 ]
    assert_contains "$output" ".buildcrew/lessons.md"
    assert_contains "$output" "touch .buildcrew/lessons.md"
    # users.md is present — must NOT appear in warning
    assert_not_contains "$output" "context/users.md"
}

@test "AC-02: all four missing shows all paths and commands in table order" {
    # No files at all
    run check_context_health
    [ "$status" -eq 0 ]

    # All four paths must appear
    assert_contains "$output" ".buildcrew/context/users.md"
    assert_contains "$output" ".buildcrew/context/principles.md"
    assert_contains "$output" ".buildcrew/context/domain.md"
    assert_contains "$output" ".buildcrew/lessons.md"

    # All four suggested commands must appear
    assert_contains "$output" "cp .buildcrew/context/users.md.example .buildcrew/context/users.md"
    assert_contains "$output" "cp .buildcrew/context/principles.md.example .buildcrew/context/principles.md"
    assert_contains "$output" "cp .buildcrew/context/domain.md.example .buildcrew/context/domain.md"
    assert_contains "$output" "touch .buildcrew/lessons.md"
}

@test "AC-02: table order preserved — users before principles before domain before lessons" {
    # No files at all — all four missing
    run check_context_health
    [ "$status" -eq 0 ]

    # Extract line numbers to verify ordering
    local users_pos principles_pos domain_pos lessons_pos
    users_pos=$(echo "$output" | grep -n "context/users.md" | head -1 | cut -d: -f1)
    principles_pos=$(echo "$output" | grep -n "context/principles.md" | head -1 | cut -d: -f1)
    domain_pos=$(echo "$output" | grep -n "context/domain.md" | head -1 | cut -d: -f1)
    lessons_pos=$(echo "$output" | grep -n "lessons.md" | grep -v "context/" | head -1 | cut -d: -f1)

    [ -n "$users_pos" ]
    [ -n "$principles_pos" ]
    [ -n "$domain_pos" ]
    [ -n "$lessons_pos" ]
    [ "$users_pos" -lt "$principles_pos" ]
    [ "$principles_pos" -lt "$domain_pos" ]
    [ "$domain_pos" -lt "$lessons_pos" ]
}

@test "AC-02: only missing files appear — present files excluded" {
    command mkdir -p .buildcrew/context
    echo "principles" > .buildcrew/context/principles.md
    echo "lessons" > .buildcrew/lessons.md
    # users.md and domain.md missing

    run check_context_health
    [ "$status" -eq 0 ]
    assert_contains "$output" "context/users.md"
    assert_contains "$output" "context/domain.md"
    # Present files must NOT appear
    assert_not_contains "$output" "context/principles.md"
    assert_not_contains "$output" "touch .buildcrew/lessons.md"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: output uses relative paths only
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-05: no absolute paths in warning output" {
    # No files — all missing, maximum output
    run check_context_health
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    # Must not contain absolute path indicators
    assert_not_contains "$output" "$TEST_DIR"
    # Every path reference should use .buildcrew/ relative form
    assert_not_contains "$output" " /Users/"
    assert_not_contains "$output" " /home/"
    assert_not_contains "$output" " /tmp/"
}
