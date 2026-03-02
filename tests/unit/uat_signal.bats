#!/usr/bin/env bats
# Unit tests for lib/uat_signal.sh — UAT signal file management

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "uat_signal.sh"

    # Override HOME to use test directory for signal paths
    REAL_HOME="$HOME"
    export HOME="$TEST_DIR/fakehome"
    mkdir -p "$HOME"
}

teardown() {
    export HOME="$REAL_HOME"
    teardown_test_dir
    __LOG_FILE=""   # Reset log state between tests
}

# ─────────────────────────────────────────────────────────────────────────────
# Source guard tests
# ─────────────────────────────────────────────────────────────────────────────

@test "uat_signal.sh: source guard prevents double-sourcing" {
    local first_load="$__BUILDCREW_UAT_SIGNAL_LOADED"
    source_lib "uat_signal.sh"
    [ "$__BUILDCREW_UAT_SIGNAL_LOADED" = "$first_load" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# create_signal_dir tests
# ─────────────────────────────────────────────────────────────────────────────

@test "create_signal_dir: creates signal directory for project" {
    run create_signal_dir "my-project"
    [ "$status" -eq 0 ]
    [ -d "$HOME/.buildcrew/uat-signals/my-project" ]
}

@test "create_signal_dir: is idempotent" {
    create_signal_dir "my-project"
    run create_signal_dir "my-project"
    [ "$status" -eq 0 ]
    [ -d "$HOME/.buildcrew/uat-signals/my-project" ]
}

@test "create_signal_dir: returns 1 when project_name is empty" {
    run create_signal_dir ""
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# signal_dir_exists tests
# ─────────────────────────────────────────────────────────────────────────────

@test "signal_dir_exists: returns 0 when directory exists" {
    create_signal_dir "my-project"
    run signal_dir_exists "my-project"
    [ "$status" -eq 0 ]
}

@test "signal_dir_exists: returns 1 when directory does not exist" {
    run signal_dir_exists "nonexistent"
    [ "$status" -eq 1 ]
}

@test "signal_dir_exists: returns 1 when project_name is empty" {
    run signal_dir_exists ""
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# clean_signal_dir tests
# ─────────────────────────────────────────────────────────────────────────────

@test "clean_signal_dir: removes files but preserves verdict.json" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    echo '{"status":"pass"}' > "$signal_dir/verdict.json"
    echo "other data" > "$signal_dir/other-file.txt"
    mkdir -p "$signal_dir/subdir"
    echo "nested" > "$signal_dir/subdir/file.txt"

    run clean_signal_dir "my-project"
    [ "$status" -eq 0 ]
    [ -f "$signal_dir/verdict.json" ]
    [ ! -f "$signal_dir/other-file.txt" ]
    [ ! -d "$signal_dir/subdir" ]
}

@test "clean_signal_dir: handles empty directory gracefully" {
    create_signal_dir "my-project"
    run clean_signal_dir "my-project"
    [ "$status" -eq 0 ]
}

@test "clean_signal_dir: handles nonexistent directory gracefully" {
    run clean_signal_dir "nonexistent"
    [ "$status" -eq 0 ]
}

@test "clean_signal_dir: returns 1 when project_name is empty" {
    run clean_signal_dir ""
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# write_verdict tests
# ─────────────────────────────────────────────────────────────────────────────

@test "write_verdict: writes valid verdict.json for passing scenarios" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    local scenarios='[{"scenario":"test1","status":"pass","summary":"All good","expected":"pass","actual":"pass"}]'

    run write_verdict "$signal_dir" "$scenarios" 1
    [ "$status" -eq 0 ]
    [ -f "$signal_dir/verdict.json" ]

    # Validate JSON structure
    local verdict_status
    verdict_status=$(jq -r '.status' "$signal_dir/verdict.json")
    [ "$verdict_status" = "pass" ]

    local total
    total=$(jq -r '.total' "$signal_dir/verdict.json")
    [ "$total" = "1" ]
}

@test "write_verdict: computes fail status correctly" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    local scenarios='[
        {"scenario":"test1","status":"pass","summary":"ok","expected":"a","actual":"a"},
        {"scenario":"test2","status":"fail","summary":"bad","expected":"b","actual":"c"}
    ]'

    write_verdict "$signal_dir" "$scenarios" 2
    local verdict_status
    verdict_status=$(jq -r '.status' "$signal_dir/verdict.json")
    [ "$verdict_status" = "fail" ]

    local passed failed
    passed=$(jq -r '.passed' "$signal_dir/verdict.json")
    failed=$(jq -r '.failed' "$signal_dir/verdict.json")
    [ "$passed" = "1" ]
    [ "$failed" = "1" ]
}

@test "write_verdict: fail outranks error in status precedence" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    local scenarios='[
        {"scenario":"test1","status":"fail","summary":"bug","expected":"a","actual":"b"},
        {"scenario":"test2","status":"error","summary":"crash","expected":"c","actual":"d"}
    ]'

    write_verdict "$signal_dir" "$scenarios" 1
    local verdict_status
    verdict_status=$(jq -r '.status' "$signal_dir/verdict.json")
    [ "$verdict_status" = "fail" ]
}

@test "write_verdict: error outranks disputed in status precedence" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    local scenarios='[
        {"scenario":"test1","status":"error","summary":"crash","expected":"a","actual":"b"},
        {"scenario":"test2","status":"disputed","summary":"unclear","expected":"c","actual":"d"}
    ]'

    write_verdict "$signal_dir" "$scenarios" 1
    local verdict_status
    verdict_status=$(jq -r '.status' "$signal_dir/verdict.json")
    [ "$verdict_status" = "error" ]
}

@test "write_verdict: disputed outranks pass in status precedence" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    local scenarios='[
        {"scenario":"test1","status":"pass","summary":"ok","expected":"a","actual":"a"},
        {"scenario":"test2","status":"disputed","summary":"unclear","expected":"b","actual":"c"}
    ]'

    write_verdict "$signal_dir" "$scenarios" 1
    local verdict_status
    verdict_status=$(jq -r '.status' "$signal_dir/verdict.json")
    [ "$verdict_status" = "disputed" ]
}

@test "write_verdict: includes build_iteration in output" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    local scenarios='[{"scenario":"test1","status":"pass","summary":"ok","expected":"a","actual":"a"}]'

    write_verdict "$signal_dir" "$scenarios" 42
    local build_iteration
    build_iteration=$(jq -r '.build_iteration' "$signal_dir/verdict.json")
    [ "$build_iteration" = "42" ]
}

@test "write_verdict: includes ISO 8601 UTC timestamp" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    local scenarios='[{"scenario":"test1","status":"pass","summary":"ok","expected":"a","actual":"a"}]'

    write_verdict "$signal_dir" "$scenarios" 1
    local timestamp
    timestamp=$(jq -r '.timestamp' "$signal_dir/verdict.json")
    # Validate ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ
    [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "write_verdict: counts all scenario statuses correctly" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    local scenarios='[
        {"scenario":"t1","status":"pass","summary":"ok","expected":"a","actual":"a"},
        {"scenario":"t2","status":"pass","summary":"ok","expected":"b","actual":"b"},
        {"scenario":"t3","status":"fail","summary":"bad","expected":"c","actual":"d"},
        {"scenario":"t4","status":"error","summary":"crash","expected":"e","actual":"f"},
        {"scenario":"t5","status":"disputed","summary":"unclear","expected":"g","actual":"h"}
    ]'

    write_verdict "$signal_dir" "$scenarios" 1
    local total passed failed errored disputed
    total=$(jq -r '.total' "$signal_dir/verdict.json")
    passed=$(jq -r '.passed' "$signal_dir/verdict.json")
    failed=$(jq -r '.failed' "$signal_dir/verdict.json")
    errored=$(jq -r '.errored' "$signal_dir/verdict.json")
    disputed=$(jq -r '.disputed' "$signal_dir/verdict.json")
    [ "$total" = "5" ]
    [ "$passed" = "2" ]
    [ "$failed" = "1" ]
    [ "$errored" = "1" ]
    [ "$disputed" = "1" ]
}

@test "write_verdict: uses atomic write (no partial verdict.json)" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    local scenarios='[{"scenario":"test1","status":"pass","summary":"ok","expected":"a","actual":"a"}]'

    write_verdict "$signal_dir" "$scenarios" 1
    # After write, no .tmp file should remain
    [ ! -f "$signal_dir/verdict.json.tmp" ]
    [ -f "$signal_dir/verdict.json" ]
}

@test "write_verdict: returns 1 when signal_dir is empty" {
    run write_verdict "" '[]' 1
    [ "$status" -eq 1 ]
}

@test "write_verdict: returns 1 when scenarios_json is empty" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    run write_verdict "$signal_dir" "" 1
    [ "$status" -eq 1 ]
}

@test "write_verdict: returns 1 when scenarios_json is not valid JSON" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    run write_verdict "$signal_dir" "not json" 1
    [ "$status" -eq 1 ]
}

@test "write_verdict: returns 1 when signal directory does not exist" {
    run write_verdict "/nonexistent/path" '[{"scenario":"t1","status":"pass","summary":"ok","expected":"a","actual":"a"}]' 1
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# read_verdict tests
# ─────────────────────────────────────────────────────────────────────────────

@test "read_verdict: reads valid verdict and sets globals" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    local scenarios='[{"scenario":"test1","status":"pass","summary":"ok","expected":"a","actual":"a"}]'

    write_verdict "$signal_dir" "$scenarios" 3

    read_verdict "$signal_dir"
    [ "$__VERDICT_STATUS" = "pass" ]
    [ "$__VERDICT_BUILD_ITERATION" = "3" ]
    [ "$__VERDICT_TOTAL" = "1" ]
    [ "$__VERDICT_PASSED" = "1" ]
    [ "$__VERDICT_FAILED" = "0" ]
    [ "$__VERDICT_ERRORED" = "0" ]
    [ "$__VERDICT_DISPUTED" = "0" ]
    [[ "$__VERDICT_SCENARIOS_JSON" == *"test1"* ]]
}

@test "read_verdict: returns 1 when verdict file is missing" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    local rc=0
    read_verdict "$signal_dir" || rc=$?
    [ "$rc" -eq 1 ]
}

@test "read_verdict: returns 1 for invalid JSON" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    echo "not json" > "$signal_dir/verdict.json"
    local rc=0
    read_verdict "$signal_dir" || rc=$?
    [ "$rc" -eq 1 ]
}

@test "read_verdict: returns 1 when signal_dir is empty" {
    local rc=0
    read_verdict "" || rc=$?
    [ "$rc" -eq 1 ]
}

@test "read_verdict: clears globals on failure" {
    # Set some globals first
    __VERDICT_STATUS="old"
    __VERDICT_BUILD_ITERATION="99"

    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    local rc=0
    read_verdict "$signal_dir" || rc=$?

    [ "$rc" -eq 1 ]
    [ -z "$__VERDICT_STATUS" ]
    [ -z "$__VERDICT_BUILD_ITERATION" ]
}

@test "read_verdict: returns 1 when required fields are missing" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    echo '{"total": 1}' > "$signal_dir/verdict.json"
    local rc=0
    read_verdict "$signal_dir" || rc=$?
    [ "$rc" -eq 1 ]
}

@test "read_verdict: reads fail verdict with mixed scenario statuses" {
    create_signal_dir "my-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/my-project"
    local scenarios='[
        {"scenario":"t1","status":"pass","summary":"ok","expected":"a","actual":"a"},
        {"scenario":"t2","status":"fail","summary":"bad","expected":"b","actual":"c"},
        {"scenario":"t3","status":"error","summary":"crash","expected":"d","actual":"e"}
    ]'

    write_verdict "$signal_dir" "$scenarios" 5
    read_verdict "$signal_dir"

    [ "$__VERDICT_STATUS" = "fail" ]
    [ "$__VERDICT_BUILD_ITERATION" = "5" ]
    [ "$__VERDICT_TOTAL" = "3" ]
    [ "$__VERDICT_PASSED" = "1" ]
    [ "$__VERDICT_FAILED" = "1" ]
    [ "$__VERDICT_ERRORED" = "1" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# read_last_tested_iteration tests
# ─────────────────────────────────────────────────────────────────────────────

@test "read_last_tested_iteration: returns 0 when file is missing" {
    run read_last_tested_iteration "$TEST_DIR/.buildcrew"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "read_last_tested_iteration: returns stored value" {
    mkdir -p "$TEST_DIR/.buildcrew"
    echo "5" > "$TEST_DIR/.buildcrew/last_tested_iteration"
    run read_last_tested_iteration "$TEST_DIR/.buildcrew"
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]
}

@test "read_last_tested_iteration: returns 0 for non-numeric content" {
    mkdir -p "$TEST_DIR/.buildcrew"
    echo "garbage" > "$TEST_DIR/.buildcrew/last_tested_iteration"
    run read_last_tested_iteration "$TEST_DIR/.buildcrew"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# write_last_tested_iteration tests
# ─────────────────────────────────────────────────────────────────────────────

@test "write_last_tested_iteration: writes iteration number" {
    mkdir -p "$TEST_DIR/.buildcrew"
    run write_last_tested_iteration "$TEST_DIR/.buildcrew" 7
    [ "$status" -eq 0 ]

    local val
    val=$(cat "$TEST_DIR/.buildcrew/last_tested_iteration")
    [ "$val" = "7" ]
}

@test "write_last_tested_iteration: uses atomic write" {
    mkdir -p "$TEST_DIR/.buildcrew"
    write_last_tested_iteration "$TEST_DIR/.buildcrew" 3
    [ ! -f "$TEST_DIR/.buildcrew/last_tested_iteration.tmp" ]
    [ -f "$TEST_DIR/.buildcrew/last_tested_iteration" ]
}

@test "write_last_tested_iteration: returns 1 when buildcrew_dir is empty" {
    run write_last_tested_iteration "" 1
    [ "$status" -eq 1 ]
}

@test "write_last_tested_iteration: returns 1 when iteration is empty" {
    run write_last_tested_iteration "$TEST_DIR/.buildcrew" ""
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# read_last_processed_iteration tests
# ─────────────────────────────────────────────────────────────────────────────

@test "read_last_processed_iteration: returns 0 when file is missing" {
    run read_last_processed_iteration "$TEST_DIR/.buildcrew"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "read_last_processed_iteration: returns stored value" {
    mkdir -p "$TEST_DIR/.buildcrew"
    echo "12" > "$TEST_DIR/.buildcrew/last_processed_uat_iteration"
    run read_last_processed_iteration "$TEST_DIR/.buildcrew"
    [ "$status" -eq 0 ]
    [ "$output" = "12" ]
}

@test "read_last_processed_iteration: returns 0 for non-numeric content" {
    mkdir -p "$TEST_DIR/.buildcrew"
    echo "abc" > "$TEST_DIR/.buildcrew/last_processed_uat_iteration"
    run read_last_processed_iteration "$TEST_DIR/.buildcrew"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# write_last_processed_iteration tests
# ─────────────────────────────────────────────────────────────────────────────

@test "write_last_processed_iteration: writes iteration number" {
    mkdir -p "$TEST_DIR/.buildcrew"
    run write_last_processed_iteration "$TEST_DIR/.buildcrew" 9
    [ "$status" -eq 0 ]

    local val
    val=$(cat "$TEST_DIR/.buildcrew/last_processed_uat_iteration")
    [ "$val" = "9" ]
}

@test "write_last_processed_iteration: uses atomic write" {
    mkdir -p "$TEST_DIR/.buildcrew"
    write_last_processed_iteration "$TEST_DIR/.buildcrew" 4
    [ ! -f "$TEST_DIR/.buildcrew/last_processed_uat_iteration.tmp" ]
    [ -f "$TEST_DIR/.buildcrew/last_processed_uat_iteration" ]
}

@test "write_last_processed_iteration: returns 1 when buildcrew_dir is empty" {
    run write_last_processed_iteration "" 1
    [ "$status" -eq 1 ]
}

@test "write_last_processed_iteration: returns 1 when iteration is empty" {
    run write_last_processed_iteration "$TEST_DIR/.buildcrew" ""
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Iteration roundtrip tests
# ─────────────────────────────────────────────────────────────────────────────

@test "iteration roundtrip: write then read last_tested_iteration" {
    mkdir -p "$TEST_DIR/.buildcrew"
    write_last_tested_iteration "$TEST_DIR/.buildcrew" 15
    run read_last_tested_iteration "$TEST_DIR/.buildcrew"
    [ "$output" = "15" ]
}

@test "iteration roundtrip: write then read last_processed_iteration" {
    mkdir -p "$TEST_DIR/.buildcrew"
    write_last_processed_iteration "$TEST_DIR/.buildcrew" 20
    run read_last_processed_iteration "$TEST_DIR/.buildcrew"
    [ "$output" = "20" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# validate_scenario_results tests
# ─────────────────────────────────────────────────────────────────────────────

@test "validate_scenario_results: accepts valid scenario results" {
    local results_file="$TEST_DIR/scenario-results.json"
    cat > "$results_file" << 'EOF'
[
    {"scenario": "User creates project", "status": "pass", "summary": "All good"},
    {"scenario": "User deletes project", "status": "fail", "summary": "Error occurred"}
]
EOF
    run validate_scenario_results "$results_file"
    [ "$status" -eq 0 ]
}

@test "validate_scenario_results: accepts empty array" {
    local results_file="$TEST_DIR/scenario-results.json"
    echo '[]' > "$results_file"
    run validate_scenario_results "$results_file"
    [ "$status" -eq 0 ]
}

@test "validate_scenario_results: accepts all valid status values" {
    local results_file="$TEST_DIR/scenario-results.json"
    cat > "$results_file" << 'EOF'
[
    {"scenario": "a", "status": "pass", "summary": "ok"},
    {"scenario": "b", "status": "fail", "summary": "bad"},
    {"scenario": "c", "status": "error", "summary": "crash"},
    {"scenario": "d", "status": "disputed", "summary": "unclear"}
]
EOF
    run validate_scenario_results "$results_file"
    [ "$status" -eq 0 ]
}

@test "validate_scenario_results: rejects non-array JSON" {
    local results_file="$TEST_DIR/scenario-results.json"
    echo '{"scenario": "test"}' > "$results_file"
    run validate_scenario_results "$results_file"
    [ "$status" -eq 1 ]
}

@test "validate_scenario_results: rejects invalid status value" {
    local results_file="$TEST_DIR/scenario-results.json"
    echo '[{"scenario": "test", "status": "unknown", "summary": "ok"}]' > "$results_file"
    run validate_scenario_results "$results_file"
    [ "$status" -eq 1 ]
}

@test "validate_scenario_results: rejects missing scenario field" {
    local results_file="$TEST_DIR/scenario-results.json"
    echo '[{"status": "pass", "summary": "ok"}]' > "$results_file"
    run validate_scenario_results "$results_file"
    [ "$status" -eq 1 ]
}

@test "validate_scenario_results: rejects missing status field" {
    local results_file="$TEST_DIR/scenario-results.json"
    echo '[{"scenario": "test", "summary": "ok"}]' > "$results_file"
    run validate_scenario_results "$results_file"
    [ "$status" -eq 1 ]
}

@test "validate_scenario_results: rejects missing summary field" {
    local results_file="$TEST_DIR/scenario-results.json"
    echo '[{"scenario": "test", "status": "pass"}]' > "$results_file"
    run validate_scenario_results "$results_file"
    [ "$status" -eq 1 ]
}

@test "validate_scenario_results: rejects non-string scenario field" {
    local results_file="$TEST_DIR/scenario-results.json"
    echo '[{"scenario": 123, "status": "pass", "summary": "ok"}]' > "$results_file"
    run validate_scenario_results "$results_file"
    [ "$status" -eq 1 ]
}

@test "validate_scenario_results: returns 1 for missing file" {
    run validate_scenario_results "/nonexistent/file.json"
    [ "$status" -eq 1 ]
}

@test "validate_scenario_results: returns 1 for invalid JSON" {
    local results_file="$TEST_DIR/scenario-results.json"
    echo "not json" > "$results_file"
    run validate_scenario_results "$results_file"
    [ "$status" -eq 1 ]
}

@test "validate_scenario_results: returns 1 when results_file is empty string" {
    run validate_scenario_results ""
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# log_dispute tests
# ─────────────────────────────────────────────────────────────────────────────

@test "log_dispute: appends dispute in correct format" {
    local disputes_file="$TEST_DIR/disputes.md"
    log_dispute "$disputes_file" \
        "Error message format" \
        "An error message is displayed" \
        "Error was displayed as JSON object" \
        "Does error message require plain text?"

    [ -f "$disputes_file" ]
    run cat "$disputes_file"
    [[ "$output" == *"## Dispute: Error message format"* ]]
    [[ "$output" == *"**Scenario:** Error message format"* ]]
    [[ "$output" == *"**Expected (from README):** An error message is displayed"* ]]
    [[ "$output" == *"**Actual:** Error was displayed as JSON object"* ]]
    [[ "$output" == *"**Question:** Does error message require plain text?"* ]]
}

@test "log_dispute: appends multiple disputes" {
    local disputes_file="$TEST_DIR/disputes.md"
    log_dispute "$disputes_file" "First dispute" "exp1" "act1" "q1"
    log_dispute "$disputes_file" "Second dispute" "exp2" "act2" "q2"

    run cat "$disputes_file"
    [[ "$output" == *"## Dispute: First dispute"* ]]
    [[ "$output" == *"## Dispute: Second dispute"* ]]
}

@test "log_dispute: creates parent directory if needed" {
    local disputes_file="$TEST_DIR/newdir/subdir/disputes.md"
    run log_dispute "$disputes_file" "test" "exp" "act" "question"
    [ "$status" -eq 0 ]
    [ -f "$disputes_file" ]
}

@test "log_dispute: returns 1 when disputes_file is empty" {
    run log_dispute "" "scenario" "expected" "actual" "question"
    [ "$status" -eq 1 ]
}

@test "log_dispute: returns 1 when scenario is empty" {
    run log_dispute "$TEST_DIR/d.md" "" "expected" "actual" "question"
    [ "$status" -eq 1 ]
}

@test "log_dispute: returns 1 when expected is empty" {
    run log_dispute "$TEST_DIR/d.md" "scenario" "" "actual" "question"
    [ "$status" -eq 1 ]
}

@test "log_dispute: returns 1 when actual is empty" {
    run log_dispute "$TEST_DIR/d.md" "scenario" "expected" "" "question"
    [ "$status" -eq 1 ]
}

@test "log_dispute: returns 1 when question is empty" {
    run log_dispute "$TEST_DIR/d.md" "scenario" "expected" "actual" ""
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Integration / roundtrip tests
# ─────────────────────────────────────────────────────────────────────────────

@test "roundtrip: write then read verdict" {
    create_signal_dir "roundtrip-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/roundtrip-project"
    local scenarios='[
        {"scenario":"Login works","status":"pass","summary":"ok","expected":"login succeeds","actual":"login succeeds"},
        {"scenario":"Signup fails gracefully","status":"fail","summary":"crash instead of error msg","expected":"error message","actual":"crash"}
    ]'

    write_verdict "$signal_dir" "$scenarios" 10
    read_verdict "$signal_dir"

    [ "$__VERDICT_STATUS" = "fail" ]
    [ "$__VERDICT_BUILD_ITERATION" = "10" ]
    [ "$__VERDICT_TOTAL" = "2" ]
    [ "$__VERDICT_PASSED" = "1" ]
    [ "$__VERDICT_FAILED" = "1" ]
    [ "$__VERDICT_ERRORED" = "0" ]
    [ "$__VERDICT_DISPUTED" = "0" ]
    [[ "$__VERDICT_SCENARIOS_JSON" == *"Login works"* ]]
    [[ "$__VERDICT_SCENARIOS_JSON" == *"Signup fails gracefully"* ]]
}

@test "roundtrip: validate then write verdict from scenario-results.json" {
    create_signal_dir "validate-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/validate-project"
    local results_file="$TEST_DIR/scenario-results.json"
    cat > "$results_file" << 'EOF'
[
    {"scenario": "User creates project", "status": "pass", "summary": "Project created successfully"},
    {"scenario": "User deletes project", "status": "error", "summary": "Permission denied"}
]
EOF

    # Validate first
    validate_scenario_results "$results_file"

    # Read and use for verdict
    local scenarios_json
    scenarios_json=$(cat "$results_file")
    write_verdict "$signal_dir" "$scenarios_json" 2

    read_verdict "$signal_dir"
    [ "$__VERDICT_STATUS" = "error" ]
    [ "$__VERDICT_TOTAL" = "2" ]
}

@test "clean_signal_dir: preserves verdict.json while cleaning other files" {
    create_signal_dir "clean-test"
    local signal_dir="$HOME/.buildcrew/uat-signals/clean-test"
    local scenarios='[{"scenario":"t1","status":"pass","summary":"ok","expected":"a","actual":"a"}]'

    write_verdict "$signal_dir" "$scenarios" 1
    echo "extra data" > "$signal_dir/extra.txt"

    clean_signal_dir "clean-test"
    [ -f "$signal_dir/verdict.json" ]
    [ ! -f "$signal_dir/extra.txt" ]

    # verdict should still be readable
    read_verdict "$signal_dir"
    [ "$__VERDICT_STATUS" = "pass" ]
}
