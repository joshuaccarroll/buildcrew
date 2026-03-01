#!/usr/bin/env bats
# Unit tests for lib/common.sh extracted functions

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "common.sh"
}

teardown() {
    teardown_test_dir
    __LOG_FILE=""   # Reset log state between tests
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

# ─────────────────────────────────────────────────────────────────────────────
# Logging: log_init / log_msg tests
# ─────────────────────────────────────────────────────────────────────────────

@test "log_init: creates .buildcrew/logs/ directory" {
    log_init
    [ -d ".buildcrew/logs" ]
}

@test "log_init: sets __LOG_FILE to a non-empty value" {
    log_init
    [ -n "$__LOG_FILE" ]
}

@test "log_init: writes a header line (log file is non-empty after init)" {
    log_init
    [ -s "$__LOG_FILE" ]
}

@test "log_msg: writes timestamped entry to log file" {
    log_init
    log_msg "test message"
    run grep "test message" "$__LOG_FILE"
    [ "$status" -eq 0 ]
}

@test "log_msg: is a no-op when __LOG_FILE is empty" {
    __LOG_FILE=""
    log_msg "should not create a file"
    run find . -name "*.log" -type f
    [ -z "$output" ]
}

@test "print_success: writes to log file when log_init has been called" {
    log_init
    print_success "all good"
    run grep "all good" "$__LOG_FILE"
    [ "$status" -eq 0 ]
}

@test "print_debug: logs to file even when VERBOSE=false" {
    log_init
    VERBOSE=false
    print_debug "hidden from terminal"
    run grep "hidden from terminal" "$__LOG_FILE"
    [ "$status" -eq 0 ]
}

@test "print_debug: does NOT write to stdout when VERBOSE=false" {
    log_init
    VERBOSE=false
    run print_debug "hidden from terminal"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "log entries have ANSI codes stripped" {
    log_init
    print_success "clean text"
    local esc
    esc=$(printf '\033')
    run grep "${esc}" "$__LOG_FILE"
    [ "$status" -eq 1 ]  # grep returns 1 when no match — i.e., no ANSI codes found
}

# ─────────────────────────────────────────────────────────────────────────────
# load_project_context: boundary-aware truncation (Change 3)
# ─────────────────────────────────────────────────────────────────────────────

@test "load_project_context: boundary-aware truncation stops at last section marker" {
    mkdir -p .buildcrew/context
    # Build a string >10KB with a --- boundary near the 10KB limit
    # First section: ~9900 bytes of content followed by ---
    python3 -c "
import sys
# Section 1: filler up to ~9900 bytes
s = 'x' * 100 + '\n'
block = s * 97  # ~9800 bytes
print('## Section One')
print(block, end='')
print('---')
print('## Section Two (should be truncated)')
print('y' * 500)
" > .buildcrew/context/users.md
    output=$(load_project_context 2>/dev/null)
    [[ "$output" == *"[truncated]"* ]]
    # Must not contain content from Section Two
    [[ "$output" != *"should be truncated"* ]]
}

@test "load_project_context: falls back to last-newline truncation when no section markers" {
    mkdir -p .buildcrew/context
    # A single long line repeated to exceed 10KB, no --- or ## markers
    python3 -c "print('a' * 200 + '\n', end='')" | python3 -c "
import sys
line = sys.stdin.read()
# Write enough lines to exceed 10KB but none start with --- or ##
content = ('content: ' + 'z' * 200 + '\n') * 60
sys.stdout.write(content)
" > .buildcrew/context/users.md
    output=$(load_project_context 2>/dev/null)
    [[ "$output" == *"[truncated]"* ]]
}
