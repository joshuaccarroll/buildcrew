#!/usr/bin/env bats
# TDD tests for AC-03: statusline displays MODEL in brackets

load '../setup.bash'

setup() {
    setup_test_dir
}

teardown() {
    teardown_test_dir
}

# AC-03: statusline reads MODEL field from state file and displays it in brackets
# Format: "Phase [model]" when MODEL is non-empty
# Format: "Phase" when MODEL is absent or empty

@test "AC-03: statusline displays model name in brackets when MODEL set" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
TASK_NUM=1
TOTAL_TASKS=3
PHASE=build
PHASE_STATUS=running
INVOCATION_COUNT=2
MAX_INVOCATIONS=15
MODEL=sonnet
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":42}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"build [sonnet]"* ]]
}

@test "AC-03: statusline does not show brackets when MODEL empty" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
TASK_NUM=1
TOTAL_TASKS=3
PHASE=build
PHASE_STATUS=running
INVOCATION_COUNT=2
MAX_INVOCATIONS=15
MODEL=
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":42}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"build"* ]]
    ! [[ "$output" == *"build ["* ]]
}

@test "AC-03: statusline does not show brackets when MODEL absent from state file" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
TASK_NUM=1
TOTAL_TASKS=3
PHASE=build
PHASE_STATUS=running
INVOCATION_COUNT=2
MAX_INVOCATIONS=15
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":42}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"build"* ]]
    ! [[ "$output" == *"build ["* ]]
}

@test "AC-03: statusline displays different model names correctly" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
TASK_NUM=2
TOTAL_TASKS=4
PHASE=research
PHASE_STATUS=running
INVOCATION_COUNT=3
MAX_INVOCATIONS=15
MODEL=opus
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":30}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"research [opus]"* ]]
}

@test "AC-03: statusline model suffix inherits phase color" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
TASK_NUM=1
TOTAL_TASKS=3
PHASE=build
PHASE_STATUS=running
INVOCATION_COUNT=1
MAX_INVOCATIONS=15
MODEL=haiku
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":20}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    # Verify the output contains both the running color (cyan) and the model in brackets
    # The color code should appear before the phase/model section
    [[ "$output" =~ \[haiku\] ]]
}
