#!/usr/bin/env bats
# TDD tests for AC-02: update_workflow_state model parameter

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# AC-02: update_workflow_state accepts optional model parameter
# When called with 3 arguments (phase, status, model), writes MODEL=$model to state file
# When called with 2 arguments (phase, status), writes MODEL= (empty) to state file
# Does NOT write AUTO_MODE= line

@test "AC-02: update_workflow_state writes MODEL field with provided model value" {
    mkdir -p .buildcrew
    __INVOCATION_COUNT=1
    MAX_INVOCATIONS=15
    __WF_TASK_NUM=1
    __WF_TOTAL_TASKS=1
    __WF_TASK_NAME="test task"
    update_workflow_state "build" "running" "sonnet"
    [ -f ".buildcrew/.workflow-state" ]
    grep -q "^MODEL=sonnet$" .buildcrew/.workflow-state
}

@test "AC-02: update_workflow_state writes empty MODEL when no 3rd argument" {
    mkdir -p .buildcrew
    __INVOCATION_COUNT=1
    MAX_INVOCATIONS=15
    __WF_TASK_NUM=1
    __WF_TOTAL_TASKS=1
    __WF_TASK_NAME="test task"
    update_workflow_state "spec" "running"
    [ -f ".buildcrew/.workflow-state" ]
    grep -q "^MODEL=$" .buildcrew/.workflow-state
}

@test "AC-02: update_workflow_state does NOT write AUTO_MODE= line" {
    mkdir -p .buildcrew
    __INVOCATION_COUNT=1
    MAX_INVOCATIONS=15
    __WF_TASK_NUM=1
    __WF_TOTAL_TASKS=1
    __WF_TASK_NAME="test task"
    AUTO_MODE=true update_workflow_state "build" "running" "haiku"
    [ -f ".buildcrew/.workflow-state" ]
    ! grep -q "^AUTO_MODE=" .buildcrew/.workflow-state
}

@test "AC-06: with CLAUDE_MODEL=auto, update_workflow_state writes resolved model name" {
    mkdir -p .buildcrew
    __INVOCATION_COUNT=1
    MAX_INVOCATIONS=15
    __WF_TASK_NUM=1
    __WF_TOTAL_TASKS=1
    __WF_TASK_NAME="test task"
    CLAUDE_MODEL=auto update_workflow_state "build" "running" "sonnet"
    [ -f ".buildcrew/.workflow-state" ]
    grep -q "^MODEL=sonnet$" .buildcrew/.workflow-state
    ! grep -q "^AUTO_MODE=" .buildcrew/.workflow-state
    ! grep -q "^MODEL=auto$" .buildcrew/.workflow-state
}

@test "AC-02: update_workflow_state preserves other state fields with model parameter" {
    mkdir -p .buildcrew
    __INVOCATION_COUNT=5
    MAX_INVOCATIONS=20
    __WF_TASK_NUM=2
    __WF_TOTAL_TASKS=8
    __WF_TASK_NAME="Complex task name"
    update_workflow_state "research" "complete" "opus"
    [ -f ".buildcrew/.workflow-state" ]
    grep -q "^PHASE=research$" .buildcrew/.workflow-state
    grep -q "^PHASE_STATUS=complete$" .buildcrew/.workflow-state
    grep -q "^MODEL=opus$" .buildcrew/.workflow-state
    grep -q "^INVOCATION_COUNT=5$" .buildcrew/.workflow-state
    grep -q "^MAX_INVOCATIONS=20$" .buildcrew/.workflow-state
}
