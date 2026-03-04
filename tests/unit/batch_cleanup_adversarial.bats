#!/usr/bin/env bats
# Adversarial and edge-case tests for _batch_parallel_cleanup
# Separate from TDD scaffold — covers scenarios TDD does not exercise.

load '../setup.bash'

setup() {
    setup_test_dir

    source_lib "common.sh"
    source_lib "workflow.sh"

    # Required globals
    BATCH_MANIFEST="$TEST_DIR/batch-manifest.json"
    LOCKFILE="$TEST_DIR/lockfile"
    STOP_FILE="$TEST_DIR/.buildcrew/stop"
    mkdir -p "$TEST_DIR/.buildcrew"
    touch "$LOCKFILE"

    # Stub helper functions
    _batch_mark_task() {
        echo "MARK_TASK:$1:$2:$3" >> "$TEST_DIR/mark_task.log"
    }
    _batch_stop_heartbeat() { :; }
    clear_workflow_state() { :; }
    print_warning() { :; }
    print_info() { :; }
}

teardown() {
    jobs -p 2>/dev/null | xargs kill -9 2>/dev/null || true
    wait 2>/dev/null || true
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# EDGE-01: Sparse array indices
# ─────────────────────────────────────────────────────────────────────────────

@test "EDGE-01: sparse _batch_pids array indices do not cause errors" {
    sleep 300 &
    local p1=$!
    sleep 300 &
    local p2=$!
    sleep 300 &
    local p3=$!

    _batch_pids=()
    _batch_pids[0]=$p1
    _batch_pids[3]=$p2
    _batch_pids[7]=$p3

    sleep() { :; }
    rm -f "$TEST_DIR/mark_task.log"

    _batch_parallel_cleanup || true

    # All three processes should be dead
    ! kill -0 "$p1" 2>/dev/null
    ! kill -0 "$p2" 2>/dev/null
    ! kill -0 "$p3" 2>/dev/null

    # manifest_idx should be i+1 for each present index: 1, 4, 8
    [ -f "$TEST_DIR/mark_task.log" ]
    grep -q "MARK_TASK:1:" "$TEST_DIR/mark_task.log"
    grep -q "MARK_TASK:4:" "$TEST_DIR/mark_task.log"
    grep -q "MARK_TASK:8:" "$TEST_DIR/mark_task.log"
}

# ─────────────────────────────────────────────────────────────────────────────
# EDGE-02: All entries are empty strings
# ─────────────────────────────────────────────────────────────────────────────

@test "EDGE-02: _batch_pids with only empty strings skips all entries" {
    _batch_pids=()
    _batch_pids[0]=""
    _batch_pids[1]=""
    _batch_pids[2]=""

    sleep() { :; }
    rm -f "$TEST_DIR/mark_task.log"

    run bash -c "
        source '$BUILDCREW_ROOT/lib/common.sh' 2>/dev/null
        source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null
        _batch_mark_task() { echo \"MARK:\$1\" >> '$TEST_DIR/mark_task.log'; }
        _batch_stop_heartbeat() { :; }
        clear_workflow_state() { :; }
        print_warning() { :; }
        print_info() { :; }
        sleep() { :; }
        BATCH_MANIFEST='$TEST_DIR/batch-manifest.json'
        LOCKFILE='$TEST_DIR/lockfile'
        _batch_pids=()
        _batch_pids[0]=''
        _batch_pids[1]=''
        _batch_pids[2]=''
        _batch_parallel_cleanup
    "

    # No marking should occur for empty-string entries
    [ ! -f "$TEST_DIR/mark_task.log" ]
    [ "$status" -eq 130 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# EDGE-03: Mix of empty strings, live PIDs, and sparse indices
# ─────────────────────────────────────────────────────────────────────────────

@test "EDGE-03: mixed empty-string and live PID entries handled correctly" {
    sleep 300 &
    local live1=$!
    sleep 300 &
    local live2=$!

    _batch_pids=()
    _batch_pids[0]=""
    _batch_pids[1]=$live1
    _batch_pids[3]=$live2

    sleep() { :; }
    rm -f "$TEST_DIR/mark_task.log"

    _batch_parallel_cleanup || true

    # Live processes should be dead
    ! kill -0 "$live1" 2>/dev/null
    ! kill -0 "$live2" 2>/dev/null

    # Only non-empty entries get marked (indices 1 and 3 -> manifest_idx 2 and 4)
    [ -f "$TEST_DIR/mark_task.log" ]
    ! grep -q "MARK_TASK:1:" "$TEST_DIR/mark_task.log"
    grep -q "MARK_TASK:2:" "$TEST_DIR/mark_task.log"
    grep -q "MARK_TASK:4:" "$TEST_DIR/mark_task.log"
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-01: Self-PID guard — _batch_pids contains $$
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-01: cleanup skips orchestrator PID in force-kill loop" {
    # Verify the guard check exists in the function body
    local func_body
    func_body=$(declare -f _batch_parallel_cleanup)

    # The implementation must have a guard that skips $$ in the per-PID SIGKILL loop
    [[ "$func_body" == *'== "$$"'* ]] || [[ "$func_body" == *'== $$'* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-02: Double invocation does not crash
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-02: calling cleanup twice does not crash" {
    run bash -c "
        source '$BUILDCREW_ROOT/lib/common.sh' 2>/dev/null
        source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null
        _batch_mark_task() { :; }
        _batch_stop_heartbeat() { :; }
        clear_workflow_state() { :; }
        print_warning() { :; }
        print_info() { :; }
        sleep() { :; }
        BATCH_MANIFEST='$TEST_DIR/batch-manifest.json'
        LOCKFILE='$TEST_DIR/lockfile'
        _batch_pids=()

        # First invocation — use return instead of exit to stay in shell
        # But the function uses 'return 130 || exit 130', so in a function context
        # we need to call it as a function. We'll use a wrapper.
        wrapper() { _batch_parallel_cleanup; }
        wrapper
        # If we get here, first call returned (didn't exit)
        wrapper
        echo 'SURVIVED_DOUBLE_CALL'
    "
    # Either exits 130 (from first call) or survives both — both are acceptable
    # The key assertion: no crash (status is 130 or 0, not 1/2/127/etc)
    [[ "$status" -eq 130 || "$status" -eq 0 ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-03: LOCKFILE already deleted
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-03: cleanup with already-deleted LOCKFILE does not error" {
    rm -f "$LOCKFILE"

    run bash -c "
        source '$BUILDCREW_ROOT/lib/common.sh' 2>/dev/null
        source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null
        _batch_mark_task() { :; }
        _batch_stop_heartbeat() { :; }
        clear_workflow_state() { :; }
        print_warning() { :; }
        print_info() { :; }
        sleep() { :; }
        BATCH_MANIFEST='$TEST_DIR/batch-manifest.json'
        LOCKFILE='$TEST_DIR/lockfile'
        _batch_pids=()
        _batch_parallel_cleanup
    "
    [ "$status" -eq 130 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-04: BATCH_MANIFEST unset
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-04: cleanup with empty BATCH_MANIFEST does not crash" {
    run bash -c "
        source '$BUILDCREW_ROOT/lib/common.sh' 2>/dev/null
        source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null
        _batch_mark_task() { :; }
        _batch_stop_heartbeat() { :; }
        clear_workflow_state() { :; }
        print_warning() { :; }
        print_info() { :; }
        sleep() { :; }
        BATCH_MANIFEST=''
        LOCKFILE='$TEST_DIR/lockfile'
        _batch_pids=()
        _batch_parallel_cleanup
    "
    [ "$status" -eq 130 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# ADV-05: trap '' INT TERM blocks re-entrant SIGTERM
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-05: trap guard blocks both INT and TERM signals during cleanup" {
    # Verify the trap line blocks both INT and TERM
    local func_body
    func_body=$(declare -f _batch_parallel_cleanup)

    # First executable line must trap both INT and TERM
    local first_exec
    first_exec=$(echo "$func_body" | tail -n +3 | grep -v '^\s*$' | grep -v '^\s*#' | head -1 | sed 's/^[[:space:]]*//')

    [[ "$first_exec" == *INT* ]]
    [[ "$first_exec" == *TERM* ]]
    [[ "$first_exec" == trap*\'\'* ]]
}
