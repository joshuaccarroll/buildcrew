#!/usr/bin/env bats
# Unit tests for write_uat_state / clean_uat_state in lib/uat_signal.sh

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "uat_signal.sh"
}

teardown() {
    teardown_test_dir
    __LOG_FILE=""
    __UAT_STATE_DIR=""
    __UAT_STATE_PROJECT_NAME=""
}

# ─────────────────────────────────────────────────────────────────────────────
# init_uat_state tests
# ─────────────────────────────────────────────────────────────────────────────

@test "init_uat_state: sets module globals" {
    mkdir -p "$TEST_DIR/.buildcrew"
    init_uat_state "$TEST_DIR" "my-project"
    [ "$__UAT_STATE_DIR" = "$TEST_DIR/.buildcrew" ]
    [ "$__UAT_STATE_PROJECT_NAME" = "my-project" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# write_uat_state tests
# ─────────────────────────────────────────────────────────────────────────────

@test "write_uat_state: creates file with all 5 fields" {
    mkdir -p "$TEST_DIR/.buildcrew"
    init_uat_state "$TEST_DIR" "my-project"

    run write_uat_state "execute" "2" "running"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/.buildcrew/.uat-state" ]

    run grep "^UAT_PHASE=execute$" "$TEST_DIR/.buildcrew/.uat-state"
    [ "$status" -eq 0 ]
    run grep "^UAT_ITERATION=2$" "$TEST_DIR/.buildcrew/.uat-state"
    [ "$status" -eq 0 ]
    run grep "^UAT_STATUS=running$" "$TEST_DIR/.buildcrew/.uat-state"
    [ "$status" -eq 0 ]
    run grep "^UAT_TIMESTAMP=" "$TEST_DIR/.buildcrew/.uat-state"
    [ "$status" -eq 0 ]
    run grep "^UAT_PROJECT_NAME=my-project$" "$TEST_DIR/.buildcrew/.uat-state"
    [ "$status" -eq 0 ]
}

@test "write_uat_state: atomic write (no .tmp file remains)" {
    mkdir -p "$TEST_DIR/.buildcrew"
    init_uat_state "$TEST_DIR" "my-project"

    write_uat_state "stories" "1" "running"
    [ ! -f "$TEST_DIR/.buildcrew/.uat-state.tmp" ]
    [ -f "$TEST_DIR/.buildcrew/.uat-state" ]
}

@test "write_uat_state: overwrites previous state on phase change" {
    mkdir -p "$TEST_DIR/.buildcrew"
    init_uat_state "$TEST_DIR" "my-project"

    write_uat_state "stories" "1" "running"
    run grep "^UAT_PHASE=stories$" "$TEST_DIR/.buildcrew/.uat-state"
    [ "$status" -eq 0 ]

    write_uat_state "scenarios" "1" "running"
    run grep "^UAT_PHASE=scenarios$" "$TEST_DIR/.buildcrew/.uat-state"
    [ "$status" -eq 0 ]
    # Old phase should not be present
    run grep "^UAT_PHASE=stories$" "$TEST_DIR/.buildcrew/.uat-state"
    [ "$status" -ne 0 ]
}

@test "write_uat_state: returns 1 when __UAT_STATE_DIR is empty" {
    __UAT_STATE_DIR=""
    run write_uat_state "execute" "1" "running"
    [ "$status" -eq 1 ]
}

@test "write_uat_state: returns 1 when phase is empty" {
    mkdir -p "$TEST_DIR/.buildcrew"
    init_uat_state "$TEST_DIR" "my-project"
    run write_uat_state "" "1" "running"
    [ "$status" -eq 1 ]
}

@test "write_uat_state: returns 1 when iteration is empty" {
    mkdir -p "$TEST_DIR/.buildcrew"
    init_uat_state "$TEST_DIR" "my-project"
    run write_uat_state "execute" "" "running"
    [ "$status" -eq 1 ]
}

@test "write_uat_state: returns 1 when status is empty" {
    mkdir -p "$TEST_DIR/.buildcrew"
    init_uat_state "$TEST_DIR" "my-project"
    run write_uat_state "execute" "1" ""
    [ "$status" -eq 1 ]
}

@test "write_uat_state: returns 1 when state dir does not exist" {
    __UAT_STATE_DIR="$TEST_DIR/nonexistent"
    __UAT_STATE_PROJECT_NAME="test"
    run write_uat_state "execute" "1" "running"
    [ "$status" -eq 1 ]
}

@test "write_uat_state: timestamp is a valid epoch number" {
    mkdir -p "$TEST_DIR/.buildcrew"
    init_uat_state "$TEST_DIR" "my-project"
    write_uat_state "execute" "1" "running"

    local ts
    ts=$(grep "^UAT_TIMESTAMP=" "$TEST_DIR/.buildcrew/.uat-state" | cut -d= -f2)
    [[ "$ts" =~ ^[0-9]+$ ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# clean_uat_state tests
# ─────────────────────────────────────────────────────────────────────────────

@test "clean_uat_state: removes the file" {
    mkdir -p "$TEST_DIR/.buildcrew"
    init_uat_state "$TEST_DIR" "my-project"
    write_uat_state "execute" "1" "running"
    [ -f "$TEST_DIR/.buildcrew/.uat-state" ]

    clean_uat_state
    [ ! -f "$TEST_DIR/.buildcrew/.uat-state" ]
}

@test "clean_uat_state: no error if file is already missing" {
    mkdir -p "$TEST_DIR/.buildcrew"
    init_uat_state "$TEST_DIR" "my-project"
    run clean_uat_state
    [ "$status" -eq 0 ]
}

@test "clean_uat_state: clears module globals" {
    init_uat_state "$TEST_DIR" "my-project"
    clean_uat_state
    [ -z "$__UAT_STATE_DIR" ]
    [ -z "$__UAT_STATE_PROJECT_NAME" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Roundtrip tests
# ─────────────────────────────────────────────────────────────────────────────

@test "roundtrip: write then read back with grep on each field" {
    mkdir -p "$TEST_DIR/.buildcrew"
    init_uat_state "$TEST_DIR" "roundtrip-proj"
    write_uat_state "harness" "3" "running"

    local phase iteration status project_name
    phase=$(grep "^UAT_PHASE=" "$TEST_DIR/.buildcrew/.uat-state" | cut -d= -f2)
    iteration=$(grep "^UAT_ITERATION=" "$TEST_DIR/.buildcrew/.uat-state" | cut -d= -f2)
    status=$(grep "^UAT_STATUS=" "$TEST_DIR/.buildcrew/.uat-state" | cut -d= -f2)
    project_name=$(grep "^UAT_PROJECT_NAME=" "$TEST_DIR/.buildcrew/.uat-state" | cut -d= -f2)

    [ "$phase" = "harness" ]
    [ "$iteration" = "3" ]
    [ "$status" = "running" ]
    [ "$project_name" = "roundtrip-proj" ]
}
