#!/usr/bin/env bats
# TDD tests for Ctrl+C / SIGINT fix in batch dispatch loop
# AC-01: _batch_parallel_cleanup disarms EXIT trap on entry (trap '' INT TERM EXIT)
# AC-02: _batch_parallel_cleanup ends with exit 130 (not return 130)
# AC-03: foreground sleep calls in _batch_dispatch_loop replaced with background sleep + wait
# AC-04: foreground sleep in _batch_handle_rate_limit_pause replaced with background sleep + wait
# AC-05: _batch_resume clears traps after _batch_dispatch_loop returns (trap - EXIT INT TERM)
# AC-06: enter_batch_mode clears traps after _batch_dispatch_loop returns (trap - EXIT INT TERM)
# AC-07: _batch_parallel_cleanup exits 130 and does not re-invoke itself (no EXIT recursion)

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "common.sh"
    source_lib "workflow.sh"
}

teardown() {
    jobs -p 2>/dev/null | xargs kill -9 2>/dev/null || true
    wait 2>/dev/null || true
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: _batch_parallel_cleanup disarms EXIT trap on entry
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01: _batch_parallel_cleanup first trap statement includes EXIT" {
    local func_body
    func_body=$(declare -f _batch_parallel_cleanup)

    # Extract the first executable (non-comment, non-blank) line inside the function
    local first_exec
    first_exec=$(printf '%s\n' "$func_body" | tail -n +3 | grep -v '^\s*$' | grep -v '^\s*#' | head -1 | sed 's/^[[:space:]]*//')

    # Must be a trap '' ... line that blocks INT TERM and EXIT
    [[ "$first_exec" == trap*\'\'* ]] || { echo "Not a trap '' statement: $first_exec"; return 1; }
    [[ "$first_exec" == *INT* ]]       || { echo "Missing INT: $first_exec"; return 1; }
    [[ "$first_exec" == *TERM* ]]      || { echo "Missing TERM: $first_exec"; return 1; }
    [[ "$first_exec" == *EXIT* ]]      || { echo "Missing EXIT: $first_exec"; return 1; }
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: _batch_parallel_cleanup ends with exit 130 (not return 130)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02a: _batch_parallel_cleanup last exit/return statement is 'exit 130' only" {
    local func_body
    func_body=$(declare -f _batch_parallel_cleanup)

    # The last line with exit/return must be exactly "exit 130" — no "return 130 ... || exit 130"
    local last_exit_line
    last_exit_line=$(printf '%s\n' "$func_body" | grep -E '^\s*(exit|return) ' | tail -1 | sed 's/^[[:space:]]*//')

    [[ "$last_exit_line" == "exit 130" ]] || { echo "Last exit/return is not plain 'exit 130': '$last_exit_line'"; return 1; }
}

@test "AC-02b: _batch_parallel_cleanup does not use 'return 130'" {
    local func_body
    func_body=$(declare -f _batch_parallel_cleanup)

    # Must NOT contain return 130 (the old fallback pattern)
    [[ "$func_body" != *"return 130"* ]] || { echo "_batch_parallel_cleanup still uses return 130"; return 1; }
}

@test "AC-02c: calling _batch_parallel_cleanup does not execute any line after it (true exit, not return)" {
    # If cleanup uses 'return 130' the next echo would run; if it uses 'exit 130' it would not.
    run bash -c "
        set +e
        source '$BUILDCREW_ROOT/lib/common.sh' 2>/dev/null
        source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null
        _batch_mark_task() { :; }
        _batch_stop_heartbeat() { :; }
        clear_workflow_state() { :; }
        print_warning() { :; }
        print_info() { :; }
        sleep() { :; }
        kill() { :; }
        BATCH_MANIFEST=''
        LOCKFILE=''
        _batch_pids=()
        _batch_parallel_cleanup
        echo AFTER_CLEANUP_REACHED
    "
    # Must exit 130 AND must NOT print AFTER_CLEANUP_REACHED
    [ "$status" -eq 130 ]
    [[ "$output" != *"AFTER_CLEANUP_REACHED"* ]] || { echo "Code after _batch_parallel_cleanup was reached — cleanup used return, not exit"; return 1; }
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: sleep calls in _batch_dispatch_loop use background pattern
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03a: _batch_dispatch_loop contains no bare 'sleep 3' foreground calls" {
    local func_body
    func_body=$(declare -f _batch_dispatch_loop)

    # The only sleep 3 calls must be background (sleep 3 &)
    # A bare "sleep 3" without & would match this pattern — we must not find it
    # We check: no line has "sleep 3" that is NOT followed by " &" or "&"
    local bare_sleep
    bare_sleep=$(printf '%s\n' "$func_body" | grep -E '^\s*sleep [0-9]' | grep -v '&' || true)
    [ -z "$bare_sleep" ] || { echo "Found bare foreground sleep in _batch_dispatch_loop: $bare_sleep"; return 1; }
}

@test "AC-03b: _batch_dispatch_loop contains background sleep pattern (sleep N &)" {
    local func_body
    func_body=$(declare -f _batch_dispatch_loop)

    # Must contain "sleep <number_or_var> &" — not just any sleep followed by any &
    local bg_sleep
    bg_sleep=$(printf '%s\n' "$func_body" | grep -E 'sleep [0-9$][^ ]* &')
    [ -n "$bg_sleep" ] || { echo "No 'sleep N &' background pattern found in _batch_dispatch_loop"; return 1; }
}

@test "AC-03c: _batch_dispatch_loop contains 'wait \$!' after background sleep" {
    local func_body
    func_body=$(declare -f _batch_dispatch_loop)

    # Must contain wait $! pattern (background sleep reaping)
    [[ "$func_body" == *'wait $!'* ]] || { echo "No 'wait \$!' found in _batch_dispatch_loop"; return 1; }
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: sleep in _batch_handle_rate_limit_pause uses background pattern
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04a: _batch_handle_rate_limit_pause contains no bare foreground sleep for backoff" {
    local func_body
    func_body=$(declare -f _batch_handle_rate_limit_pause)

    # Any sleep "$backoff" or sleep "\$backoff" must be backgrounded
    local bare_sleep
    bare_sleep=$(printf '%s\n' "$func_body" | grep -E '^\s*sleep .*backoff' | grep -v '&' || true)
    [ -z "$bare_sleep" ] || { echo "Found bare foreground backoff sleep: $bare_sleep"; return 1; }
}

@test "AC-04b: _batch_handle_rate_limit_pause background sleep pattern includes wait" {
    local func_body
    func_body=$(declare -f _batch_handle_rate_limit_pause)

    # If sleep is backgrounded, must have wait $! nearby
    [[ "$func_body" == *'wait $!'* ]] || { echo "No 'wait \$!' found in _batch_handle_rate_limit_pause"; return 1; }
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: _batch_resume clears traps after _batch_dispatch_loop returns
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-05: _batch_resume contains 'trap - EXIT INT TERM' after _batch_dispatch_loop call" {
    local func_body
    func_body=$(declare -f _batch_resume)

    # Must contain trap - EXIT INT TERM (order may vary)
    local has_clear_trap=false
    while IFS= read -r line; do
        local stripped
        stripped=$(printf '%s\n' "$line" | sed 's/^[[:space:]]*//')
        if [[ "$stripped" == trap*-*EXIT* && "$stripped" == *INT* && "$stripped" == *TERM* ]]; then
            has_clear_trap=true
            break
        fi
        if [[ "$stripped" == trap*-*INT* && "$stripped" == *TERM* && "$stripped" == *EXIT* ]]; then
            has_clear_trap=true
            break
        fi
    done <<< "$func_body"

    [ "$has_clear_trap" = true ] || { echo "_batch_resume missing 'trap - EXIT INT TERM'"; return 1; }
}

@test "AC-05b: _batch_resume 'trap - EXIT INT TERM' appears after _batch_dispatch_loop call" {
    local func_body
    func_body=$(declare -f _batch_resume)

    # Find line numbers of dispatch_loop call and trap - line
    local dispatch_line trap_line
    dispatch_line=$(printf '%s\n' "$func_body" | grep -n '_batch_dispatch_loop' | head -1 | cut -d: -f1)
    trap_line=$(printf '%s\n' "$func_body" | grep -n 'trap.*-.*INT\|trap.*-.*EXIT' | tail -1 | cut -d: -f1)

    [[ -n "$dispatch_line" ]] || { echo "_batch_dispatch_loop call not found in _batch_resume"; return 1; }
    [[ -n "$trap_line" ]]    || { echo "trap - disarm not found in _batch_resume"; return 1; }
    # trap - line must come after the dispatch_loop call
    [ "$trap_line" -gt "$dispatch_line" ] || { echo "trap - ($trap_line) must be after dispatch_loop ($dispatch_line)"; return 1; }
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-06: enter_batch_mode clears traps after _batch_dispatch_loop returns
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-06: enter_batch_mode contains 'trap - EXIT INT TERM' after _batch_dispatch_loop call" {
    local func_body
    func_body=$(declare -f enter_batch_mode)

    local has_clear_trap=false
    while IFS= read -r line; do
        local stripped
        stripped=$(printf '%s\n' "$line" | sed 's/^[[:space:]]*//')
        if [[ "$stripped" == trap*-*EXIT* && "$stripped" == *INT* && "$stripped" == *TERM* ]]; then
            has_clear_trap=true
            break
        fi
        if [[ "$stripped" == trap*-*INT* && "$stripped" == *TERM* && "$stripped" == *EXIT* ]]; then
            has_clear_trap=true
            break
        fi
    done <<< "$func_body"

    [ "$has_clear_trap" = true ] || { echo "enter_batch_mode missing 'trap - EXIT INT TERM'"; return 1; }
}

@test "AC-06b: enter_batch_mode 'trap - EXIT INT TERM' appears after _batch_dispatch_loop call" {
    local func_body
    func_body=$(declare -f enter_batch_mode)

    local dispatch_line trap_line
    dispatch_line=$(printf '%s\n' "$func_body" | grep -n '_batch_dispatch_loop' | head -1 | cut -d: -f1)
    trap_line=$(printf '%s\n' "$func_body" | grep -n 'trap.*-.*INT\|trap.*-.*EXIT' | tail -1 | cut -d: -f1)

    [[ -n "$dispatch_line" ]] || { echo "_batch_dispatch_loop call not found in enter_batch_mode"; return 1; }
    [[ -n "$trap_line" ]]    || { echo "trap - disarm not found in enter_batch_mode"; return 1; }
    [ "$trap_line" -gt "$dispatch_line" ] || { echo "trap - ($trap_line) must be after dispatch_loop ($dispatch_line)"; return 1; }
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-07: _batch_parallel_cleanup does not recurse via EXIT trap
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-07: _batch_parallel_cleanup 'trap '' EXIT' appears before 'exit 130' to prevent EXIT-trap recursion" {
    # When cleanup calls exit 130, the EXIT trap must NOT re-fire cleanup.
    # Guaranteed by trap '' EXIT being set on entry — EXIT must be in that first trap line.
    local func_body
    func_body=$(declare -f _batch_parallel_cleanup)

    # Find first "trap ''" line that also includes EXIT
    local trap_with_exit_line exit_line
    trap_with_exit_line=$(printf '%s\n' "$func_body" | grep -n "trap ''" | grep 'EXIT' | head -1 | cut -d: -f1)
    exit_line=$(printf '%s\n' "$func_body" | grep -n 'exit 130' | head -1 | cut -d: -f1)

    [[ -n "$trap_with_exit_line" ]] || { echo "No 'trap '' ... EXIT' line found in _batch_parallel_cleanup"; return 1; }
    [[ -n "$exit_line" ]]           || { echo "exit 130 not found in _batch_parallel_cleanup"; return 1; }
    # trap disarm must precede exit 130
    [ "$trap_with_exit_line" -lt "$exit_line" ] || { echo "trap '' EXIT ($trap_with_exit_line) must precede exit 130 ($exit_line)"; return 1; }
}
