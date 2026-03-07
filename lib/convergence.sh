# ═══════════════════════════════════════════════════════════════════════════════
# BuildCrew - Plan Review Convergence Loop
# ═══════════════════════════════════════════════════════════════════════════════
#
# Implements the serial convergence loop for the plan review phase.
# Runs up to 3 rounds of sub-agent review with CONVERGED signal detection.
#
# ═══════════════════════════════════════════════════════════════════════════════

# Source guard
[[ -n "${__BUILDCREW_CONVERGENCE_LOADED:-}" ]] && return 0
__BUILDCREW_CONVERGENCE_LOADED=1

# Initialize convergence loop state
convergence_loop_init() {
    mkdir -p .claude
    echo "0" > .claude/.convergence-iteration
}

# Increment iteration counter
convergence_loop_increment() {
    local n
    n=$(cat .claude/.convergence-iteration)
    echo $((n + 1)) > .claude/.convergence-iteration
}

# Check if loop should continue (< 3 iterations); returns 0 to continue, 1 to stop
convergence_loop_should_continue() {
    local n
    n=$(cat .claude/.convergence-iteration)
    [ "$n" -lt 3 ]
}

# Check if response file contains CONVERGED signal (case-sensitive exact match)
convergence_check_response() {
    local response_file="$1"
    grep -q "CONVERGED" "$response_file"
}

# Handle sub-agent failure — log warning with iteration number
convergence_handle_failure() {
    local iteration="$1"
    mkdir -p .claude
    echo "WARNING: Convergence sub-agent failed (iteration $iteration)" >> .claude/.convergence-failure-log
}

# Finalize convergence state for Pass 3
convergence_loop_finalize() {
    mkdir -p .claude
    touch .claude/.convergence-finalized
}

# Check if this is a revision cycle (plan-review-prev.md exists)
convergence_is_revision_cycle() {
    [ -f .claude/plan-review-prev.md ]
}

# Get the prompt for a convergence round (uses revision variant when in revision cycle)
convergence_get_prompt() {
    local iteration="$1"
    if convergence_is_revision_cycle; then
        cat <<'PROMPT'
Read `.claude/plan-review-prev.md` to understand what was previously flagged. Then read `.claude/current-plan.md`.

Your job is NOT to re-review from scratch. Verify that previous findings were addressed and check for regressions. Only flag NEW issues if they are genuinely blocking (security, data loss, core logic error).

Make targeted improvements to `.claude/current-plan.md` if previous issues were NOT addressed.

If previous issues were substantively addressed (even if imperfectly), respond with exactly: CONVERGED

Do not explain what you reviewed. Either improve the file or respond CONVERGED.
PROMPT
    else
        cat <<'PROMPT'
Read `.claude/current-plan.md`. Review it critically as if seeing it for the first time.
Look for gaps, missing details, unclear sections, over-engineering, incorrect assumptions,
missing edge cases, and areas that could be improved.

Make concrete improvements directly to the file. Be specific and substantive.

If the document is solid and no meaningful improvements can be made,
respond with exactly: CONVERGED

Do not explain what you reviewed. Either improve the file or respond CONVERGED.
PROMPT
    fi
}

# Map verdict string to final verdict value (pass-through)
convergence_map_verdict() {
    local verdict="$1"
    echo "$verdict"
}

# Write the combined review output to .claude/plan-review.md
convergence_write_review_output() {
    local verdict="$1"
    local verdict_upper
    verdict_upper=$(echo "$verdict" | tr '[:lower:]' '[:upper:]')

    local lens1_content="" lens2_content="" lens3_content=""
    [ -f .claude/review-lens1.md ] && lens1_content=$(cat .claude/review-lens1.md)
    [ -f .claude/review-lens2.md ] && lens2_content=$(cat .claude/review-lens2.md)
    [ -f .claude/review-lens3.md ] && lens3_content=$(cat .claude/review-lens3.md)

    local approved_line
    if [ "$verdict" = "approved" ]; then
        approved_line="YES"
    else
        approved_line="NO - revise plan first"
    fi

    cat > .claude/plan-review.md <<EOF
## Plan Review (3-Pass)

### Lens 1: Technical Soundness
$lens1_content

### Lens 2: Completeness & Gaps
$lens2_content

### Lens 3: Simplicity & Over-engineering
$lens3_content

### Pass 3: Convergence Synthesis
**Verdict**: $verdict_upper

### Overall Verdict: $verdict_upper

### Approved to Proceed: $approved_line
EOF
}
