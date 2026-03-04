#!/usr/bin/env bats
# TDD tests for: Require Execution Proof in Verify Phase
# Tests verify that buildcrew/skills/buildcrew-verify/SKILL.md contains
# the required Gather Evidence section, updated checklist item, and
# Evidence subsection in the report template.

SKILL_FILE="$BATS_TEST_DIRNAME/../../skills/buildcrew-verify/SKILL.md"

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: Gather Evidence section exists between Discovering What Changed
#         and Verify Checklist
# ─────────────────────────────────────────────────────────────────────────────

@test "AC01_gather_evidence_h3_section_exists" {
    grep -q '^### Gather Evidence' "$SKILL_FILE"
}

@test "AC01_gather_evidence_after_discovering_what_changed" {
    # The line number of "### Gather Evidence" must be greater than
    # the line number of "### Discovering What Changed"
    local discover_line gather_line
    discover_line=$(grep -n '^### Discovering What Changed' "$SKILL_FILE" | head -1 | cut -d: -f1)
    gather_line=$(grep -n '^### Gather Evidence' "$SKILL_FILE" | head -1 | cut -d: -f1)
    [ -n "$discover_line" ]
    [ -n "$gather_line" ]
    [ "$gather_line" -gt "$discover_line" ]
}

@test "AC01_gather_evidence_before_verify_checklist" {
    # The line number of "### Gather Evidence" must be less than
    # the line number of "### Verify Checklist"
    local gather_line checklist_line
    gather_line=$(grep -n '^### Gather Evidence' "$SKILL_FILE" | head -1 | cut -d: -f1)
    checklist_line=$(grep -n '^### Verify Checklist' "$SKILL_FILE" | head -1 | cut -d: -f1)
    [ -n "$gather_line" ]
    [ -n "$checklist_line" ]
    [ "$gather_line" -lt "$checklist_line" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: Test runner detection priority list with 5 entries
# ─────────────────────────────────────────────────────────────────────────────

@test "AC02_detection_entry_1_test_sh" {
    # Detection: test -x test.sh — Run: ./test.sh
    grep -q 'test -x test.sh' "$SKILL_FILE"
    grep -q '\./test\.sh' "$SKILL_FILE"
}

@test "AC02_detection_entry_2_makefile" {
    # Detection includes grep pattern for Makefile test target
    grep -q "grep -q '\\^test\\[:" "$SKILL_FILE"
    grep -q 'make test' "$SKILL_FILE"
}

@test "AC02_detection_entry_3_package_json" {
    # Detection: grep -q '"test"' package.json — Run: npm test
    grep -q 'grep -q.*"test".*package.json' "$SKILL_FILE"
    grep -q 'npm test' "$SKILL_FILE"
}

@test "AC02_detection_entry_4_pyproject" {
    # Detection: test -f pyproject.toml && command -v pytest
    grep -q 'pyproject.toml' "$SKILL_FILE"
    grep -q 'command -v pytest' "$SKILL_FILE"
    grep -q 'pytest' "$SKILL_FILE"
}

@test "AC02_detection_entry_5_cargo" {
    # Detection: test -f Cargo.toml && command -v cargo
    grep -q 'Cargo.toml' "$SKILL_FILE"
    grep -q 'command -v cargo' "$SKILL_FILE"
    grep -q 'cargo test' "$SKILL_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: Execution order — git diff first, then test, then write evidence
# ─────────────────────────────────────────────────────────────────────────────

@test "AC03_git_diff_stat_head_present" {
    grep -q 'git diff --stat HEAD' "$SKILL_FILE"
}

@test "AC03_git_diff_before_test_execution" {
    # git diff --stat HEAD must appear before the test runner detection list
    # within the Gather Evidence section
    local diff_line first_detect_line
    diff_line=$(grep -n 'git diff --stat HEAD' "$SKILL_FILE" | head -1 | cut -d: -f1)
    first_detect_line=$(grep -n 'test -x test.sh' "$SKILL_FILE" | head -1 | cut -d: -f1)
    [ -n "$diff_line" ]
    [ -n "$first_detect_line" ]
    [ "$diff_line" -lt "$first_detect_line" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: Shell capture pattern with 2>&1 and $?
# ─────────────────────────────────────────────────────────────────────────────

@test "AC04_stderr_redirect_pattern" {
    grep -q '2>&1' "$SKILL_FILE"
}

@test "AC04_exit_code_capture" {
    grep -q '\$?' "$SKILL_FILE"
}

@test "AC04_capture_pattern_example" {
    # The shell pattern: output=$(<command> 2>&1); rc=$?
    grep -q 'output=\$(' "$SKILL_FILE"
    grep -q 'rc=\$?' "$SKILL_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: No test runner fallback
# ─────────────────────────────────────────────────────────────────────────────

@test "AC05_no_runner_fallback_text" {
    grep -q 'No test runner detected' "$SKILL_FILE"
}

@test "AC05_no_auto_fail_on_missing_runner" {
    # The section must explicitly state that the Test Suite check is NOT auto-failed
    # when no runner is found. Look for language about NOT failing.
    local gather_start gather_end section
    gather_start=$(grep -n '^### Gather Evidence' "$SKILL_FILE" | head -1 | cut -d: -f1)
    gather_end=$(grep -n '^### Verify Checklist' "$SKILL_FILE" | head -1 | cut -d: -f1)
    [ -n "$gather_start" ]
    [ -n "$gather_end" ]
    section=$(sed -n "${gather_start},${gather_end}p" "$SKILL_FILE")
    echo "$section" | grep -iq 'not.*auto.*fail\|do not.*fail\|NOT.*fail'
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-06: Evidence file format with two H2 sections
# ─────────────────────────────────────────────────────────────────────────────

@test "AC06_evidence_file_path" {
    grep -q '\.claude/verify-evidence\.md' "$SKILL_FILE"
}

@test "AC06_test_output_section" {
    grep -q '## Test Output' "$SKILL_FILE"
}

@test "AC06_changed_files_section" {
    grep -q '## Changed Files' "$SKILL_FILE"
}

@test "AC06_no_changes_detected_fallback" {
    grep -q 'No changes detected' "$SKILL_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-07: Output truncation rule
# ─────────────────────────────────────────────────────────────────────────────

@test "AC07_truncation_threshold_500_lines" {
    grep -q '500 lines' "$SKILL_FILE"
}

@test "AC07_keep_first_50_lines" {
    grep -q 'first 50' "$SKILL_FILE"
}

@test "AC07_keep_last_200_lines" {
    grep -q 'last 200' "$SKILL_FILE"
}

@test "AC07_truncation_marker_format" {
    # The marker format: ... (N lines truncated) ...
    grep -q 'lines truncated' "$SKILL_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-08: Updated Test Suite checklist item
# ─────────────────────────────────────────────────────────────────────────────

@test "AC08_updated_checklist_item_text" {
    grep -q 'All tests pass — use results from Gather Evidence step above' "$SKILL_FILE"
}

@test "AC08_references_verify_evidence_md" {
    # The checklist item must reference .claude/verify-evidence.md
    grep -q '\.claude/verify-evidence\.md.*not.*\.claude/test-report\.md' "$SKILL_FILE"
}

@test "AC08_old_checklist_item_removed" {
    # The old text "All tests pass (zero failures)" should no longer exist
    ! grep -q 'All tests pass (zero failures)' "$SKILL_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-09: Evidence subsection in verify report template
# ─────────────────────────────────────────────────────────────────────────────

@test "AC09_evidence_subsection_in_report" {
    # The fenced code block in the Verify Report section must contain ### Evidence
    local report_start report_end
    report_start=$(grep -n '^### Verify Report' "$SKILL_FILE" | head -1 | cut -d: -f1)
    [ -n "$report_start" ]
    # Find the closing ``` of the fenced block after report_start
    report_end=$(tail -n +"$report_start" "$SKILL_FILE" | grep -n '^```$' | tail -1 | cut -d: -f1)
    [ -n "$report_end" ]
    report_end=$((report_start + report_end - 1))
    section=$(sed -n "${report_start},${report_end}p" "$SKILL_FILE")
    echo "$section" | grep -q '### Evidence'
}

@test "AC09_evidence_source_field" {
    grep -Fq '**Source**: `.claude/verify-evidence.md`' "$SKILL_FILE"
}

@test "AC09_evidence_test_result_field" {
    grep -Fq '**Test Result**: [PASS | FAIL | NO RUNNER]' "$SKILL_FILE"
}

@test "AC09_evidence_changed_files_field" {
    grep -Fq '**Changed Files**' "$SKILL_FILE"
    grep -q 'files changed' "$SKILL_FILE"
}

@test "AC09_evidence_after_architecture_before_verdict" {
    # ### Evidence must appear after ### Architecture and before ### FINAL VERDICT
    # within the fenced code block
    local report_start
    report_start=$(grep -n '^### Verify Report' "$SKILL_FILE" | head -1 | cut -d: -f1)
    [ -n "$report_start" ]
    local arch_line evidence_line verdict_line
    arch_line=$(tail -n +"$report_start" "$SKILL_FILE" | grep -n '### Architecture' | head -1 | cut -d: -f1)
    evidence_line=$(tail -n +"$report_start" "$SKILL_FILE" | grep -n '### Evidence' | head -1 | cut -d: -f1)
    verdict_line=$(tail -n +"$report_start" "$SKILL_FILE" | grep -n '### FINAL VERDICT' | head -1 | cut -d: -f1)
    [ -n "$arch_line" ]
    [ -n "$evidence_line" ]
    [ -n "$verdict_line" ]
    [ "$evidence_line" -gt "$arch_line" ]
    [ "$evidence_line" -lt "$verdict_line" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-10: No unintended changes — existing sections preserved
# ─────────────────────────────────────────────────────────────────────────────

@test "AC10_discovering_what_changed_section_preserved" {
    # Original content preserved AND new section exists (both required)
    grep -q "Run \`git diff --name-only HEAD\` to discover changed files for audit" "$SKILL_FILE"
    grep -q '^### Gather Evidence' "$SKILL_FILE"
}

@test "AC10_verdict_definitions_preserved" {
    # phase-result.json format unchanged AND new section exists
    grep -q '"verdict": "complete"' "$SKILL_FILE"
    grep -q '"verdict": "blocked"' "$SKILL_FILE"
    grep -q '^### Gather Evidence' "$SKILL_FILE"
}

@test "AC10_commit_section_preserved" {
    grep -q '^## COMMIT' "$SKILL_FILE"
    grep -q '^### Gather Evidence' "$SKILL_FILE"
}

@test "AC10_signal_section_preserved" {
    grep -q '^## SIGNAL' "$SKILL_FILE"
    grep -q '^### Gather Evidence' "$SKILL_FILE"
}

@test "AC10_remaining_checklist_items_preserved" {
    grep -q 'Coverage meets project threshold' "$SKILL_FILE"
    grep -q 'No skipped tests without justification' "$SKILL_FILE"
    grep -q '^### Gather Evidence' "$SKILL_FILE"
}
