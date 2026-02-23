#!/usr/bin/env bats
# Unit tests for lib/statusline.sh

load '../setup.bash'

STATUSLINE="$BUILDCREW_HOME/lib/statusline.sh"

setup() {
    setup_test_dir
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# Basic functionality tests
# ─────────────────────────────────────────────────────────────────────────────

@test "statusline: exits 0 with no stdin and no state file" {
    run bash -c 'echo "" | "$BUILDCREW_HOME/lib/statusline.sh"' </dev/null
    [ "$status" -eq 0 ]
}

@test "statusline: shows BuildCrew prefix when no state file" {
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":42}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"BuildCrew"* ]]
}

@test "statusline: shows context percentage when no state file" {
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":42}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"42% ctx"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# State file tests
# ─────────────────────────────────────────────────────────────────────────────

@test "statusline: shows task progress when state file exists" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
TASK_NUM=3
TOTAL_TASKS=7
TASK_NAME=Build the feature
PHASE=research
PHASE_STATUS=running
INVOCATION_COUNT=4
MAX_INVOCATIONS=15
TIMESTAMP=1700000000
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":42}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Task 3/7"* ]]
    [[ "$output" == *"research"* ]]
    [[ "$output" == *"42% ctx"* ]]
    [[ "$output" == *"inv 4/15"* ]]
}

@test "statusline: handles missing state file gracefully" {
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":55}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"BuildCrew"* ]]
    [[ "$output" == *"55% ctx"* ]]
}

@test "statusline: shows phase name from state file" {
    mkdir -p .buildcrew
    cat > .buildcrew/.workflow-state << 'EOF'
TASK_NUM=1
TOTAL_TASKS=3
PHASE=build
PHASE_STATUS=running
INVOCATION_COUNT=2
MAX_INVOCATIONS=15
EOF
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":30}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"build"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Context percentage handling
# ─────────────────────────────────────────────────────────────────────────────

@test "statusline: handles null context percentage from stdin" {
    run bash -c 'printf '"'"'{"context_window":{}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ctx"* ]]
}

@test "statusline: handles missing context_window field" {
    run bash -c 'printf '"'"'{}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    # Should not crash
}

@test "statusline: handles empty stdin gracefully" {
    run bash -c 'echo "" | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
}

@test "statusline: handles completely empty stdin" {
    run bash -c '"$BUILDCREW_HOME/lib/statusline.sh" < /dev/null'
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Color threshold tests
# ─────────────────────────────────────────────────────────────────────────────

@test "statusline: green color for context below 70 percent" {
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":50}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    # Green ANSI code \033[0;32m
    [[ "$output" == *$'\033[0;32m'* ]]
}

@test "statusline: yellow color for context at 70 percent" {
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":70}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    # Yellow ANSI code \033[0;33m
    [[ "$output" == *$'\033[0;33m'* ]]
}

@test "statusline: red color for context at 90 percent" {
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":90}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    # Red ANSI code \033[0;31m
    [[ "$output" == *$'\033[0;31m'* ]]
}

@test "statusline: red color for context above 90 percent" {
    run bash -c 'printf '"'"'{"context_window":{"used_percentage":95}}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033[0;31m'* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Always exits 0
# ─────────────────────────────────────────────────────────────────────────────

@test "statusline: always exits 0 with malformed JSON" {
    run bash -c 'printf '"'"'not json at all'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
}

@test "statusline: always exits 0 with corrupt state file" {
    mkdir -p .buildcrew
    printf 'CORRUPT DATA\x00\xff' > .buildcrew/.workflow-state
    run bash -c 'printf '"'"'{}'"'"' | "$BUILDCREW_HOME/lib/statusline.sh"'
    [ "$status" -eq 0 ]
}
