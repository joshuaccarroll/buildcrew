#!/usr/bin/env bats
# Unit tests for inline UAT (--no-uat flag, run_inline_uat function)

load '../setup.bash'

setup() {
    setup_test_dir

    source_lib "common.sh"
    source_lib "uat_signal.sh"
    source_lib "artifact.sh"

    mkdir -p .buildcrew
    echo "# Test Project" > README.md
    echo "- [ ] Test task" > BACKLOG.md

    # Set up required variables that workflow.sh expects
    export PHASE_RESULT_FILE=".claude/phase-result.json"
    export STATUS_FILE=".claude/workflow-status.json"
    export STOP_FILE=".buildcrew/.stop-workflow"
    export LOCKFILE=".buildcrew/.workflow-lock"
    export VERBOSE=false
    export AUTO_MODE=true
    export COMPLEXITY_AWARE=true
    export MAX_INVOCATIONS=15
    export MAX_PARALLEL=5
    export BATCH_MODE=false
    export DRY_RUN=false
    export SINGLE_TASK=false
    export HUMAN_REVIEW=false
    export GIT_BRANCH=false
    export RESUME_MODE=false
    export TARGET_TASK=""
    export SKIP_SPEC=false
    export STRICT_MODE=true
    export STRICT_EXPLICIT=false
    export FULL_PIPELINE=false
    export PLAN_MODE=false
    export NO_UAT=false

    source_lib "workflow.sh"
}

teardown() {
    # Clean up any UAT workdirs/signals created during tests
    rm -rf "$HOME/.buildcrew/uat-workdirs/test-inline-"* 2>/dev/null || true
    rm -rf "$HOME/.buildcrew/uat-signals/test-inline-"* 2>/dev/null || true
    rm -rf "$HOME/.buildcrew/artifacts/test-inline-"* 2>/dev/null || true
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: set up all mocks needed for run_inline_uat behavioral tests
# ─────────────────────────────────────────────────────────────────────────────

_setup_inline_uat_mocks() {
    # Mock publish_artifact to be a no-op
    publish_artifact() { return 0; }

    # Mock read_manifest to set globals
    read_manifest() {
        __MANIFEST_PROJECT="test-inline"
        __MANIFEST_ARTIFACT_TYPE="cli"
        __MANIFEST_ARTIFACT_PATH="/tmp/test-artifact"
        __MANIFEST_RUN_COMMAND="echo test"
        __MANIFEST_INSTALL_COMMAND=""
        __MANIFEST_HEALTH_CHECK=""
        __MANIFEST_STOP_COMMAND=""
        __MANIFEST_BUILD_TIMESTAMP="$(date +%s)"
        __MANIFEST_BUILD_ITERATION=1
        __MANIFEST_README_HASH="abc123"
        return 0
    }

    # Mock uat_init — create required subdirectories
    uat_init() { mkdir -p .buildcrew scenarios harness results; return 0; }

    # Mock load_uat_config — set defaults
    load_uat_config() { UAT_MAX_RETRIES="${UAT_MAX_RETRIES:-3}"; return 0; }

    # Mock UAT phase functions
    uat_phase_stories() { return 0; }
    uat_phase_scenarios() { return 0; }
    _uat_list_scenarios() { return 0; }
    uat_phase_harness() { return 0; }
    uat_phase_setup_env() { __UAT_ARTIFACT_CONTEXT="test-context"; return 0; }
    uat_phase_execute() { return 0; }
    uat_stop_server() { return 0; }

    # Mock reporting functions
    _uat_print_report() { return 0; }
    _uat_print_retry_context() { return 0; }
    write_uat_context() { return 0; }
    _uat_rebuild_pipeline() { return 0; }
}

# Helper: mock uat_phase_verdict and read_verdict for a pass verdict
_mock_pass_verdict() {
    uat_phase_verdict() {
        local sig_dir="$1"
        local iter="$2"
        mkdir -p "$sig_dir"
        cat > "$sig_dir/verdict.json" << VEOF
{"status":"pass","total":2,"passed":2,"failed":0,"errored":0,"disputed":0,"build_iteration":${iter},"scenarios":[{"scenario":"Test A","status":"pass","summary":"OK"},{"scenario":"Test B","status":"pass","summary":"OK"}]}
VEOF
        return 0
    }
    read_verdict() {
        local sig_dir="$1"
        __VERDICT_STATUS="pass"
        __VERDICT_BUILD_ITERATION=1
        __VERDICT_TOTAL=2
        __VERDICT_PASSED=2
        __VERDICT_FAILED=0
        __VERDICT_ERRORED=0
        __VERDICT_DISPUTED=0
        __VERDICT_SCENARIOS_JSON='[{"scenario":"Test A","status":"pass","summary":"OK"},{"scenario":"Test B","status":"pass","summary":"OK"}]'
        return 0
    }
}

# Helper: mock verdict for disputed-only
_mock_disputed_verdict() {
    uat_phase_verdict() {
        local sig_dir="$1"
        local iter="$2"
        mkdir -p "$sig_dir"
        cat > "$sig_dir/verdict.json" << VEOF
{"status":"disputed","total":2,"passed":1,"failed":0,"errored":0,"disputed":1,"build_iteration":${iter},"scenarios":[{"scenario":"Test A","status":"pass","summary":"OK"},{"scenario":"Test B","status":"disputed","summary":"Ambiguous"}]}
VEOF
        return 0
    }
    read_verdict() {
        local sig_dir="$1"
        __VERDICT_STATUS="disputed"
        __VERDICT_BUILD_ITERATION=1
        __VERDICT_TOTAL=2
        __VERDICT_PASSED=1
        __VERDICT_FAILED=0
        __VERDICT_ERRORED=0
        __VERDICT_DISPUTED=1
        __VERDICT_SCENARIOS_JSON='[{"scenario":"Test A","status":"pass","summary":"OK"},{"scenario":"Test B","status":"disputed","summary":"Ambiguous"}]'
        return 0
    }
}

# Helper: mock verdict for fail
_mock_fail_verdict() {
    uat_phase_verdict() {
        local sig_dir="$1"
        local iter="$2"
        mkdir -p "$sig_dir"
        cat > "$sig_dir/verdict.json" << VEOF
{"status":"fail","total":2,"passed":1,"failed":1,"errored":0,"disputed":0,"build_iteration":${iter},"scenarios":[{"scenario":"Test A","status":"pass","summary":"OK"},{"scenario":"Test B","status":"fail","summary":"Bad output"}]}
VEOF
        return 0
    }
    read_verdict() {
        local sig_dir="$1"
        __VERDICT_STATUS="fail"
        __VERDICT_BUILD_ITERATION=1
        __VERDICT_TOTAL=2
        __VERDICT_PASSED=1
        __VERDICT_FAILED=1
        __VERDICT_ERRORED=0
        __VERDICT_DISPUTED=0
        __VERDICT_SCENARIOS_JSON='[{"scenario":"Test A","status":"pass","summary":"OK"},{"scenario":"Test B","status":"fail","summary":"Bad output"}]'
        return 0
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# parse_args --no-uat flag tests
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --no-uat sets NO_UAT=true" {
    NO_UAT=false
    parse_args --no-uat
    [ "$NO_UAT" = "true" ]
}

@test "parse_args: NO_UAT defaults to false" {
    [ "$NO_UAT" = "false" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# run_inline_uat function existence
# ─────────────────────────────────────────────────────────────────────────────

@test "run_inline_uat: function exists" {
    run type run_inline_uat
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Help text includes --no-uat
# ─────────────────────────────────────────────────────────────────────────────

@test "run_inline_uat: help text includes --no-uat" {
    run grep -- '--no-uat' "$BUILDCREW_ROOT/lib/workflow.sh"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Inline UAT block appears before mark_task_complete
# ─────────────────────────────────────────────────────────────────────────────

@test "process_task_isolated: inline UAT block exists before mark_task_complete" {
    # Find the line numbers of the inline UAT block and mark_task_complete
    local uat_line mark_line
    uat_line=$(grep -n 'run_inline_uat' "$BUILDCREW_ROOT/lib/workflow.sh" | grep -v '^[0-9]*:run_inline_uat()' | grep -v '^[0-9]*:#' | head -1 | cut -d: -f1)
    mark_line=$(grep -n 'mark_task_complete "$task"' "$BUILDCREW_ROOT/lib/workflow.sh" | head -1 | cut -d: -f1)
    # inline UAT call must come before mark_task_complete
    [ -n "$uat_line" ]
    [ -n "$mark_line" ]
    [ "$uat_line" -lt "$mark_line" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# _batch_launch_task forwards --no-uat
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_launch_task: forwards --no-uat when set" {
    run grep -A2 'NO_UAT.*--no-uat' "$BUILDCREW_ROOT/lib/workflow.sh"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Behavioral tests for run_inline_uat
# ─────────────────────────────────────────────────────────────────────────────

@test "run_inline_uat: returns 0 on all-pass verdict" {
    _setup_inline_uat_mocks
    _mock_pass_verdict

    local rc=0
    run_inline_uat "test-inline-pass-$$" "test task" "standard" || rc=$?
    [ "$rc" -eq 0 ]
}

@test "run_inline_uat: returns 2 on disputed-only verdict" {
    _setup_inline_uat_mocks
    _mock_disputed_verdict

    local rc=0
    run_inline_uat "test-inline-disp-$$" "test task" "standard" || rc=$?
    [ "$rc" -eq 2 ]
}

@test "run_inline_uat: returns 1 after max retries exhausted" {
    _setup_inline_uat_mocks
    _mock_fail_verdict
    UAT_MAX_RETRIES=1

    local rc=0
    run_inline_uat "test-inline-retry-$$" "test task" "standard" || rc=$?
    [ "$rc" -eq 1 ]
}

@test "run_inline_uat: stops server after execute" {
    _setup_inline_uat_mocks
    _mock_pass_verdict

    local __stop_server_called=false
    uat_stop_server() { __stop_server_called=true; return 0; }

    run_inline_uat "test-inline-stop-$$" "test task" "standard" || true
    [ "$__stop_server_called" = "true" ]
}

@test "run_inline_uat: restores working directory on success" {
    _setup_inline_uat_mocks
    _mock_pass_verdict

    local before_dir
    before_dir="$(pwd)"
    run_inline_uat "test-inline-pwd-ok-$$" "test task" "standard" || true
    local after_dir
    after_dir="$(pwd)"
    [ "$before_dir" = "$after_dir" ]
}

@test "run_inline_uat: restores working directory on failure" {
    _setup_inline_uat_mocks
    _mock_fail_verdict
    UAT_MAX_RETRIES=1

    local before_dir
    before_dir="$(pwd)"
    run_inline_uat "test-inline-pwd-fail-$$" "test task" "standard" || true
    local after_dir
    after_dir="$(pwd)"
    [ "$before_dir" = "$after_dir" ]
}

@test "run_inline_uat: skips when README.md not found (via process_task_isolated gating)" {
    # The README check is in process_task_isolated, not run_inline_uat itself.
    # Verify the gating logic: when no README.md exists, run_inline_uat is NOT called.
    rm -f README.md
    # The code path in process_task_isolated:
    #   if [[ -f "README.md" ]]; then ... run_inline_uat ... else print_info "No README.md found" fi
    # Verify this structural property
    local gate_line
    gate_line=$(grep -n 'if \[\[ -f "README.md" \]\]' "$BUILDCREW_ROOT/lib/workflow.sh" | head -1)
    [ -n "$gate_line" ]
    local skip_line
    skip_line=$(grep -n 'No README.md found.*skipping inline UAT' "$BUILDCREW_ROOT/lib/workflow.sh" | head -1)
    [ -n "$skip_line" ]
}
