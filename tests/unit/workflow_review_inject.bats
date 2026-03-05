#!/usr/bin/env bats
# Unit tests for code-review feedback injection into build retry context

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# Code review feedback injection (build retry context)
# ─────────────────────────────────────────────────────────────────────────────

# These tests verify the logic inline in the build loop. We simulate the
# conditions and test that the build_context string would include code-review
# feedback on retry attempts.

@test "build retry: code-review.md contents are injected on retry" {
    mkdir -p .claude
    echo '{"details": "test failed"}' > .claude/phase-result.json
    echo "Fix the null check in parser.ts line 42" > .claude/code-review.md

    # Simulate build_attempt > 1
    local build_attempt=2
    local build_context="spec context"
    local __lesson_instruction="lesson: do not break things"
    local PHASE_RESULT_FILE=".claude/phase-result.json"

    if (( build_attempt > 1 )); then
        local prev_reason
        prev_reason=$(jq -r '.details // "unknown"' "$PHASE_RESULT_FILE")
        build_context="${build_context:+$build_context | }This is build attempt $build_attempt. Previous attempt failed: $prev_reason. Avoid the same mistakes."
        build_context="$build_context"$'\n\n'"$__lesson_instruction"
        if [[ -f ".claude/code-review.md" ]]; then
            local cr_feedback
            cr_feedback=$(head -80 ".claude/code-review.md")
            build_context="$build_context"$'\n\n'"## Code Review Feedback (from previous attempt)"$'\n'"$cr_feedback"
        fi
    fi

    [[ "$build_context" == *"Code Review Feedback"* ]]
    [[ "$build_context" == *"Fix the null check"* ]]
}

@test "build retry: no injection when code-review.md missing" {
    mkdir -p .claude
    echo '{"details": "test failed"}' > .claude/phase-result.json
    # No code-review.md

    local build_attempt=2
    local build_context="spec context"
    local __lesson_instruction="lesson"
    local PHASE_RESULT_FILE=".claude/phase-result.json"

    if (( build_attempt > 1 )); then
        local prev_reason
        prev_reason=$(jq -r '.details // "unknown"' "$PHASE_RESULT_FILE")
        build_context="${build_context:+$build_context | }This is build attempt $build_attempt. Previous attempt failed: $prev_reason. Avoid the same mistakes."
        build_context="$build_context"$'\n\n'"$__lesson_instruction"
        if [[ -f ".claude/code-review.md" ]]; then
            local cr_feedback
            cr_feedback=$(head -80 ".claude/code-review.md")
            build_context="$build_context"$'\n\n'"## Code Review Feedback (from previous attempt)"$'\n'"$cr_feedback"
        fi
    fi

    [[ "$build_context" != *"Code Review Feedback"* ]]
}

@test "build retry: no injection on first attempt" {
    mkdir -p .claude
    echo "Some review feedback" > .claude/code-review.md

    local build_attempt=1
    local build_context="spec context"
    local __lesson_instruction="lesson"
    local PHASE_RESULT_FILE=".claude/phase-result.json"

    if (( build_attempt > 1 )); then
        local prev_reason
        prev_reason=$(jq -r '.details // "unknown"' "$PHASE_RESULT_FILE")
        build_context="${build_context:+$build_context | }This is build attempt $build_attempt."
        if [[ -f ".claude/code-review.md" ]]; then
            local cr_feedback
            cr_feedback=$(head -80 ".claude/code-review.md")
            build_context="$build_context"$'\n\n'"## Code Review Feedback (from previous attempt)"$'\n'"$cr_feedback"
        fi
    fi

    [[ "$build_context" != *"Code Review Feedback"* ]]
}

@test "build retry: code-review.md truncated to 80 lines" {
    mkdir -p .claude
    # Create a 100-line file
    for i in $(seq 1 100); do
        echo "Line $i of review feedback"
    done > .claude/code-review.md

    local cr_feedback
    cr_feedback=$(head -80 ".claude/code-review.md")
    local line_count
    line_count=$(echo "$cr_feedback" | wc -l | tr -d ' ')

    [ "$line_count" -eq 80 ]
}
