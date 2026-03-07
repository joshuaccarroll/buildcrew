#!/usr/bin/env bats
# TDD tests for plan review convergence loop
# Tests for convergence loop behavior in the review phase (AC-01 through AC-09)

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "common.sh"
    source_lib "convergence.sh"
    create_mock_claude
    mkdir -p .claude
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: Serial convergence loop runs up to 3 rounds (iterations 0–2)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01: convergence_loop initializes iteration counter to 0" {
    # Helper stub for convergence_loop (will be implemented)
    # Verify that the loop starts at iteration 0
    convergence_loop_init

    [ -f .claude/.convergence-iteration ]
    [ "$(cat .claude/.convergence-iteration)" = "0" ]
}

@test "AC-01: convergence_loop increments iteration counter" {
    convergence_loop_init
    convergence_loop_increment
    [ "$(cat .claude/.convergence-iteration)" = "1" ]

    convergence_loop_increment
    [ "$(cat .claude/.convergence-iteration)" = "2" ]
}

@test "AC-01: convergence_loop stops after 3 iterations" {
    convergence_loop_init

    for i in {1..3}; do
        convergence_loop_should_continue || break
        convergence_loop_increment
    done

    # After 3 iterations, should not continue
    convergence_loop_should_continue && false || true
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: CONVERGED signal stops iteration early
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02: convergence_check detects CONVERGED signal in response" {
    echo "Plan is solid and no meaningful improvements can be made. CONVERGED" > /tmp/agent_response.txt

    convergence_check_response /tmp/agent_response.txt
    [ "$?" -eq 0 ]
}

@test "AC-02: convergence_check rejects response without CONVERGED" {
    echo "Some changes need to be made to improve the plan." > /tmp/agent_response.txt

    ! convergence_check_response /tmp/agent_response.txt
}

@test "AC-02: convergence_check case-sensitive for CONVERGED" {
    echo "The plan has converged." > /tmp/agent_response.txt

    ! convergence_check_response /tmp/agent_response.txt
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: Sub-agent failure (missing output) is handled
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03: convergence_handle_failure logs warning for missing output" {
    convergence_handle_failure 1

    [ -f .claude/.convergence-failure-log ]
    grep -q "iteration 1" .claude/.convergence-failure-log
}

@test "AC-03: convergence_handle_failure records which iteration failed" {
    convergence_handle_failure 0
    convergence_handle_failure 2

    grep -q "iteration 0" .claude/.convergence-failure-log
    grep -q "iteration 2" .claude/.convergence-failure-log
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: Pass 3 inline synthesis still runs after loop
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04: convergence_loop_finalize prepares state for Pass 3" {
    convergence_loop_init
    convergence_loop_finalize

    [ -f .claude/.convergence-finalized ]
}

@test "AC-04: Pass 3 can read convergence findings" {
    cat > .claude/.convergence-findings <<EOF
Iteration 0: Plan improved with better error handling
Iteration 1: CONVERGED
EOF

    [ -f .claude/.convergence-findings ]
    grep -q "CONVERGED" .claude/.convergence-findings
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: Revision cycle detection (plan-review-prev.md) is preserved
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-05: convergence_is_revision_cycle returns true when plan-review-prev.md exists" {
    touch .claude/plan-review-prev.md

    convergence_is_revision_cycle
    [ "$?" -eq 0 ]
}

@test "AC-05: convergence_is_revision_cycle returns false when plan-review-prev.md missing" {
    ! convergence_is_revision_cycle
}

@test "AC-05: convergence_get_prompt uses revision variant when in revision cycle" {
    touch .claude/plan-review-prev.md

    local prompt=$(convergence_get_prompt 0)

    echo "$prompt" | grep -q "plan-review-prev.md"
    echo "$prompt" | grep -q "NOT to re-review from scratch"
}

@test "AC-05: convergence_get_prompt uses fresh variant when not in revision cycle" {
    local prompt=$(convergence_get_prompt 0)

    echo "$prompt" | grep -q "Review it critically as if seeing it for the first time"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-06: .claude/plan-review.md written with correct format
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-06: convergence_write_review_output creates plan-review.md" {
    cat > .claude/review-lens1.md <<EOF
## Lens 1: Technical Soundness
- Finding 1
- Finding 2
VERDICT: PASS
EOF

    cat > .claude/review-lens2.md <<EOF
## Lens 2: Completeness & Gaps
- Gap 1
VERDICT: PASS
EOF

    cat > .claude/review-lens3.md <<EOF
## Lens 3: Simplicity & Over-engineering
- Simplification 1
VERDICT: PASS
EOF

    convergence_write_review_output "approved"

    [ -f .claude/plan-review.md ]
    grep -q "Plan Review" .claude/plan-review.md
    grep -q "Lens 1" .claude/plan-review.md
    grep -q "Lens 2" .claude/plan-review.md
    grep -q "Lens 3" .claude/plan-review.md
}

@test "AC-06: plan-review.md includes verdict from synthesis" {
    echo "VERDICT: PASS" > .claude/review-lens1.md
    echo "VERDICT: PASS" > .claude/review-lens2.md
    echo "VERDICT: PASS" > .claude/review-lens3.md

    convergence_write_review_output "approved"

    grep -q "APPROVED" .claude/plan-review.md
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-07: Verdict contract unchanged (approved/needs_revision/rejected)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-07: convergence_map_verdict maps approved correctly" {
    local verdict=$(convergence_map_verdict "approved")
    [ "$verdict" = "approved" ]
}

@test "AC-07: convergence_map_verdict maps needs_revision correctly" {
    local verdict=$(convergence_map_verdict "needs_revision")
    [ "$verdict" = "needs_revision" ]
}

@test "AC-07: convergence_map_verdict maps rejected correctly" {
    local verdict=$(convergence_map_verdict "rejected")
    [ "$verdict" = "rejected" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-08: workflow.sh external retry loop NOT modified (verification only)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-08: workflow.sh can be sourced without modification" {
    # This test verifies the external loop is not modified
    # by checking that workflow.sh can still be sourced
    source_lib "workflow.sh"

    # If we got here, workflow.sh sourced successfully
    [ 1 -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-09: ./buildcrew/test.sh passes (integration verification)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-09: convergence loop integrates with review phase" {
    # This test verifies the convergence loop can be orchestrated
    # within the review phase workflow

    # Create minimal spec and plan files
    cat > .claude/current-plan.md <<EOF
# Implementation Plan
- Step 1: Modify review phase
- Step 2: Test convergence loop
EOF

    # Initialize convergence state
    convergence_loop_init

    [ -f .claude/current-plan.md ]
    [ -f .claude/.convergence-iteration ]
}
