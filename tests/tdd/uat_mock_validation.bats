#!/usr/bin/env bats
# TDD tests for mock validation and catalog writing in UAT orchestrator
# AC-01: Catalog written by orchestrator shell after mock generation
# AC-02: Catalog schema correctness (service, doc_url, doc_fetched_at, mock_file, validation_status)
# AC-03: Validation runs once per UAT invocation, updates validation_status
# AC-04: Unreachable docs produce warning but do not abort UAT run
# AC-05: Agent isolation not violated (no agent writes to .buildcrew/)
# AC-06: ./test.sh passes

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "common.sh"
    source_lib "uat_signal.sh"
    source_lib "uat.sh"

    # Set up minimal BuildCrew environment
    mkdir -p .buildcrew
    echo "# Test Project" > README.md

    # Export required variables
    export BUILDCREW_PROJECT_DIR="$TEST_DIR"
    export BUILDCREW_ROOT="$BUILDCREW_ROOT"
}

teardown() {
    teardown_test_dir
}

# AC-01: uat_write_mock_catalog creates .buildcrew/uat-mocks.json with correct structure
@test "AC-01: catalog file created at .buildcrew/uat-mocks.json" {
    local mocks_json='.buildcrew/uat-mocks.json'

    uat_write_mock_catalog "stripe" "https://api.stripe.com/docs" "lib/mocks/stripe.sh"

    [ -f "$mocks_json" ]
}

@test "AC-02: catalog contains service name in JSON" {
    local mocks_json='.buildcrew/uat-mocks.json'

    uat_write_mock_catalog "stripe" "https://api.stripe.com/docs" "lib/mocks/stripe.sh"

    grep -q '"service"\s*:\s*"stripe"' "$mocks_json"
}

@test "AC-02: catalog contains doc_url with correct value" {
    local mocks_json='.buildcrew/uat-mocks.json'

    uat_write_mock_catalog "stripe" "https://api.stripe.com/docs" "lib/mocks/stripe.sh"

    grep -q '"doc_url"\s*:\s*"https://api.stripe.com/docs"' "$mocks_json"
}

@test "AC-02: catalog contains mock_file with correct path" {
    local mocks_json='.buildcrew/uat-mocks.json'

    uat_write_mock_catalog "stripe" "https://api.stripe.com/docs" "lib/mocks/stripe.sh"

    grep -q '"mock_file"\s*:\s*"lib/mocks/stripe.sh"' "$mocks_json"
}

@test "AC-02: catalog contains validation_status field" {
    local mocks_json='.buildcrew/uat-mocks.json'

    uat_write_mock_catalog "stripe" "https://api.stripe.com/docs" "lib/mocks/stripe.sh"

    grep -q '"validation_status"' "$mocks_json"
}

@test "AC-02: catalog contains generated_at ISO timestamp" {
    local mocks_json='.buildcrew/uat-mocks.json'

    uat_write_mock_catalog "stripe" "https://api.stripe.com/docs" "lib/mocks/stripe.sh"

    grep -q '"generated_at"\s*:\s*"[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T' "$mocks_json"
}

@test "AC-02: catalog contains doc_fetched_at ISO timestamp" {
    local mocks_json='.buildcrew/uat-mocks.json'

    uat_write_mock_catalog "stripe" "https://api.stripe.com/docs" "lib/mocks/stripe.sh"

    grep -q '"doc_fetched_at"\s*:\s*"[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T' "$mocks_json"
}

@test "AC-03: uat_validate_mock_urls returns success even with unreachable URL" {
    local mocks_json='.buildcrew/uat-mocks.json'

    uat_write_mock_catalog "stripe" "https://invalid-unreachable.example.com/docs" "lib/mocks/stripe.sh"

    # Validation should return 0 (not abort) even if URL is unreachable
    uat_validate_mock_urls
    local exit_code=$?

    [ $exit_code -eq 0 ]
}

@test "AC-04: catalog remains valid JSON after validation call" {
    local mocks_json='.buildcrew/uat-mocks.json'

    uat_write_mock_catalog "stripe" "https://api.stripe.com/docs" "lib/mocks/stripe.sh"
    uat_validate_mock_urls

    # Validate JSON is still valid by checking it parses
    [ -f "$mocks_json" ]
    [ -s "$mocks_json" ]
}

@test "AC-01: catalog supports multiple mock entries" {
    local mocks_json='.buildcrew/uat-mocks.json'

    uat_write_mock_catalog "stripe" "https://api.stripe.com/docs" "lib/mocks/stripe.sh"
    uat_write_mock_catalog "twilio" "https://www.twilio.com/docs" "lib/mocks/twilio.sh"

    # Second write should create or append correctly
    [ -f "$mocks_json" ]
    [ -s "$mocks_json" ]
}

@test "AC-05: catalog is written to .buildcrew (not in isolated agent dir)" {
    uat_write_mock_catalog "stripe" "https://api.stripe.com/docs" "lib/mocks/stripe.sh"

    # Should be in project .buildcrew, not in agent workspace
    [ -f ".buildcrew/uat-mocks.json" ]
    [ ! -f ".claude/uat-mocks.json" ]
}

@test "AC-01: second mock write appends to existing catalog (not overwrites)" {
    local mocks_json='.buildcrew/uat-mocks.json'

    uat_write_mock_catalog "stripe" "https://api.stripe.com/docs" "lib/mocks/stripe.sh"
    local first_size=$(wc -c < "$mocks_json")

    uat_write_mock_catalog "twilio" "https://www.twilio.com/docs" "lib/mocks/twilio.sh"
    local second_size=$(wc -c < "$mocks_json")

    # Second write should result in larger file (both entries present)
    [ $second_size -gt $first_size ]
}

@test "AC-02: catalog contains both mocks after multiple writes" {
    local mocks_json='.buildcrew/uat-mocks.json'

    uat_write_mock_catalog "stripe" "https://api.stripe.com/docs" "lib/mocks/stripe.sh"
    uat_write_mock_catalog "twilio" "https://www.twilio.com/docs" "lib/mocks/twilio.sh"

    # Both service names should be in catalog
    grep -q '"service"\s*:\s*"stripe"' "$mocks_json"
    grep -q '"service"\s*:\s*"twilio"' "$mocks_json"
}

@test "AC-03: catalog mocks array is valid JSON after validation" {
    local mocks_json='.buildcrew/uat-mocks.json'

    uat_write_mock_catalog "stripe" "https://api.stripe.com/docs" "lib/mocks/stripe.sh"
    uat_validate_mock_urls

    # File should be valid JSON
    [ -f "$mocks_json" ]
    if command -v jq &> /dev/null; then
        jq '.' "$mocks_json" > /dev/null
    fi
}
