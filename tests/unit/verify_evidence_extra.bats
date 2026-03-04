#!/usr/bin/env bats
# Additional adversarial and edge-case tests for: Require Execution Proof in Verify Phase
# These tests complement the TDD scaffold in tests/tdd/verify_evidence.bats.
# They cover edge cases and adversarial scenarios NOT covered by TDD tests.

SKILL_FILE="$BATS_TEST_DIRNAME/../../skills/buildcrew-verify/SKILL.md"

# Helper: extract text between ### Gather Evidence and ### Verify Checklist
gather_evidence_section() {
    local start end
    start=$(grep -n '^### Gather Evidence' "$SKILL_FILE" | head -1 | cut -d: -f1)
    end=$(grep -n '^### Verify Checklist' "$SKILL_FILE" | head -1 | cut -d: -f1)
    sed -n "${start},${end}p" "$SKILL_FILE"
}

# Helper: extract the report template fenced block
report_template_block() {
    local report_start
    report_start=$(grep -n '^### Verify Report' "$SKILL_FILE" | head -1 | cut -d: -f1)
    # Find opening ``` and closing ``` within the report section
    tail -n +"$report_start" "$SKILL_FILE" | sed -n '/^```markdown/,/^```$/p'
}

# ─────────────────────────────────────────────────────────────────────────────
# EDGE CASES
# ─────────────────────────────────────────────────────────────────────────────

@test "EDGE01_cross_reference_consistency" {
    # .claude/verify-evidence.md must appear in all 3 consumer locations:
    # 1. Gather Evidence Step 3 (writing the file)
    # 2. Verify Checklist (referencing the file)
    # 3. Report template Evidence subsection (referencing the file)
    local section
    section=$(gather_evidence_section)
    echo "$section" | grep -q '\.claude/verify-evidence\.md'

    # In the checklist item
    grep -q '\.claude/verify-evidence\.md.*not.*\.claude/test-report\.md' "$SKILL_FILE"

    # In the report template Evidence subsection
    local template
    template=$(report_template_block)
    echo "$template" | grep -q '\.claude/verify-evidence\.md'
}

@test "EDGE02_detection_entries_numbered_1_to_5" {
    local section
    section=$(gather_evidence_section)
    # Must have numbered entries 1. through 5. (not bullets)
    echo "$section" | grep -q '^1\. '
    echo "$section" | grep -q '^2\. '
    echo "$section" | grep -q '^3\. '
    echo "$section" | grep -q '^4\. '
    echo "$section" | grep -q '^5\. '
    # Must not have 6.
    local count
    count=$(echo "$section" | grep -c '^6\. ' || true)
    [ "$count" -eq 0 ]
}

@test "EDGE03_detection_probe_command_pairing" {
    local section
    section=$(gather_evidence_section)
    # Each numbered line must pair its detection condition with the correct run command
    local line1 line2 line3 line4 line5
    line1=$(echo "$section" | grep '^1\. ')
    line2=$(echo "$section" | grep '^2\. ')
    line3=$(echo "$section" | grep '^3\. ')
    line4=$(echo "$section" | grep '^4\. ')
    line5=$(echo "$section" | grep '^5\. ')

    [[ "$line1" == *"test -x test.sh"* ]] && [[ "$line1" == *"./test.sh"* ]]
    [[ "$line2" == *"Makefile"* ]] && [[ "$line2" == *"make test"* ]]
    [[ "$line3" == *"package.json"* ]] && [[ "$line3" == *"npm test"* ]]
    [[ "$line4" == *"pyproject.toml"* ]] && [[ "$line4" == *"pytest"* ]]
    [[ "$line5" == *"Cargo.toml"* ]] && [[ "$line5" == *"cargo test"* ]]
}

@test "EDGE04_evidence_template_exactly_two_h2_sections" {
    local section
    section=$(gather_evidence_section)
    # Extract the markdown fenced block in Step 3
    local template
    template=$(echo "$section" | sed -n '/^```markdown/,/^```$/p')
    [ -n "$template" ]
    # Count H2 headings in the template
    local h2_count
    h2_count=$(echo "$template" | grep -c '^## ' || true)
    [ "$h2_count" -eq 2 ]
    # Verify they are exactly the right two
    echo "$template" | grep -q '^## Test Output'
    echo "$template" | grep -q '^## Changed Files'
}

@test "EDGE05_no_output_fallback_documented_outside_template" {
    local section
    section=$(gather_evidence_section)
    # Remove fenced blocks, check that (no output) appears in prose
    local prose
    prose=$(echo "$section" | sed '/^```/,/^```$/d')
    echo "$prose" | grep -q '(no output)'
    echo "$prose" | grep -iq 'empty'
}

@test "EDGE06_evidence_file_overwrites_not_appends" {
    local section
    section=$(gather_evidence_section)
    echo "$section" | grep -q 'overwriting any previous content'
}

@test "EDGE07_makefile_detection_includes_tab_escape" {
    local section
    section=$(gather_evidence_section)
    # The Makefile detection line must include \t in the bracket expression
    local makefile_line
    makefile_line=$(echo "$section" | grep '^2\. ')
    # Check for [: \t] pattern (with \t escape)
    [[ "$makefile_line" == *'[: \t]'* ]]
}

@test "EDGE08_project_root_instruction_present" {
    local section
    section=$(gather_evidence_section)
    # Must instruct running from project root before any Step entries
    local preamble_end
    preamble_end=$(echo "$section" | grep -n '\*\*Step 1' | head -1 | cut -d: -f1)
    [ -n "$preamble_end" ]
    local preamble
    preamble=$(echo "$section" | head -n "$preamble_end")
    echo "$preamble" | grep -iq 'project root'
}

# ─────────────────────────────────────────────────────────────────────────────
# ADVERSARIAL
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV01_no_duplicate_gather_evidence_sections" {
    local count
    count=$(grep -c '^### Gather Evidence' "$SKILL_FILE")
    [ "$count" -eq 1 ]
}

@test "ADV02_no_jq_dependency" {
    # The spec explicitly excludes jq dependency
    local count
    count=$(grep -c 'jq' "$SKILL_FILE" || true)
    [ "$count" -eq 0 ]
}

@test "ADV03_evidence_subsection_no_test_report_reference" {
    # Extract lines between ### Evidence and ### FINAL VERDICT in the report template
    local template
    template=$(report_template_block)
    local evidence_section
    evidence_section=$(echo "$template" | sed -n '/### Evidence/,/### FINAL VERDICT/p')
    [ -n "$evidence_section" ]
    # Must reference verify-evidence.md
    echo "$evidence_section" | grep -q '\.claude/verify-evidence\.md'
    # Must NOT reference test-report.md
    local bad_ref
    bad_ref=$(echo "$evidence_section" | grep -c 'test-report\.md' || true)
    [ "$bad_ref" -eq 0 ]
}

@test "ADV04_first_match_semantics_documented" {
    local section
    section=$(gather_evidence_section)
    echo "$section" | grep -iq 'first match'
}

@test "ADV05_evidence_report_subsection_exactly_3_bullets" {
    local template
    template=$(report_template_block)
    local evidence_section
    evidence_section=$(echo "$template" | sed -n '/### Evidence/,/### FINAL VERDICT/p' | grep -v '### Evidence' | grep -v '### FINAL VERDICT')
    local bullet_count
    bullet_count=$(echo "$evidence_section" | grep -c '^- \*\*' || true)
    [ "$bullet_count" -eq 3 ]
}

@test "ADV06_step_numbering_contiguous_1_2_3" {
    local section
    section=$(gather_evidence_section)
    # Exactly 3 step headers with em dash (—)
    local step1_count step2_count step3_count
    step1_count=$(echo "$section" | grep -c '\*\*Step 1' || true)
    step2_count=$(echo "$section" | grep -c '\*\*Step 2' || true)
    step3_count=$(echo "$section" | grep -c '\*\*Step 3' || true)
    [ "$step1_count" -eq 1 ]
    [ "$step2_count" -eq 1 ]
    [ "$step3_count" -eq 1 ]
    # No Step 0 or Step 4
    local step0_count step4_count
    step0_count=$(echo "$section" | grep -c '\*\*Step 0' || true)
    step4_count=$(echo "$section" | grep -c '\*\*Step 4' || true)
    [ "$step0_count" -eq 0 ]
    [ "$step4_count" -eq 0 ]
}

@test "ADV07_exit_code_semantics_both_directions" {
    local section
    section=$(gather_evidence_section)
    # Must document both: exit 0 = pass AND non-zero = fail
    echo "$section" | grep -iq 'exit code 0.*pass\|0 means.*pass'
    echo "$section" | grep -iq 'non-zero.*fail\|non.zero.*fail'
}

@test "ADV08_shell_capture_semicolon_not_pipe" {
    local section
    section=$(gather_evidence_section)
    # Extract the sh fenced block
    local sh_block
    sh_block=$(echo "$section" | sed -n '/^```sh/,/^```$/p')
    [ -n "$sh_block" ]
    # Must have semicolon-separated pattern
    echo "$sh_block" | grep -q 'output=\$(.*2>&1); rc=\$?'
    # Must NOT have pipe
    local pipe_count
    pipe_count=$(echo "$sh_block" | grep -c '|' || true)
    [ "$pipe_count" -eq 0 ]
}
