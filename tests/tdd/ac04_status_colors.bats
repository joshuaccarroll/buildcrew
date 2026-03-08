#!/usr/bin/env bats
# TDD tests for AC-04 and AC-05: statusline color-codes new statuses

load '../setup.bash'

setup() {
    setup_test_dir
}

teardown() {
    teardown_test_dir
}

# AC-04: statusline color-codes new statuses:
# awaiting_input → YELLOW (\033[0;33m)
# skipped → RESET (\033[0m)
# max_turns → RED (\033[0;31m)
# permission_denied → RED (\033[0;31m)

# AC-05: statusline exits 0 in all cases

@test "AC-04: statusline shows yellow color for awaiting_input status" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
TASK_NUM=1
TOTAL_TASKS=3
PHASE=spec
PHASE_STATUS=awaiting_input
INVOCATION_COUNT=1
MAX_INVOCATIONS=15
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":30}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033[0;33m'* ]]
}

@test "AC-04: statusline shows red color for max_turns status" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
TASK_NUM=2
TOTAL_TASKS=5
PHASE=build
PHASE_STATUS=max_turns
INVOCATION_COUNT=15
MAX_INVOCATIONS=15
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":50}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033[0;31m'* ]]
}

@test "AC-04: statusline shows red color for permission_denied status" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
TASK_NUM=1
TOTAL_TASKS=3
PHASE=build
PHASE_STATUS=permission_denied
INVOCATION_COUNT=3
MAX_INVOCATIONS=15
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":60}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033[0;31m'* ]]
}

@test "AC-04: statusline uses reset color for skipped status" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
TASK_NUM=1
TOTAL_TASKS=3
PHASE=spec
PHASE_STATUS=skipped
INVOCATION_COUNT=0
MAX_INVOCATIONS=15
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":30}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    # For skipped status with RESET, the phase name should appear without CYAN (running) color
    # We verify this by checking that CYAN is NOT in the output
    ! [[ "$output" == *$'\033[0;36m'* ]]
}

@test "AC-05: statusline exits 0 with awaiting_input status" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
PHASE=spec
PHASE_STATUS=awaiting_input
INVOCATION_COUNT=1
MAX_INVOCATIONS=15
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":20}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
}

@test "AC-05: statusline exits 0 with max_turns status" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
PHASE=build
PHASE_STATUS=max_turns
INVOCATION_COUNT=15
MAX_INVOCATIONS=15
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":80}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
}

@test "AC-05: statusline exits 0 with permission_denied status" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
PHASE=build
PHASE_STATUS=permission_denied
INVOCATION_COUNT=2
MAX_INVOCATIONS=15
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":45}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
}

@test "AC-05: statusline exits 0 with skipped status" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
PHASE=research
PHASE_STATUS=skipped
INVOCATION_COUNT=0
MAX_INVOCATIONS=15
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":25}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
}

@test "AC-05: statusline exits 0 with running status (existing behavior)" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
PHASE=build
PHASE_STATUS=running
INVOCATION_COUNT=3
MAX_INVOCATIONS=15
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":50}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
}

@test "AC-05: statusline exits 0 with complete status (existing behavior)" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
PHASE=build
PHASE_STATUS=complete
INVOCATION_COUNT=2
MAX_INVOCATIONS=15
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":35}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
}

@test "AC-05: statusline exits 0 with failed status (existing behavior)" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
PHASE=build
PHASE_STATUS=failed
INVOCATION_COUNT=5
MAX_INVOCATIONS=15
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":70}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
}

@test "AC-05: statusline exits 0 with malformed state file" {
    mkdir -p .buildcrew
    echo "INVALID_KEY=value" > .buildcrew/.workflow-state
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":40}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
}

@test "AC-05: statusline exits 0 with missing state file" {
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":40}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
}
