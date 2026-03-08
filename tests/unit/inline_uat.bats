#!/usr/bin/env bats
# Unit tests for UAT (--no-uat flag, run_inline_uat function, post-completion triggers)

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
    # Behavioral: invoke parse_args --help and assert on stdout
    run parse_args --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--no-uat"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# UAT is NOT in process_task_isolated (removed inline UAT)
# ─────────────────────────────────────────────────────────────────────────────

@test "process_task_isolated: does NOT contain inline UAT block" {
    # Semi-structural via declare -f: tests the function as loaded into the shell (sourced in setup()).
    # Fully behavioral invocation is infeasible: process_task_isolated has ~20 dependencies
    # (git ops, claude invocations, lock files) that cannot be mocked in a unit test.
    local body
    body="$(declare -f process_task_isolated)"
    [[ "$body" != *"── Inline UAT ──"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Post-completion UAT trigger exists in main()
# ─────────────────────────────────────────────────────────────────────────────

@test "main: post-completion UAT trigger exists after 'All backlog tasks processed'" {
    # Semi-structural via declare -f: tests the loaded main() function body (sourced in setup()).
    # Calling main() directly is infeasible: it runs the entire workflow orchestrator.
    local body success_pos uat_pos
    body="$(declare -f main)"
    success_pos=$(echo "$body" | grep -n 'All backlog tasks processed' | head -1 | cut -d: -f1)
    uat_pos=$(echo "$body" | grep -n 'run_inline_uat' | tail -1 | cut -d: -f1)
    [ -n "$success_pos" ]
    [ -n "$uat_pos" ]
    [ "$uat_pos" -gt "$success_pos" ]
}

@test "main: post-completion UAT is guarded by NO_UAT and failed and README and SINGLE_TASK" {
    # Semi-structural via declare -f: A behavioral test would require calling main() with 4
    # different configurations, which is infeasible (full orchestrator with git ops, claude, etc.).
    local body
    body="$(declare -f main)"
    [[ "$body" == *'NO_UAT'*'failed'*'README'*'SINGLE_TASK'* ]]
}

@test "main: post-completion UAT skips when failed > 0 with info message" {
    # Semi-structural via declare -f: same rationale as previous test.
    local body="$(declare -f main)"
    [[ "$body" == *'Skipping UAT'*'task(s) failed'* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Parallel post-completion UAT trigger in _batch_post_completion
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_post_completion: UAT trigger exists after post-build verification" {
    # Semi-structural via declare -f: _batch_post_completion requires batch mode infrastructure
    # (worktrees, merge operations, git state) that cannot be mocked in a unit test.
    local body post_build_pos uat_pos
    body="$(declare -f _batch_post_completion)"
    post_build_pos=$(echo "$body" | grep -n 'Post-build verification passed\|post.build.*verif' | head -1 | cut -d: -f1)
    uat_pos=$(echo "$body" | grep -n 'run_inline_uat' | head -1 | cut -d: -f1)
    [ -n "$post_build_pos" ]
    [ -n "$uat_pos" ]
    [ "$uat_pos" -gt "$post_build_pos" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# _batch_launch_task forwards --no-uat
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_launch_task: forwards --no-uat when set" {
    # Semi-structural via declare -f: _batch_launch_task spawns background subprocesses in worktrees
    # and manages batch coordination state; a mock binary approach is impractical.
    local body
    body="$(declare -f _batch_launch_task)"
    [[ "$body" == *'--no-uat'* ]]
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

# ─────────────────────────────────────────────────────────────────────────────
# process_task_isolated no longer returns exit code 2
# ─────────────────────────────────────────────────────────────────────────────

@test "main task loop: no task_result -eq 2 handling" {
    # Semi-structural via declare -f: process_task_isolated/main cannot be invoked due to side effects.
    # With inline UAT removed, neither function should check for exit code 2.
    local body main_body
    body="$(declare -f process_task_isolated)"
    [[ "$body" != *'task_result -eq 2'* ]]
    main_body="$(declare -f main)"
    [[ "$main_body" != *'task_result -eq 2'* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Standalone buildcrew uat (structural tests)
# ─────────────────────────────────────────────────────────────────────────────

@test "cmd_uat: standalone mode sources workflow.sh" {
    # cmd_uat is defined in bin/buildcrew which cannot be sourced directly (no BASH_SOURCE guard).
    # Extract the function via sed, load it, and verify it references run_inline_uat (from workflow.sh).
    run bash -c '
      source "'"$BUILDCREW_ROOT"'/lib/common.sh" 2>/dev/null || true
      source "'"$BUILDCREW_ROOT"'/lib/workflow.sh" 2>/dev/null || true
      eval "$(sed -n "/^cmd_uat()/,/^}/p" "'"$BUILDCREW_ROOT"'/bin/buildcrew")"
      type cmd_uat && declare -f cmd_uat | grep -q run_inline_uat
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "cmd_uat: standalone mode exits 1 without README.md" {
    # Behavioral: extract cmd_uat and invoke it without a README.md; verify exit 1 + error message.
    # The README check fires before any sourcing (line 2231 in bin/buildcrew), so no complex deps arise.
    rm -f README.md
    run bash -c '
      export BUILDCREW_HOME="'"$BUILDCREW_ROOT"'"
      source "'"$BUILDCREW_ROOT"'/lib/common.sh" 2>/dev/null || true
      source "'"$BUILDCREW_ROOT"'/lib/version.sh" 2>/dev/null || true
      source "'"$BUILDCREW_ROOT"'/lib/update.sh" 2>/dev/null || true
      eval "$(sed -n "/^cmd_uat()/,/^}/p" "'"$BUILDCREW_ROOT"'/bin/buildcrew")"
      cd "'"$PWD"'"
      cmd_uat
    '
    [ "$status" -eq 1 ]
    [[ "$output" == *"README"* ]]
}
