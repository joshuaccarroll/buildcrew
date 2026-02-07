#!/usr/bin/env bats
# Integration tests for buildcrew status command

load '../setup.bash'

setup() {
    setup_test_dir
    create_mock_claude
    create_mock_jq
    mkdir -p .claude
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# buildcrew status tests
# ─────────────────────────────────────────────────────────────────────────────

@test "status: shows version" {
    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"BuildCrew"* ]]
}

@test "status: shows no backlog message when missing" {
    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"No BACKLOG.md found"* ]]
}

@test "status: shows backlog counts" {
    cat > BACKLOG.md << 'EOF'
- [ ] Pending task 1
- [ ] Pending task 2
- [x] Completed task
- [!] Blocked task (blocked: reason)
EOF
    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pending:   2"* ]]
    [[ "$output" == *"Completed: 1"* ]]
    [[ "$output" == *"Blocked:   1"* ]]
}

@test "status: shows no previous run when no status file" {
    echo "- [ ] Task" > BACKLOG.md
    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"No previous workflow run found"* ]]
}
