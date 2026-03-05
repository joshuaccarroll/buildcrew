#!/usr/bin/env bats
# Tests for: Verify Phase SKILL structure after parallel sub-agent rewrite
# Validates that the verify SKILL correctly references evidence files,
# includes test runner detection, and maintains report template structure.

SKILL_FILE="$BATS_TEST_DIRNAME/../../skills/buildcrew-verify/SKILL.md"

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
    # .claude/verify-evidence.md must appear in:
    # 1. Sub-Agent 2 prompt (writing the file)
    # 2. Verify Checklist (referencing the file)
    # 3. Report template Evidence subsection (referencing the file)

    # In the sub-agent prompt
    grep -q '\.claude/verify-evidence\.md' "$SKILL_FILE"

    # In the checklist item
    grep -q '\.claude/verify-evidence\.md' "$SKILL_FILE"

    # In the report template Evidence subsection
    local template
    template=$(report_template_block)
    echo "$template" | grep -q '\.claude/verify-evidence\.md'
}

@test "EDGE02_detection_entries_numbered_1_to_5" {
    # Test runner detection list must have entries 1. through 5.
    grep -q '^1\. ' "$SKILL_FILE"
    grep -q '^2\. ' "$SKILL_FILE"
    grep -q '^3\. ' "$SKILL_FILE"
    grep -q '^4\. ' "$SKILL_FILE"
    grep -q '^5\. ' "$SKILL_FILE"
}

@test "EDGE03_detection_probe_command_pairing" {
    # Test runner detection includes correct detection/command pairs
    grep -q 'test.sh' "$SKILL_FILE"
    grep -q 'Makefile' "$SKILL_FILE"
    grep -q 'package.json' "$SKILL_FILE"
    grep -q 'pyproject.toml' "$SKILL_FILE"
    grep -q 'Cargo.toml' "$SKILL_FILE"
}

@test "EDGE04_evidence_template_has_test_output_and_changed_files" {
    # The sub-agent prompt includes template with Test Output and Changed Files
    grep -q '## Test Output' "$SKILL_FILE"
    grep -q '## Changed Files' "$SKILL_FILE"
}

@test "EDGE05_truncation_documented" {
    # Output truncation rule for >500 lines
    grep -q '500 lines' "$SKILL_FILE"
    grep -q 'truncated' "$SKILL_FILE"
}

@test "EDGE06_evidence_file_overwrites" {
    # The sub-agent writes to verify-evidence.md
    grep -q 'verify-evidence.md' "$SKILL_FILE"
}

@test "EDGE07_makefile_detection" {
    # Makefile detection present
    grep -q 'make test' "$SKILL_FILE"
}

@test "EDGE08_project_root_instruction_present" {
    # Must instruct running from project root
    grep -iq 'project root' "$SKILL_FILE" || grep -iq 'root directory' "$SKILL_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# ADVERSARIAL
# ─────────────────────────────────────────────────────────────────────────────

@test "ADV01_parallel_sub_agents_documented" {
    # The SKILL must describe parallel sub-agents
    grep -q 'Parallel Verification' "$SKILL_FILE"
    grep -q 'Sub-Agent 1' "$SKILL_FILE"
    grep -q 'Sub-Agent 2' "$SKILL_FILE"
    grep -q 'Sub-Agent 3' "$SKILL_FILE"
}

@test "ADV02_no_jq_dependency" {
    # The spec explicitly excludes jq dependency
    local count
    count=$(grep -c 'jq' "$SKILL_FILE" || true)
    [ "$count" -eq 0 ]
}

@test "ADV03_evidence_subsection_references_verify_evidence" {
    local template
    template=$(report_template_block)
    local evidence_section
    evidence_section=$(echo "$template" | sed -n '/### Evidence/,/### FINAL VERDICT/p')
    [ -n "$evidence_section" ]
    echo "$evidence_section" | grep -q '\.claude/verify-evidence\.md'
}

@test "ADV04_first_match_semantics_documented" {
    # The test runner detection should use first-match semantics
    grep -iq 'first match' "$SKILL_FILE"
}

@test "ADV05_evidence_report_subsection_has_bullets" {
    local template
    template=$(report_template_block)
    local evidence_section
    evidence_section=$(echo "$template" | sed -n '/### Evidence/,/### FINAL VERDICT/p' | grep -v '### Evidence' | grep -v '### FINAL VERDICT')
    local bullet_count
    bullet_count=$(echo "$evidence_section" | grep -c '^- \*\*' || true)
    [ "$bullet_count" -ge 2 ]
}

@test "ADV06_three_sub_agents_present" {
    # Verify exactly 3 sub-agent sections
    local count
    count=$(grep -c '#### Sub-Agent' "$SKILL_FILE" || true)
    [ "$count" -eq 3 ]
}

@test "ADV07_exit_code_semantics" {
    # Must document exit code semantics
    grep -iq 'exit code 0\|exit.*code.*0\|rc=\$?' "$SKILL_FILE"
}

@test "ADV08_shell_capture_pattern" {
    # Must have the stderr redirect capture pattern
    grep -q '2>&1' "$SKILL_FILE"
}

@test "ADV09_ac_verification_absorbed" {
    # Verify that acceptance criteria verification is part of verify
    grep -q 'Acceptance Criteria' "$SKILL_FILE"
    grep -q 'outcome-report.md' "$SKILL_FILE"
}

@test "ADV09b_cross_reference_artifacts" {
    # Sub-agent 3 must reference the TDD manifest and ac_coverage for cross-referencing
    grep -q 'tdd-manifest.json' "$SKILL_FILE"
    grep -q 'ac_coverage' "$SKILL_FILE"
    grep -q 'verify-evidence.md' "$SKILL_FILE"
}

@test "ADV10_batch_mode_context" {
    # Verify batch mode context reading is documented
    grep -q 'batch-combined-context.md' "$SKILL_FILE"
}
