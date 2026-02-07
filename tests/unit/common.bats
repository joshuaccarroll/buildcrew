#!/usr/bin/env bats
# Unit tests for lib/common.sh extracted functions

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "common.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# load_project_context tests
# ─────────────────────────────────────────────────────────────────────────────

@test "load_project_context: returns empty when no context files exist" {
    run load_project_context
    [ "$status" -eq 0 ]
    [ -z "$(echo "$output" | tr -d '[:space:]')" ]
}

@test "load_project_context: loads single context file" {
    mkdir -p .buildcrew/context
    echo "User context here" > .buildcrew/context/users.md
    run load_project_context
    [ "$status" -eq 0 ]
    [[ "$output" == *"User context here"* ]]
}

@test "load_project_context: loads all three context files" {
    mkdir -p .buildcrew/context
    echo "Users" > .buildcrew/context/users.md
    echo "Principles" > .buildcrew/context/principles.md
    echo "Domain" > .buildcrew/context/domain.md
    run load_project_context
    [ "$status" -eq 0 ]
    [[ "$output" == *"Users"* ]]
    [[ "$output" == *"Principles"* ]]
    [[ "$output" == *"Domain"* ]]
}

@test "load_project_context: truncates oversized context" {
    mkdir -p .buildcrew/context
    # Create a file larger than 10KB
    python3 -c "print('x' * 12000)" > .buildcrew/context/users.md
    output=$(load_project_context 2>/dev/null)
    [[ "$output" == *"[truncated]"* ]]
}

@test "load_project_context: sends truncation warning to stderr" {
    mkdir -p .buildcrew/context
    python3 -c "print('x' * 12000)" > .buildcrew/context/users.md
    # Capture stderr
    stderr_output=$(load_project_context 2>&1 1>/dev/null)
    [[ "$stderr_output" == *"truncating"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# parse_status_file tests
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_status_file: parses complete status" {
    mkdir -p .claude
    echo '{"status": "complete", "summary": "Task done"}' > .claude/test-status.json
    parse_status_file ".claude/test-status.json"
    [ "$__STATUS_RESULT" = "complete" ]
    [ "$__STATUS_SUMMARY" = "Task done" ]
}

@test "parse_status_file: parses blocked status" {
    mkdir -p .claude
    echo '{"status": "blocked", "reason": "Tests failing"}' > .claude/test-status.json
    parse_status_file ".claude/test-status.json"
    [ "$__STATUS_RESULT" = "blocked" ]
    [ "$__STATUS_REASON" = "Tests failing" ]
}

@test "parse_status_file: returns 1 for missing file" {
    local rc=0
    parse_status_file "nonexistent.json" || rc=$?
    [ "$rc" -eq 1 ]
    [ "$__STATUS_RESULT" = "error" ]
}

@test "parse_status_file: returns 1 for invalid JSON" {
    mkdir -p .claude
    echo "not json" > .claude/test-status.json
    local rc=0
    parse_status_file ".claude/test-status.json" || rc=$?
    [ "$rc" -eq 1 ]
    [ "$__STATUS_RESULT" = "error" ]
}

@test "parse_status_file: returns 1 for missing status field" {
    mkdir -p .claude
    echo '{"summary": "no status"}' > .claude/test-status.json
    local rc=0
    parse_status_file ".claude/test-status.json" || rc=$?
    [ "$rc" -eq 1 ]
    [ "$__STATUS_RESULT" = "error" ]
}

@test "parse_status_file: provides default summary when missing" {
    mkdir -p .claude
    echo '{"status": "complete"}' > .claude/test-status.json
    parse_status_file ".claude/test-status.json"
    [ "$__STATUS_SUMMARY" = "No summary provided" ]
}

@test "parse_status_file: provides default reason when missing" {
    mkdir -p .claude
    echo '{"status": "blocked"}' > .claude/test-status.json
    parse_status_file ".claude/test-status.json"
    [ "$__STATUS_REASON" = "Unknown reason" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# start_file_monitor / stop_file_monitor tests
# ─────────────────────────────────────────────────────────────────────────────

@test "stop_file_monitor: handles no active monitor gracefully" {
    __MONITOR_PID=""
    run stop_file_monitor
    [ "$status" -eq 0 ]
}

@test "start_file_monitor: sets __MONITOR_PID" {
    start_file_monitor "/nonexistent/file" "nonexistent-pattern"
    [ -n "$__MONITOR_PID" ]
    # Clean up
    stop_file_monitor
}

@test "stop_file_monitor: clears __MONITOR_PID" {
    start_file_monitor "/nonexistent/file" "nonexistent-pattern"
    [ -n "$__MONITOR_PID" ]
    stop_file_monitor
    [ -z "$__MONITOR_PID" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Source guard tests
# ─────────────────────────────────────────────────────────────────────────────

@test "common.sh: source guard prevents double-sourcing" {
    # common.sh already sourced in setup. Source it again.
    local first_load="$__BUILDCREW_COMMON_LOADED"
    source_lib "common.sh"
    [ "$__BUILDCREW_COMMON_LOADED" = "$first_load" ]
}
