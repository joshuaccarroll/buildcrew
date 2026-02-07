#!/usr/bin/env bats
# Contract tests for jq JSON parsing patterns used by the workflow.
# These verify that jq correctly parses the status file formats that
# workflow.sh relies on (valid/invalid JSON, missing fields, etc.),
# NOT the workflow error handling logic itself.

load '../setup.bash'

setup() {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
    setup_test_dir
    source_lib "workflow.sh"
    create_mock_claude
    mkdir -p .claude
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# Status file JSON validation tests
# ─────────────────────────────────────────────────────────────────────────────

@test "status parsing: handles valid complete status" {
    echo '- [ ] Test task' > BACKLOG.md
    echo '{"status": "complete", "summary": "Done"}' > .claude/workflow-status.json

    # Source the workflow functions and run the status check logic
    source_lib "workflow.sh"

    # Verify jq can parse it
    run jq -e . .claude/workflow-status.json
    [ "$status" -eq 0 ]

    local parsed_status
    parsed_status=$(jq -r '.status // ""' .claude/workflow-status.json)
    [ "$parsed_status" = "complete" ]
}

@test "status parsing: handles valid blocked status" {
    echo '{"status": "blocked", "reason": "Tests failed"}' > .claude/workflow-status.json

    run jq -e . .claude/workflow-status.json
    [ "$status" -eq 0 ]

    local parsed_status
    parsed_status=$(jq -r '.status // ""' .claude/workflow-status.json)
    [ "$parsed_status" = "blocked" ]
}

@test "status parsing: detects invalid JSON" {
    echo 'not valid json {{{' > .claude/workflow-status.json

    run jq -e . .claude/workflow-status.json
    [ "$status" -ne 0 ]
}

@test "status parsing: detects truncated JSON" {
    echo '{"status": "comp' > .claude/workflow-status.json

    run jq -e . .claude/workflow-status.json
    [ "$status" -ne 0 ]
}

@test "status parsing: detects empty file" {
    touch .claude/workflow-status.json

    run jq -e . .claude/workflow-status.json
    [ "$status" -ne 0 ]
}

@test "status parsing: handles missing status field" {
    echo '{"summary": "Done but no status"}' > .claude/workflow-status.json

    run jq -e . .claude/workflow-status.json
    [ "$status" -eq 0 ]

    local parsed_status
    parsed_status=$(jq -r '.status // ""' .claude/workflow-status.json)
    [ "$parsed_status" = "" ]
}

@test "status parsing: handles null status field" {
    echo '{"status": null, "summary": "Done"}' > .claude/workflow-status.json

    run jq -e . .claude/workflow-status.json
    [ "$status" -eq 0 ]

    local parsed_status
    parsed_status=$(jq -r '.status // ""' .claude/workflow-status.json)
    [ "$parsed_status" = "" ]
}

@test "status parsing: handles unexpected status value" {
    echo '{"status": "pending", "summary": "Unexpected"}' > .claude/workflow-status.json

    run jq -e . .claude/workflow-status.json
    [ "$status" -eq 0 ]

    local parsed_status
    parsed_status=$(jq -r '.status // ""' .claude/workflow-status.json)
    [ "$parsed_status" = "pending" ]
    # pending is not complete or blocked, so should be treated as unexpected
    [[ "$parsed_status" != "complete" && "$parsed_status" != "blocked" ]]
}

@test "status parsing: handles JSON with extra whitespace" {
    echo '
    {
        "status": "complete",
        "summary": "Done with whitespace"
    }
    ' > .claude/workflow-status.json

    run jq -e . .claude/workflow-status.json
    [ "$status" -eq 0 ]

    local parsed_status
    parsed_status=$(jq -r '.status // ""' .claude/workflow-status.json)
    [ "$parsed_status" = "complete" ]
}

@test "status parsing: handles JSON with unicode" {
    echo '{"status": "complete", "summary": "Done ✓ with emoji"}' > .claude/workflow-status.json

    run jq -e . .claude/workflow-status.json
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Integration-style tests for status file handling
# ─────────────────────────────────────────────────────────────────────────────

@test "workflow: blocks task on invalid JSON status file" {
    echo '- [ ] Test task' > BACKLOG.md
    echo 'invalid json' > .claude/workflow-status.json

    # The workflow should detect this and mark task blocked
    # We test the jq validation that the workflow uses
    if jq -e . .claude/workflow-status.json >/dev/null 2>&1; then
        fail "jq should have failed on invalid JSON"
    fi
}

@test "workflow: extracts summary from valid status" {
    echo '{"status": "complete", "summary": "Built the feature"}' > .claude/workflow-status.json

    local summary
    summary=$(jq -r '.summary // "No summary provided"' .claude/workflow-status.json)
    [ "$summary" = "Built the feature" ]
}

@test "workflow: provides default summary when missing" {
    echo '{"status": "complete"}' > .claude/workflow-status.json

    local summary
    summary=$(jq -r '.summary // "No summary provided"' .claude/workflow-status.json)
    [ "$summary" = "No summary provided" ]
}

@test "workflow: extracts reason from blocked status" {
    echo '{"status": "blocked", "reason": "Tests are failing"}' > .claude/workflow-status.json

    local reason
    reason=$(jq -r '.reason // "Unknown reason"' .claude/workflow-status.json)
    [ "$reason" = "Tests are failing" ]
}

@test "workflow: provides default reason when missing" {
    echo '{"status": "blocked"}' > .claude/workflow-status.json

    local reason
    reason=$(jq -r '.reason // "Unknown reason"' .claude/workflow-status.json)
    [ "$reason" = "Unknown reason" ]
}
