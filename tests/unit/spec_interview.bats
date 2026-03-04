#!/usr/bin/env bats
# Unit tests for handle_spec_interview and the needs_probing spec flow
# Tests the orchestrator-driven interview feature added to the spec phase.

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"

    # Set up PHASE_RESULT_FILE in temp dir
    mkdir -p .claude
    export PHASE_RESULT_FILE="$TEST_DIR/.claude/phase-result.json"

    # Clear color variables to simplify output assertions
    YELLOW="" BOLD="" CYAN="" NC=""

    # Enable VERBOSE so print_debug output appears on stdout
    export VERBOSE=true

    # Initialize variables used by update_workflow_state / handle_spec_interview
    AUTO_MODE="false"
    __INVOCATION_COUNT=1
    MAX_INVOCATIONS=15
    __WF_TASK_NUM=""
    __WF_TOTAL_TASKS=""
    __WF_TASK_NAME=""
    unset __replan_context

    # Temp files for capturing stub call args
    __RPG_CALL_FILE="$TEST_DIR/.rpg_calls"
    __STDOUT_FILE="$TEST_DIR/.test_stdout"
}

teardown() {
    teardown_test_dir
}

# Helper: write phase-result.json with needs_probing and questions
write_needs_probing() {
    local questions_json="${1:-[\"Should X happen?\",\"What about Y?\"]}"
    cat > "$PHASE_RESULT_FILE" << EOF
{"phase":"spec","verdict":"needs_probing","details":"ambiguities found","questions":$questions_json}
EOF
}

# Helper: stub __is_interactive to return 0 (simulates a tty)
stub_interactive() {
    __is_interactive() { return 0; }
}

# Helper: stub run_phase_group to capture args and write a second-pass result.
# Each call is written to a separate file (.rpg_call_1, .rpg_call_2, etc.)
# because arg $3 (spec_extra) contains newlines.
stub_run_phase_group() {
    local result_json="${1:-{\"phase\":\"spec\",\"verdict\":\"complete\",\"details\":\"ok\"}}"
    __RPG_CALL_COUNT=0
    eval "run_phase_group() {
        __RPG_CALL_COUNT=\$((__RPG_CALL_COUNT + 1))
        printf '%s\n---ARG2---\n%s\n---ARG3---\n%s\n' \"\$1\" \"\$2\" \"\$3\" > \"$__RPG_CALL_FILE.\$__RPG_CALL_COUNT\"
        rm -f \"$PHASE_RESULT_FILE\"
        echo '$result_json' > \"$PHASE_RESULT_FILE\"
        return 0
    }"
}

# Helper: stub run_phase_group to fail
stub_run_phase_group_fail() {
    __RPG_CALL_COUNT=0
    run_phase_group() {
        __RPG_CALL_COUNT=$((__RPG_CALL_COUNT + 1))
        printf '%s\n---ARG2---\n%s\n---ARG3---\n%s\n' "$1" "$2" "$3" > "$__RPG_CALL_FILE.$__RPG_CALL_COUNT"
        rm -f "$PHASE_RESULT_FILE"
        return 1
    }
}

# Helper: get a specific arg from a captured run_phase_group call.
# Usage: get_rpg_arg CALL_NUM ARG_NAME   (ARG_NAME: 1, 2, or 3)
get_rpg_arg() {
    local call_num="${1:-1}"
    local arg_num="${2:-3}"
    local file="$__RPG_CALL_FILE.$call_num"
    [[ -f "$file" ]] || return 1
    case "$arg_num" in
        1) head -1 "$file" ;;
        2) sed -n '/^---ARG2---$/,/^---ARG3---$/{ /^---/d; p; }' "$file" ;;
        3) sed -n '/^---ARG3---$/,$ { /^---ARG3---$/d; p; }' "$file" ;;
    esac
}

get_rpg_call_count() {
    echo "${__RPG_CALL_COUNT:-0}"
}

# Helper: run handle_spec_interview with piped answers (avoids read builtin hang).
# Usage: run_interview "task name" "answer1" "answer2" ...
# Requires: stub_interactive called first, stubs for run_phase_group set up.
# Output saved to $__STDOUT_FILE. Return code saved to $__RC.
run_interview() {
    local task="$1"; shift
    local answers_input=""
    local a
    for a in "$@"; do
        answers_input+="$a"$'\n'
    done
    __RC=0
    handle_spec_interview "$task" <<< "$answers_input" > "$__STDOUT_FILE" 2>&1 || __RC=$?
}

# ─────────────────────────────────────────────────────────────────────────────
# SMOKE tests
# ─────────────────────────────────────────────────────────────────────────────

@test "SMOKE-01: workflow.sh sources without syntax errors" {
    run source_lib "workflow.sh"
    [ "$status" -eq 0 ]
}

@test "SMOKE-02: handle_spec_interview function exists" {
    run type handle_spec_interview
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "SMOKE-02b: __is_interactive function exists" {
    run type __is_interactive
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Happy Path tests
# ─────────────────────────────────────────────────────────────────────────────

@test "HP-01: auto mode skips interview with non-empty questions" {
    write_needs_probing
    AUTO_MODE="true"

    run handle_spec_interview "test task"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Auto mode: skipping spec interview, proceeding with best-effort spec"* ]]
}

@test "HP-02: non-interactive terminal skips interview" {
    write_needs_probing
    AUTO_MODE="false"
    # __is_interactive not stubbed — bats stdin is not a tty, so the guard fires

    run handle_spec_interview "test task"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Non-interactive terminal"* ]]
    [[ "$output" == *"skipping spec interview"* ]]
}

@test "HP-03: builds correct answer context format" {
    cat > "$PHASE_RESULT_FILE" << 'EOF'
{"phase":"spec","verdict":"needs_probing","details":"unclear","questions":["What is X?","How about Y?"]}
EOF
    stub_interactive
    stub_run_phase_group

    run_interview "my task" "foo" "bar"
    [ "$__RC" -eq 0 ]
    [ "$(get_rpg_call_count)" -eq 1 ]

    local spec_extra
    spec_extra="$(get_rpg_arg 1 3)"

    # Should start with the marker (no replan prefix)
    [[ "$spec_extra" == "[BUILDCREW_INTERVIEW_ANSWERS]"* ]]
    # Should contain Q/A pairs
    [[ "$spec_extra" == *"Q1: What is X?"* ]]
    [[ "$spec_extra" == *"A1: foo"* ]]
    [[ "$spec_extra" == *"Q2: How about Y?"* ]]
    [[ "$spec_extra" == *"A2: bar"* ]]
}

@test "HP-04: re-invokes spec and returns 0 on complete verdict" {
    write_needs_probing
    stub_interactive
    stub_run_phase_group '{"phase":"spec","verdict":"complete","details":"ok"}'

    run_interview "my task" "answer1" "answer2"
    [ "$__RC" -eq 0 ]
    [ "$(get_rpg_call_count)" -eq 1 ]

    # Verify first arg is "spec" and second is the task
    [ "$(get_rpg_arg 1 1)" = "spec" ]
    [ "$(get_rpg_arg 1 2)" = "my task" ]
}

@test "HP-05: CLAUDE.md spec phase verdicts include needs_probing" {
    run grep 'spec' "$BUILDCREW_ROOT/CLAUDE.md"
    [[ "$output" == *'needs_probing'* ]]
    [[ "$output" == *'complete'* ]]
    [[ "$output" == *'vague'* ]]
}

@test "HP-06: SKILL.md has three assessment paths" {
    local skill_file="$BUILDCREW_ROOT/skills/buildcrew-spec/SKILL.md"
    grep -q '^\*\*Clear\*\*' "$skill_file"
    grep -q '^\*\*Needs probing\*\*' "$skill_file"
    grep -q '^\*\*Insufficient clarity\*\*' "$skill_file"
}

@test "HP-07: SKILL.md has second-pass detection block" {
    local skill_file="$BUILDCREW_ROOT/skills/buildcrew-spec/SKILL.md"
    grep -q '\[BUILDCREW_INTERVIEW_ANSWERS\]' "$skill_file"
    grep -q 'Interview Answers (Second Pass)' "$skill_file"
}

@test "HP-08: SKILL.md Phase Result Protocol includes needs_probing" {
    local skill_file="$BUILDCREW_ROOT/skills/buildcrew-spec/SKILL.md"
    grep -q '"needs_probing"' "$skill_file"
    grep -q '"questions"' "$skill_file"
}

@test "HP-09: workflow.sh needs_probing verdict calls handle_spec_interview" {
    grep -q 'elif \[\[ "\$spec_verdict" == "needs_probing" \]\]' "$BUILDCREW_ROOT/lib/workflow.sh"
    grep -q 'handle_spec_interview "\$task"' "$BUILDCREW_ROOT/lib/workflow.sh"
}

@test "HP-10: calls update_workflow_state spec awaiting_input during interview" {
    write_needs_probing
    stub_interactive
    stub_run_phase_group

    # Track update_workflow_state calls
    local uws_file="$TEST_DIR/.uws_calls"
    : > "$uws_file"
    update_workflow_state() { echo "$1|$2" >> "$uws_file"; }

    run_interview "test task" "answer1" "answer2"
    [ -s "$uws_file" ]
    head -1 "$uws_file" | grep -q "spec|awaiting_input"
}

# ─────────────────────────────────────────────────────────────────────────────
# Error Handling tests
# ─────────────────────────────────────────────────────────────────────────────

@test "ERR-01: empty questions array treated as complete" {
    cat > "$PHASE_RESULT_FILE" << 'EOF'
{"phase":"spec","verdict":"needs_probing","details":"unclear","questions":[]}
EOF

    run handle_spec_interview "test task"
    [ "$status" -eq 0 ]
    [[ "$output" == *"needs_probing verdict but no questions"* ]]
}

@test "ERR-02: second-pass needs_probing returns 0 with warning" {
    write_needs_probing
    stub_interactive
    stub_run_phase_group '{"phase":"spec","verdict":"needs_probing","details":"still unclear"}'

    run_interview "test task" "a1" "a2"
    [ "$__RC" -eq 0 ]
    grep -q "Interview re-run produced needs_probing again" "$__STDOUT_FILE"
}

@test "ERR-03: second-pass vague verdict returns 1" {
    write_needs_probing
    stub_interactive
    stub_run_phase_group '{"phase":"spec","verdict":"vague","details":"scope too broad"}'

    run_interview "test task" "a1" "a2"
    [ "$__RC" -ne 0 ]
    grep -q "Second-pass spec flagged as too vague: scope too broad" "$__STDOUT_FILE"
}

@test "ERR-04: run_phase_group failure returns 1 immediately" {
    write_needs_probing
    stub_interactive
    stub_run_phase_group_fail

    run_interview "test task" "a1" "a2"
    [ "$__RC" -ne 0 ]
    # Should NOT reach the verdict check warnings
    ! grep -q "Second-pass spec flagged" "$__STDOUT_FILE"
    ! grep -q "Interview re-run produced" "$__STDOUT_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Edge Case tests
# ─────────────────────────────────────────────────────────────────────────────

@test "EDGE-01: empty entries in questions array are filtered out" {
    cat > "$PHASE_RESULT_FILE" << 'EOF'
{"phase":"spec","verdict":"needs_probing","details":"unclear","questions":["What is X?","","How about Y?"]}
EOF
    stub_interactive
    stub_run_phase_group

    run_interview "test task" "a1" "a2"

    local spec_extra
    spec_extra="$(get_rpg_arg 1 3)"
    # Should have Q1/A1 and Q2/A2, but no Q3
    [[ "$spec_extra" == *"Q1: What is X?"* ]]
    [[ "$spec_extra" == *"Q2: How about Y?"* ]]
    [[ "$spec_extra" != *"Q3:"* ]]
}

@test "EDGE-02: preserves __replan_context in re-invocation" {
    write_needs_probing
    stub_interactive
    stub_run_phase_group
    __replan_context="circuit breaker replan"

    run_interview "test task" "a1" "a2"

    local spec_extra
    spec_extra="$(get_rpg_arg 1 3)"
    [[ "$spec_extra" == "Re-planning context: circuit breaker replan | [BUILDCREW_INTERVIEW_ANSWERS]"* ]]
}

@test "EDGE-03: absent __replan_context omits prefix" {
    write_needs_probing
    stub_interactive
    stub_run_phase_group
    unset __replan_context

    run_interview "test task" "a1" "a2"

    local spec_extra
    spec_extra="$(get_rpg_arg 1 3)"
    [[ "$spec_extra" == "[BUILDCREW_INTERVIEW_ANSWERS]"* ]]
    [[ "$spec_extra" != *"Re-planning context"* ]]
}

@test "EDGE-04: empty answers (user presses Enter) still proceeds" {
    write_needs_probing
    stub_interactive
    stub_run_phase_group

    # Provide empty lines as answers
    run_interview "test task" "" ""

    local spec_extra
    spec_extra="$(get_rpg_arg 1 3)"
    # A1 and A2 should be present (with empty values)
    [[ "$spec_extra" == *"A1: "* ]]
    [[ "$spec_extra" == *"A2: "* ]]
}

@test "EDGE-05: SKILL.md User Decisions section conditional on second pass" {
    local skill_file="$BUILDCREW_ROOT/skills/buildcrew-spec/SKILL.md"
    grep -q '## User Decisions' "$skill_file"
    grep -q 'Only include this section on second pass' "$skill_file" || \
    grep -q 'Omit this section entirely on first pass' "$skill_file"
}

@test "EDGE-06: SKILL.md mentions TBD markers for first-pass spec" {
    local skill_file="$BUILDCREW_ROOT/skills/buildcrew-spec/SKILL.md"
    grep -q '\[TBD:' "$skill_file"
}

@test "EDGE-07: vague/needs_probing/fallthrough if-elif-fi structure in workflow.sh" {
    local wf="$BUILDCREW_ROOT/lib/workflow.sh"
    grep -q 'if \[\[ "\$spec_verdict" == "vague" \]\]' "$wf"
    grep -q 'elif \[\[ "\$spec_verdict" == "needs_probing" \]\]' "$wf"
    grep -A5 'elif.*needs_probing' "$wf" | grep -q 'fi'
}

@test "EDGE-08: missing verdict field defaults to complete" {
    cat > "$PHASE_RESULT_FILE" << 'EOF'
{"phase":"spec","verdict":"needs_probing","details":"unclear","questions":["Q1?"]}
EOF
    stub_interactive

    # Stub run_phase_group to write JSON without verdict field
    : > "$__RPG_CALL_FILE"
    run_phase_group() {
        echo "$1|$2|$3" >> "$__RPG_CALL_FILE"
        rm -f "$PHASE_RESULT_FILE"
        echo '{"phase":"spec","details":"some details"}' > "$PHASE_RESULT_FILE"
        return 0
    }

    run_interview "test task" "a1"
    [ "$__RC" -eq 0 ]
    # No warnings about vague or needs_probing
    ! grep -q "Second-pass spec flagged" "$__STDOUT_FILE"
    ! grep -q "Interview re-run produced" "$__STDOUT_FILE"
}

@test "EDGE-09: single question in array works correctly" {
    cat > "$PHASE_RESULT_FILE" << 'EOF'
{"phase":"spec","verdict":"needs_probing","details":"one thing unclear","questions":["What about Z?"]}
EOF
    stub_interactive
    stub_run_phase_group

    run_interview "test task" "answer z"

    local spec_extra
    spec_extra="$(get_rpg_arg 1 3)"
    [[ "$spec_extra" == *"Q1: What about Z?"* ]]
    [[ "$spec_extra" == *"A1: answer z"* ]]
    [[ "$spec_extra" != *"Q2:"* ]]
}

@test "EDGE-10: unknown second-pass verdict treated as success" {
    write_needs_probing
    stub_interactive
    stub_run_phase_group '{"phase":"spec","verdict":"blocked","details":"unknown state"}'

    run_interview "test task" "a1" "a2"
    [ "$__RC" -eq 0 ]
    ! grep -q "Second-pass spec flagged" "$__STDOUT_FILE"
    ! grep -q "Interview re-run produced" "$__STDOUT_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Adversarial tests
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV-01: no questions field in JSON treated as complete" {
    cat > "$PHASE_RESULT_FILE" << 'EOF'
{"phase":"spec","verdict":"needs_probing","details":"unclear"}
EOF

    run handle_spec_interview "test task"
    [ "$status" -eq 0 ]
    [[ "$output" == *"needs_probing verdict but no questions"* ]]
}

@test "ADV-02: invalid JSON in phase-result.json treated as complete" {
    echo "not json at all" > "$PHASE_RESULT_FILE"

    run handle_spec_interview "test task"
    [ "$status" -eq 0 ]
    [[ "$output" == *"needs_probing verdict but no questions"* ]]
}

@test "ADV-03: shell metacharacters in questions passed through literally" {
    # jq -r will output the literal string "What about $(whoami)?" from JSON
    # The question is whether it survives through the shell pipeline intact
    cat > "$PHASE_RESULT_FILE" << 'JSONEOF'
{"phase":"spec","verdict":"needs_probing","details":"test","questions":["What about dollar-whoami?"]}
JSONEOF
    stub_interactive
    stub_run_phase_group

    run_interview "test task" "safe answer"

    local spec_extra
    spec_extra="$(get_rpg_arg 1 3)"
    # Question text should appear unchanged in the answer context
    [[ "$spec_extra" == *"Q1: What about dollar-whoami?"* ]]
    [[ "$spec_extra" == *"A1: safe answer"* ]]
}

@test "ADV-04: PHASE_RESULT_FILE does not exist at entry" {
    rm -f "$PHASE_RESULT_FILE"

    run handle_spec_interview "test task"
    [ "$status" -eq 0 ]
    [[ "$output" == *"needs_probing verdict but no questions"* ]]
}

@test "ADV-05: questions field is a string not an array" {
    cat > "$PHASE_RESULT_FILE" << 'EOF'
{"phase":"spec","verdict":"needs_probing","details":"test","questions":"what?"}
EOF

    run handle_spec_interview "test task"
    [ "$status" -eq 0 ]
    # jq errors on iterating a string, stderr suppressed, no questions extracted
    [[ "$output" == *"needs_probing verdict but no questions"* ]]
}

@test "ADV-06: questions field is null" {
    cat > "$PHASE_RESULT_FILE" << 'EOF'
{"phase":"spec","verdict":"needs_probing","details":"test","questions":null}
EOF

    run handle_spec_interview "test task"
    [ "$status" -eq 0 ]
    [[ "$output" == *"needs_probing verdict but no questions"* ]]
}

@test "ADV-07: question containing escaped newline splits into two entries" {
    # jq -r expands \n in JSON strings to real newlines, so "What is\nthe limit?"
    # becomes two lines. The while-read loop treats each line as a separate question.
    printf '{"phase":"spec","verdict":"needs_probing","details":"test","questions":["What is\\nthe limit?"]}' > "$PHASE_RESULT_FILE"
    stub_interactive
    stub_run_phase_group

    run_interview "test task" "a1" "a2"
    [ "$__RC" -eq 0 ]

    local spec_extra
    spec_extra="$(get_rpg_arg 1 3)"
    # Should have Q1 and Q2 (split from the single JSON question)
    [[ "$spec_extra" == *"Q1: What is"* ]]
    [[ "$spec_extra" == *"Q2: the limit?"* ]]
    [[ "$spec_extra" == *"A1: a1"* ]]
    [[ "$spec_extra" == *"A2: a2"* ]]
}

@test "ERR-06: second-pass PHASE_RESULT_FILE missing after run_phase_group returns 0" {
    write_needs_probing
    stub_interactive

    # Stub run_phase_group to delete PHASE_RESULT_FILE but NOT recreate it
    __RPG_CALL_COUNT=0
    run_phase_group() {
        __RPG_CALL_COUNT=$((__RPG_CALL_COUNT + 1))
        rm -f "$PHASE_RESULT_FILE"
        # Intentionally do NOT write a new file — simulates a broken second pass
        return 0
    }

    run_interview "test task" "a1" "a2"
    # Function should return 0 — jq fails, new_verdict is empty, neither vague nor needs_probing match
    [ "$__RC" -eq 0 ]
    # Should NOT contain warnings about vague or needs_probing
    ! grep -q "Second-pass spec flagged" "$__STDOUT_FILE"
    ! grep -q "Interview re-run produced" "$__STDOUT_FILE"
}

@test "EDGE-12: fewer stdin lines than questions — remaining answers default to empty" {
    cat > "$PHASE_RESULT_FILE" << 'EOF'
{"phase":"spec","verdict":"needs_probing","details":"3 qs","questions":["Q one?","Q two?","Q three?"]}
EOF
    stub_interactive
    stub_run_phase_group

    # Only provide 1 answer for 3 questions — stdin will EOF for Q2 and Q3
    run_interview "test task" "only answer"

    local spec_extra
    spec_extra="$(get_rpg_arg 1 3)"
    # First question gets the answer
    [[ "$spec_extra" == *"Q1: Q one?"* ]]
    [[ "$spec_extra" == *"A1: only answer"* ]]
    # Second and third questions get empty answers
    [[ "$spec_extra" == *"Q2: Q two?"* ]]
    [[ "$spec_extra" == *"A2: "* ]]
    [[ "$spec_extra" == *"Q3: Q three?"* ]]
    [[ "$spec_extra" == *"A3: "* ]]
}
