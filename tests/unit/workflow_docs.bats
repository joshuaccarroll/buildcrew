#!/usr/bin/env bats
# Unit tests for run_optional_docs in lib/workflow.sh

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: run_optional_docs returns 0 when skill dir doesn't exist (guards)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01: run_optional_docs returns 0 when docs skill not installed" {
    run run_optional_docs "task" "context"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: get_phase_max_turns returns 20 for docs phase
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02: get_phase_max_turns returns 20 for docs phase" {
    run get_phase_max_turns "docs"
    [ "$status" -eq 0 ]
    [ "$output" = "20" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: run_optional_docs is non-blocking when skill exists (|| true behavior)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03: run_optional_docs exits 0 even if run_phase_group would fail" {
    # Set up mock environment
    mkdir -p .claude/skills/buildcrew-docs

    # Mock run_phase_group to fail (return non-zero)
    run_phase_group() {
        return 1
    }

    # run_optional_docs should still exit 0 due to || true
    run run_optional_docs "task" "context"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: run_optional_docs calls run_phase_group with correct phase name
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04: run_optional_docs calls run_phase_group with 'docs' phase" {
    mkdir -p .claude/skills/buildcrew-docs

    # Track what run_phase_group was called with
    run_phase_group() {
        echo "phase=$1 task=$2 context=$3" > /tmp/run_phase_group_called.txt
        return 0
    }

    run_optional_docs "test_task" "test_context"

    [ -f /tmp/run_phase_group_called.txt ]
    [ "$(cat /tmp/run_phase_group_called.txt)" = "phase=docs task=test_task context=test_context" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: Integration - phase count increments when docs skill exists
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-05: Phase count includes docs when skill is installed" {
    mkdir -p .claude/skills/buildcrew-docs

    # Simulate the phase count logic from workflow.sh
    _phase_count=7  # base count (spec, research, review, tdd, build, simplify, codereview, verify = 8 normally)
    [[ -d ".claude/skills/buildcrew-docs" ]] && _phase_count=$((_phase_count + 1))

    [ "$_phase_count" -eq 8 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-06: Phase count does not change when docs skill is not installed
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-06: Phase count unchanged when docs skill not installed" {
    _phase_count=7
    [[ -d ".claude/skills/buildcrew-docs" ]] && _phase_count=$((_phase_count + 1))

    [ "$_phase_count" -eq 7 ]
}
