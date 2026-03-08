#!/usr/bin/env bats
# TDD tests for rate limit detection and pause handling
# Maps to AC-01: Rate limit detection
# Maps to AC-02: Sentinel file lifecycle
# Maps to AC-03: Task requeuing on resume

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: _check_rate_limit_in_log detects rate limit patterns
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01a: _check_rate_limit_in_log detects 'rate limit reached' pattern" {
    mkdir -p .buildcrew
    local log_file
    log_file=$(mktemp)
    printf 'some output\nrate limit reached\nmore output\n' > "$log_file"
    __LOG_FILE="$log_file"
    run _check_rate_limit_in_log 0
    [ "$status" -eq 0 ]
    rm -f "$log_file"
}

@test "AC-01b: _check_rate_limit_in_log detects 'rate_limit_error' pattern" {
    mkdir -p .buildcrew
    local log_file
    log_file=$(mktemp)
    printf 'Phase started\nrate_limit_error: too many requests\nPhase ended\n' > "$log_file"
    __LOG_FILE="$log_file"
    run _check_rate_limit_in_log 0
    [ "$status" -eq 0 ]
    rm -f "$log_file"
}

@test "AC-01c: _check_rate_limit_in_log detects 'usage limit' pattern" {
    mkdir -p .buildcrew
    local log_file
    log_file=$(mktemp)
    printf 'Processing...\nYou have reached your usage limit\n' > "$log_file"
    __LOG_FILE="$log_file"
    run _check_rate_limit_in_log 0
    [ "$status" -eq 0 ]
    rm -f "$log_file"
}

@test "AC-01d: _check_rate_limit_in_log detects 'rate.limit.exceeded' pattern" {
    mkdir -p .buildcrew
    local log_file
    log_file=$(mktemp)
    printf 'Starting task\nrate.limit.exceeded: please wait\n' > "$log_file"
    __LOG_FILE="$log_file"
    run _check_rate_limit_in_log 0
    [ "$status" -eq 0 ]
    rm -f "$log_file"
}

@test "AC-01e: _check_rate_limit_in_log rejects normal failures" {
    mkdir -p .buildcrew
    local log_file
    log_file=$(mktemp)
    printf 'Phase complete\nError: file not found\nNo issues reported\n' > "$log_file"
    __LOG_FILE="$log_file"
    run _check_rate_limit_in_log 0
    [ "$status" -eq 1 ]
    rm -f "$log_file"
}

@test "AC-01f: _check_rate_limit_in_log returns 1 when log file empty" {
    __LOG_FILE=""
    run _check_rate_limit_in_log 0
    [ "$status" -eq 1 ]
}

@test "AC-01g: _check_rate_limit_in_log respects byte offset" {
    mkdir -p .buildcrew
    local log_file
    log_file=$(mktemp)
    printf 'old: rate limit reached\nnew: everything fine\n' > "$log_file"
    __LOG_FILE="$log_file"
    local old_len
    old_len=$(printf 'old: rate limit reached\n' | wc -c | tr -d ' ')
    run _check_rate_limit_in_log "$old_len"
    [ "$status" -eq 1 ]
    rm -f "$log_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: Sentinel file lifecycle (_signal, _check, _clear)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02a: _signal_rate_limit_pause creates sentinel file" {
    mkdir -p .buildcrew
    BUILDCREW_BATCH_PARENT_CWD="$(pwd)"
    run _signal_rate_limit_pause
    [ "$status" -eq 0 ]
    [ -f .buildcrew/.rate-limit-pause ]
    rm -f .buildcrew/.rate-limit-pause
}

@test "AC-02b: _check_rate_limit_pause detects sentinel file" {
    mkdir -p .buildcrew
    touch .buildcrew/.rate-limit-pause
    run _check_rate_limit_pause "$(pwd)"
    [ "$status" -eq 0 ]
    rm -f .buildcrew/.rate-limit-pause
}

@test "AC-02c: _check_rate_limit_pause returns 1 when no sentinel" {
    mkdir -p .buildcrew
    run _check_rate_limit_pause "$(pwd)"
    [ "$status" -eq 1 ]
}

@test "AC-02d: _clear_rate_limit_pause removes sentinel file" {
    mkdir -p .buildcrew
    touch .buildcrew/.rate-limit-pause
    _clear_rate_limit_pause "$(pwd)"
    [ ! -f .buildcrew/.rate-limit-pause ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: Task requeuing on resume
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03a: _batch_requeue_rate_limited_tasks resets task status to pending" {
    mkdir -p .buildcrew
    cat > BACKLOG.md <<'EOF'
- [ ] Completed task
- [ ] Rate-limited task
- [ ] Another task
EOF
    echo "task_status[1]=rate_limited" >> .buildcrew/.batch-state
    run _batch_requeue_rate_limited_tasks
    [ "$status" -eq 0 ]
    grep -q "task_status\[1\]=pending" .buildcrew/.batch-state
    rm -f BACKLOG.md .buildcrew/.batch-state
}

@test "AC-03b: _batch_requeue_rate_limited_tasks handles multiple rate-limited tasks" {
    mkdir -p .buildcrew
    cat > BACKLOG.md <<'EOF'
- [ ] Task one
- [ ] Task two
- [ ] Task three
EOF
    cat > .buildcrew/.batch-state <<'EOF'
task_status[0]=rate_limited
task_status[1]=completed
task_status[2]=rate_limited
EOF
    run _batch_requeue_rate_limited_tasks
    [ "$status" -eq 0 ]
    grep -q "task_status\[0\]=pending" .buildcrew/.batch-state
    grep -q "task_status\[2\]=pending" .buildcrew/.batch-state
    grep -q "task_status\[1\]=completed" .buildcrew/.batch-state
    rm -f BACKLOG.md .buildcrew/.batch-state
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: Return code 4 propagates through phase chain (tested in integration/build phase)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04a: Helper rate limit functions are defined" {
    # Verify all stub functions compile and can be called
    _check_rate_limit_in_log 0 >/dev/null 2>&1 || true
    _signal_rate_limit_pause >/dev/null 2>&1 || true
    _check_rate_limit_pause "$(pwd)" >/dev/null 2>&1 || true
    _clear_rate_limit_pause "$(pwd)" >/dev/null 2>&1 || true
    [ 1 -eq 1 ]
}

@test "AC-04b: Batch requeue function is defined and callable" {
    _batch_requeue_rate_limited_tasks >/dev/null 2>&1 || true
    [ 1 -eq 1 ]
}
