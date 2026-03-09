#!/usr/bin/env bats
# TDD tests for tdd-review SKILL.md completeness
# Covers the missing phase-result.json write instruction (AC-phase-result)
# These tests are in RED state: SKILL.md does not yet contain the required instructions.

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-phase-result-01: SKILL.md must instruct the agent to write phase-result.json
# Without this, the tdd-review phase loops indefinitely (no signal to workflow.sh)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-phase-result-01: SKILL.md contains phase-result.json write instruction" {
    grep -q "phase-result.json" "$BUILDCREW_ROOT/skills/buildcrew-tdd-review/SKILL.md"
}

@test "AC-phase-result-02: SKILL.md instructs writing phase-result with approved verdict" {
    grep -q '"approved"' "$BUILDCREW_ROOT/skills/buildcrew-tdd-review/SKILL.md"
}

@test "AC-phase-result-03: SKILL.md instructs writing phase-result with needs_revision verdict" {
    grep -q '"needs_revision"' "$BUILDCREW_ROOT/skills/buildcrew-tdd-review/SKILL.md"
}

@test "AC-phase-result-04: SKILL.md instructs explicit Write of phase-result.json as final step" {
    # Must instruct agent to write the file, not just mention it
    grep -q 'Write.*phase-result\.json\|phase-result\.json.*Write\|write.*phase-result\.json' \
        "$BUILDCREW_ROOT/skills/buildcrew-tdd-review/SKILL.md"
}
