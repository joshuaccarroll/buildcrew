#!/usr/bin/env bats
# Unit tests for awaiting_input state emission in workflow.sh review functions

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

@test "update_workflow_state: writes awaiting_input for plan review" {
    run update_workflow_state "review" "awaiting_input"
    [ "$status" -eq 0 ]
    run grep -q "PHASE_STATUS=awaiting_input" .buildcrew/.workflow-state
    [ "$status" -eq 0 ]
}

@test "update_workflow_state: writes awaiting_input for spec review" {
    run update_workflow_state "spec" "awaiting_input"
    [ "$status" -eq 0 ]
    run grep -q "PHASE_STATUS=awaiting_input" .buildcrew/.workflow-state
    [ "$status" -eq 0 ]
}

@test "handle_plan_review: AUTO_MODE skips awaiting_input state write" {
    export AUTO_MODE="true"
    export HUMAN_REVIEW="true"
    run handle_plan_review "test-task" "test description"
    [ "$status" -eq 0 ]
    run grep -q "PHASE_STATUS=awaiting_input" .buildcrew/.workflow-state
    [ "$status" -ne 0 ]
}

@test "handle_spec_review: AUTO_MODE skips awaiting_input state write" {
    export AUTO_MODE="true"
    run handle_spec_review "test-task" "0"
    [ "$status" -eq 0 ]
    run grep -q "PHASE_STATUS=awaiting_input" .buildcrew/.workflow-state
    [ "$status" -ne 0 ]
}
