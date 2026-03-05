#!/usr/bin/env bats
# TDD Scaffold: Post-task lessons nudge notification
# Covers: AC-01, AC-02, AC-03, AC-04, AC-05

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "common.sh"
    source_lib "workflow.sh"
    export LESSONS_FILE=".buildcrew/lessons.md"
}

teardown() {
    teardown_test_dir
    __LOG_FILE=""
}

# Helper: assert string contains substring
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

# Helper: create a lessons file with N lesson entries
create_lessons_file() {
    local count="$1"
    mkdir -p .buildcrew
    cat > "$LESSONS_FILE" <<'HEADER'
# BuildCrew Lessons

Lessons learned from failures across runs.

---

HEADER
    for ((i=1; i<=count; i++)); do
        cat >> "$LESSONS_FILE" <<EOF

## Lesson $i: 2026-03-05

**Phase**: build
**What went wrong**: Test failure $i
**What fixed it**: Fixed it
**Rule**: Rule $i
**Applies to**: build persona

---

EOF
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: _check_lessons_nudge is a callable function
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01: _check_lessons_nudge is a callable function" {
    run bash -c 'source "'"$BUILDCREW_ROOT"'/lib/common.sh"; source "'"$BUILDCREW_ROOT"'/lib/workflow.sh"; type _check_lessons_nudge'
    [ "$status" -eq 0 ]
    assert_contains "$output" "is a function"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01/AC-02: Nudge shown when new lessons were added, with correct count
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01: nudge appears when lessons_after > lessons_before" {
    create_lessons_file 3
    run _check_lessons_nudge 0
    [ "$status" -eq 0 ]
    assert_contains "$output" "new lesson"
}

@test "AC-02: nudge shows exact count of 1 new lesson" {
    create_lessons_file 2
    run _check_lessons_nudge 1
    [ "$status" -eq 0 ]
    assert_contains "$output" "1 new lesson"
}

@test "AC-02: nudge shows exact count of 3 new lessons" {
    create_lessons_file 5
    run _check_lessons_nudge 2
    [ "$status" -eq 0 ]
    assert_contains "$output" "3 new lesson"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: Nudge suppressed when no new lessons
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03: no nudge when lessons count unchanged" {
    create_lessons_file 2
    run _check_lessons_nudge 2
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AC-03: no nudge when no lessons file exists" {
    run _check_lessons_nudge 0
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AC-03: no nudge when lessons_after < lessons_before (summarization)" {
    create_lessons_file 3
    run _check_lessons_nudge 5
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: Promote tip uses actual CLI syntax
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-05: nudge includes buildcrew lessons review tip" {
    create_lessons_file 1
    run _check_lessons_nudge 0
    [ "$status" -eq 0 ]
    assert_contains "$output" "buildcrew lessons"
}

@test "AC-05: nudge includes promote tip with correct syntax" {
    create_lessons_file 1
    run _check_lessons_nudge 0
    [ "$status" -eq 0 ]
    assert_contains "$output" "buildcrew lessons promote"
}
