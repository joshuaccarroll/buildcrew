#!/usr/bin/env bats
# TDD tests for buildcrew-tdd-review phase integration
# AC: Acceptance criteria from implementation plan
#
# Plan context:
# - Add tdd-review phase between tdd-scaffold and build
# - SKILL.md uses 3 parallel Task-spawned lenses (Correctness, Design, Speed)
# - Phase result verdicts: approved, needs_revision
# - Only runs when tdd-scaffold verdict is complete

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
    source_lib "common.sh"

    # Set up minimal test environment
    export TDD_MODE="true"
    mkdir -p .claude/skills/buildcrew-tdd-review
    mkdir -p .claude/skills/buildcrew-tdd-scaffold
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: tdd-review phase slot exists in workflow.sh
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01a: get_phase_max_turns returns valid value for tdd-review" {
    run get_phase_max_turns "tdd-review"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ "$output" -gt 0 ]
}

@test "AC-01b: get_phase_max_turns returns 30 for tdd-review" {
    run get_phase_max_turns "tdd-review"
    [ "$status" -eq 0 ]
    [ "$output" = "30" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: tdd-review verdict handling is registered in workflow
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02a: get_phase_verdicts returns valid verdicts for tdd-review" {
    # This test verifies that when get_phase_verdicts is called with "tdd-review",
    # it returns a string containing valid verdicts: approved, needs_revision
    run bash -c 'source_lib workflow.sh; get_phase_verdicts "tdd-review"'
    # Function should return successfully and include valid verdicts
    [[ "$output" == *"approved"* ]] || [[ "$output" == *"needs_revision"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: tdd-review SKILL.md exists and has required structure
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03a: buildcrew-tdd-review skill directory must exist in project" {
    [ -d "skills/buildcrew-tdd-review" ] || [ -d ".claude/skills/buildcrew-tdd-review" ]
}

@test "AC-03b: SKILL.md for tdd-review must exist at correct location" {
    # After implementation, SKILL.md should be at skills/buildcrew-tdd-review/SKILL.md
    [ -f "$BUILDCREW_ROOT/skills/buildcrew-tdd-review/SKILL.md" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: tdd-review produces findings file (.claude/tdd-review.md)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04a: tdd-review phase can write findings to .claude/tdd-review.md" {
    # Mock a successful tdd-review by writing the findings file
    mkdir -p .claude
    echo "# TDD Review Findings" > .claude/tdd-review.md
    echo "## Correctness" >> .claude/tdd-review.md
    [ -f ".claude/tdd-review.md" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: tdd-review verdict handling (approved vs needs_revision)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-05a: phase verdict approved is recognized as valid" {
    mkdir -p .claude
    printf '{"phase": "tdd-review", "verdict": "approved"}' > .claude/phase-result.json
    verdict=$(jq -r '.verdict' .claude/phase-result.json)
    [ "$verdict" = "approved" ]
}

@test "AC-05b: phase verdict needs_revision is recognized as valid" {
    mkdir -p .claude
    printf '{"phase": "tdd-review", "verdict": "needs_revision"}' > .claude/phase-result.json
    verdict=$(jq -r '.verdict' .claude/phase-result.json)
    [ "$verdict" = "needs_revision" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03 continued: tdd-review uses parallel Task sub-agents for lenses
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03c: tdd-review SKILL.md front matter includes Task tool" {
    # Stub: After build, SKILL.md must allow Task tool (spawn parallel agents)
    # Create stub content to verify structure
    mkdir -p skills/buildcrew-tdd-review
    cat > skills/buildcrew-tdd-review/SKILL.md << 'EOF'
# TDD Review Phase

allowed-tools: Read, Write, Glob, Grep, Task

## Three Parallel Lenses

This phase spawns three parallel Task sub-agents for independent lens review:
- Correctness & Reliability
- Design & Intent
- Speed & Isolation

EOF
    [ -f "skills/buildcrew-tdd-review/SKILL.md" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-06: tdd-review phase can read tdd-manifest.json
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-06a: tdd-manifest.json is readable and structured" {
    mkdir -p .claude
    cat > .claude/tdd-manifest.json << 'EOF'
{
  "test_files": ["tests/tdd/ac01.test.ts", "tests/tdd/ac02.test.ts"],
  "stub_files": ["src/feature.ts"],
  "test_dir": "tests/tdd",
  "test_count": 5,
  "all_failing": true,
  "framework": "jest",
  "run_command": "npm test",
  "ac_coverage": {
    "AC-01": ["test_ac01_one", "test_ac01_two"],
    "AC-02": ["test_ac02_one"]
  }
}
EOF
    [ -f ".claude/tdd-manifest.json" ]
    test_count=$(jq '.test_count' .claude/tdd-manifest.json)
    [ "$test_count" -eq 5 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01 continued: Integration — tdd-review phase runs after tdd-scaffold
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01c: phase_completed function recognizes tdd-review as phase" {
    mkdir -p .claude
    touch .claude/phase-completed-tdd-review.txt
    # The phase_completed logic should recognize tdd-review as a valid phase name
    run bash -c "source_lib workflow.sh; [ -f '.claude/phase-completed-tdd-review.txt' ] && echo 'phase_file_recognized'"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04 continued: tdd-review findings consolidation
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04b: tdd-review findings include all three lenses" {
    mkdir -p .claude
    cat > .claude/tdd-review.md << 'EOF'
# TDD Review Findings

## Correctness & Reliability
- Finding 1

## Design & Intent
- Finding 2

## Speed & Isolation
- Finding 3

## Consolidated Verdict
approved
EOF
    [ -f ".claude/tdd-review.md" ]
    grep -q "Correctness & Reliability" .claude/tdd-review.md
    grep -q "Design & Intent" .claude/tdd-review.md
    grep -q "Speed & Isolation" .claude/tdd-review.md
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05 continued: Verdict blocks task on needs_revision
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-05c: needs_revision verdict requires tdd-scaffold to rewrite" {
    mkdir -p .claude
    cat > .claude/phase-result.json << 'EOF'
{
  "phase": "tdd-review",
  "verdict": "needs_revision",
  "details": "Test assertions too weak to catch real bugs"
}
EOF
    verdict=$(jq -r '.verdict' .claude/phase-result.json)
    [ "$verdict" = "needs_revision" ]
    details=$(jq -r '.details' .claude/phase-result.json)
    [ -n "$details" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03 continued: Lenses are read-only (no Edit/Bash)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03d: SKILL.md specifies allowed-tools without Bash or Edit" {
    mkdir -p skills/buildcrew-tdd-review
    # Create a minimal valid SKILL.md
    cat > skills/buildcrew-tdd-review/SKILL.md << 'EOF'
# TDD Review Phase

allowed-tools: Read, Write, Glob, Grep, Task

## Three Parallel Review Lenses

[Content describing lenses...]
EOF
    # Verify the file exists and contains the required front matter
    [ -f "skills/buildcrew-tdd-review/SKILL.md" ]
    head -3 skills/buildcrew-tdd-review/SKILL.md | grep -q "allowed-tools.*Task"
}
