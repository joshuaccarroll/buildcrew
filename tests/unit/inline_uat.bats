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
    teardown_test_dir
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
