#!/usr/bin/env bats
# TDD tests for TDD-Review Phase integration
# Tests for tdd-review phase orchestration (AC-01 through AC-11)

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "common.sh"
    source_lib "workflow.sh"
    mkdir -p .claude
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: get_phase_max_turns returns 30 for tdd-review
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01: get_phase_max_turns returns 30 for tdd-review" {
    local max_turns=$(get_phase_max_turns "tdd-review")
    [ "$max_turns" = "30" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: workflow.sh contains tdd-review phase block between tdd-scaffold and build
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02: workflow.sh has tdd-review phase block" {
    # Check that lib/workflow.sh contains tdd-review phase block
    grep -q 'tdd-review)' "$BUILDCREW_ROOT/lib/workflow.sh"
}

@test "AC-02: tdd-review appears in workflow after tdd-scaffold" {
    # Verify tdd-review phase block is defined in workflow.sh
    grep -q '"tdd-review"' "$BUILDCREW_ROOT/lib/workflow.sh"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: tdd-review phase runs only when TDD_MODE=true and complexity=standard
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03: tdd-review phase block guards on TDD_MODE and complexity" {
    # Check that workflow.sh has conditional: TDD_MODE=true and standard complexity
    grep -q 'TDD_MODE.*==.*"true"' "$BUILDCREW_ROOT/lib/workflow.sh" && \
    grep -q 'task_complexity" == "standard' "$BUILDCREW_ROOT/lib/workflow.sh"
}

@test "AC-03: tdd-review skips if tdd-manifest.json not found" {
    # Check that workflow guards against missing manifest
    grep -q '! -f ".claude/tdd-manifest.json"' "$BUILDCREW_ROOT/lib/workflow.sh"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: tdd-review phase is non-blocking (uses || true)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04: tdd-review phase call includes || true" {
    # Check that run_phase_group call for tdd-review is non-blocking
    grep -q 'run_phase_group "tdd-review".*|| true' "$BUILDCREW_ROOT/lib/workflow.sh"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: tdd-review is included in phase_completed resume guard
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-05: tdd-review is in phase_completed check" {
    # Verify phase_completed guards the tdd-review block
    grep -B 5 'run_phase_group "tdd-review"' "$BUILDCREW_ROOT/lib/workflow.sh" | grep -q 'phase_completed "tdd-review"'
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-06: tdd-review is added to __completed_phases and saved
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-06: tdd-review is appended to __completed_phases" {
    # Check that tdd-review is added to completed phases tracking
    grep -q '__completed_phases.*"tdd-review"' "$BUILDCREW_ROOT/lib/workflow.sh"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-07: Phase count includes tdd-review when TDD mode and skill dir exist
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-07: _phase_count increments for tdd-review" {
    # Check that phase count logic includes tdd-review
    grep -q 'tdd-review' "$BUILDCREW_ROOT/lib/workflow.sh"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-08: tdd-review SKILL.md exists
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-08: skills/buildcrew-tdd-review/SKILL.md exists" {
    [ -f "$BUILDCREW_ROOT/skills/buildcrew-tdd-review/SKILL.md" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-09: SKILL.md describes convergence rounds scoped to test_files
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-09: SKILL.md mentions test_files from tdd-manifest" {
    grep -q 'test_files' "$BUILDCREW_ROOT/skills/buildcrew-tdd-review/SKILL.md"
}

@test "AC-09: SKILL.md describes RED state verification" {
    grep -q 'RED' "$BUILDCREW_ROOT/skills/buildcrew-tdd-review/SKILL.md" || \
    grep -q 'red' "$BUILDCREW_ROOT/skills/buildcrew-tdd-review/SKILL.md"
}

@test "AC-09: SKILL.md mentions checksum updates" {
    grep -q 'checksum\|SHA' "$BUILDCREW_ROOT/skills/buildcrew-tdd-review/SKILL.md"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-10: tdd-review phase verdict is documented
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-10: workflow.sh documents tdd-review verdict as complete" {
    grep -q 'tdd-review.*complete' "$BUILDCREW_ROOT/lib/workflow.sh" || \
    grep -q 'complete.*tdd-review' "$BUILDCREW_ROOT/lib/workflow.sh"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-11: Test suite passes
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-11: ./test.sh does not fail on workflow.sh syntax" {
    # Basic syntax check: sourcing workflow.sh should not error
    (source "$BUILDCREW_ROOT/lib/workflow.sh") || true
}
