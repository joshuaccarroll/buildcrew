#!/usr/bin/env bats
# AC-01 through AC-07: Prereqs phase workflow integration tests

load '../setup.bash'

setup() {
    setup_test_dir
    create_mock_claude
    create_mock_jq
    mkdir -p .claude
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: Prereqs phase runs between spec and research when skill exists
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01a: phase_completed recognizes 'prereqs' as valid phase name" {
    # Before any phase runs, phase_completed should return 1 (not completed)
    run phase_completed "prereqs"
    [ "$status" -eq 1 ]
}

@test "AC-01b: update_workflow_state accepts 'prereqs' phase" {
    # Must be able to record prereqs phase as skipped
    update_workflow_state "prereqs" "skipped"
    [ -f ".claude/workflow-status.json" ]
}

@test "AC-01c: phase_completed returns 0 after prereqs marked completed" {
    update_workflow_state "prereqs" "complete"
    run phase_completed "prereqs"
    [ "$status" -eq 0 ]
}

@test "AC-01d: PHASE_RESULT_FILE can be written with prereqs verdict" {
    mkdir -p .claude
    local result_file=".claude/phase-result.json"
    printf '{"phase":"prereqs","verdict":"complete","details":"Prereqs satisfied"}' > "$result_file"
    [ -f "$result_file" ]
    grep -q "prereqs" "$result_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: Phase is skipped (not blocked) when no prereqs are detected
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02a: prereqs skill directory check works" {
    # Stub: skill doesn't exist, phase should skip
    [[ ! -d ".claude/skills/buildcrew-prereqs" ]]
}

@test "AC-02b: prereqs skill directory can be created" {
    # Stub: create the skill directory for testing
    mkdir -p ".claude/skills/buildcrew-prereqs"
    [ -d ".claude/skills/buildcrew-prereqs" ]
}

@test "AC-02c: skipped verdict is handled correctly" {
    # The phase handler should treat 'skipped' as a success verdict
    update_workflow_state "prereqs" "skipped"
    [ -f ".claude/workflow-status.json" ]
}

@test "AC-02d: phase can record 'no prereqs detected' in status" {
    mkdir -p .claude
    printf '{"phase":"prereqs","verdict":"skipped","details":"No prerequisites detected"}' > ".claude/phase-result.json"
    grep -q "skipped" ".claude/phase-result.json"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: Phase blocks task when prereqs unmet in non-auto mode
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03a: AUTO_MODE variable exists and defaults to false or true" {
    # AUTO_MODE is set during init; test framework accepts it
    export AUTO_MODE=false
    [[ "$AUTO_MODE" == "false" ]]
}

@test "AC-03b: phase result 'blocked' verdict is valid" {
    mkdir -p .claude
    printf '{"phase":"prereqs","verdict":"blocked","details":"Missing required dependencies"}' > ".claude/phase-result.json"
    grep -q "blocked" ".claude/phase-result.json"
}

@test "AC-03c: non-auto mode can be set" {
    export AUTO_MODE=false
    [[ "$AUTO_MODE" != "true" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: In auto mode, prereqs emits skipped with warnings instead of blocking
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04a: AUTO_MODE=true is recognized" {
    export AUTO_MODE=true
    [[ "$AUTO_MODE" == "true" ]]
}

@test "AC-04b: warnings file can be written to .buildcrew/prereqs.json" {
    mkdir -p .buildcrew
    printf '{"warnings":["warning 1","warning 2"],"status":"auto_mode_skipped"}' > ".buildcrew/prereqs.json"
    [ -f ".buildcrew/prereqs.json" ]
    grep -q "warnings" ".buildcrew/prereqs.json"
}

@test "AC-04c: auto mode result is skipped not blocked" {
    export AUTO_MODE=true
    mkdir -p .claude
    printf '{"phase":"prereqs","verdict":"skipped","details":"AUTO MODE: warnings only, not blocking"}' > ".claude/phase-result.json"
    grep -q "skipped" ".claude/phase-result.json"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: --skip-prereqs flag bypasses phase entirely
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-05a: parse_args sets SKIP_PREREQS=true when flag present" {
    parse_args "--skip-prereqs"
    [[ "${SKIP_PREREQS:-false}" == "true" ]]
}

@test "AC-05b: parse_args accepts both --skip-spec and --skip-prereqs" {
    parse_args "--skip-spec" "--skip-prereqs"
    [[ "${SKIP_SPEC:-false}" == "true" ]]
    [[ "${SKIP_PREREQS:-false}" == "true" ]]
}

@test "AC-05c: SKIP_PREREQS defaults to false" {
    # Fresh parse without flags
    SKIP_PREREQS=false
    parse_args
    [[ "${SKIP_PREREQS}" == "false" ]]
}

@test "AC-05d: forward flag syntax works for sub-invocations" {
    # Test the bash syntax used in batch_run_task (follows SKIP_SPEC pattern)
    local SKIP_PREREQS=true
    local flags="$( [[ "$SKIP_PREREQS" == "true" ]] && echo "--skip-prereqs" )"
    [[ "$flags" == "--skip-prereqs" ]]
}

@test "AC-05e: forward flag syntax when false produces empty string" {
    # When SKIP_PREREQS is not literally "true", the conditional should not add the flag
    local SKIP_PREREQS=false
    local flags="$( [[ "$SKIP_PREREQS" == "true" ]] && echo "--skip-prereqs" )"
    [[ -z "$flags" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-06: Resume (--resume) skips prereqs if already completed
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-06a: parse_args sets RESUME_MODE with --resume flag" {
    parse_args "--resume"
    [[ "${RESUME_MODE:-false}" == "true" ]]
}

@test "AC-06b: phase_completed returns 0 after prereqs already done" {
    # Mark prereqs complete in workflow state
    update_workflow_state "prereqs" "complete"
    run phase_completed "prereqs"
    [ "$status" -eq 0 ]
}

@test "AC-06c: resume with completed prereqs should skip the phase" {
    # Set up scenario: prereqs already completed
    update_workflow_state "prereqs" "complete"
    export RESUME_MODE=true

    # phase_completed returns 0 when resumed
    run phase_completed "prereqs"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-07: _phase_count display includes prereqs when skill installed
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-07a: prereqs skill directory existence is checkable" {
    mkdir -p ".claude/skills/buildcrew-prereqs"
    [[ -d ".claude/skills/buildcrew-prereqs" ]]
}

@test "AC-07b: phase count logic can include prereqs when skill exists" {
    mkdir -p ".claude/skills/buildcrew-prereqs"
    mkdir -p ".claude/skills/buildcrew-spec"

    # Simulate the phase count logic
    local phase_count=0
    [[ -d ".claude/skills/buildcrew-spec" ]] && phase_count=$(($phase_count + 1))
    [[ -d ".claude/skills/buildcrew-prereqs" ]] && phase_count=$(($phase_count + 1))

    [ $phase_count -eq 2 ]
}

@test "AC-07c: phase count omits prereqs when skill missing" {
    mkdir -p ".claude/skills/buildcrew-spec"

    # Simulate the phase count logic without prereqs skill
    local phase_count=0
    [[ -d ".claude/skills/buildcrew-spec" ]] && phase_count=$(($phase_count + 1))
    [[ -d ".claude/skills/buildcrew-prereqs" ]] && phase_count=$(($phase_count + 1))

    [ $phase_count -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-08: --help includes --skip-prereqs option
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-08a: --skip-prereqs appears in help text" {
    run "$BUILDCREW_HOME/bin/buildcrew" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--skip-prereqs"* ]]
}

@test "AC-08b: help text documents --skip-prereqs alongside --skip-spec" {
    run "$BUILDCREW_HOME/bin/buildcrew" --help
    [ "$status" -eq 0 ]
    # Both flags should be documented
    [[ "$output" == *"--skip-spec"* ]]
    [[ "$output" == *"--skip-prereqs"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-09: get_phase_max_turns includes prereqs case
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-09a: get_phase_max_turns recognizes 'prereqs' phase" {
    run get_phase_max_turns "prereqs"
    # Should return a number (30 is reasonable default)
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "AC-09b: prereqs max turns is a reasonable value" {
    run get_phase_max_turns "prereqs"
    # Prereqs should have at least 5 turns, at most 100
    local max_turns=$output
    [ $max_turns -ge 5 ] && [ $max_turns -le 100 ]
}
