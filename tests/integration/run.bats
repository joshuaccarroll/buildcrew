#!/usr/bin/env bats
# Integration tests for buildcrew run command

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
# buildcrew run tests
# ─────────────────────────────────────────────────────────────────────────────

@test "run: exits when claude not installed" {
    # Remove mock claude from PATH
    export PATH="${PATH#$TEST_DIR/bin:}"
    # Also ensure no real claude
    if command -v claude &>/dev/null; then
        skip "Real claude is installed, can't test missing claude"
    fi

    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Claude Code CLI not found"* ]]
}

@test "run: dry-run mode marks tasks complete without executing" {
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run --single
    [ "$status" -eq 0 ]
    grep -q "\[x\] Test task" BACKLOG.md
}

@test "run: single mode exits after first task" {
    cat > BACKLOG.md << 'EOF'
- [ ] Task 1
- [ ] Task 2
- [ ] Task 3
EOF
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run --single
    [ "$status" -eq 0 ]
    # Only first task should be completed
    grep -q "\[x\] Task 1" BACKLOG.md
    grep -q "\[ \] Task 2" BACKLOG.md
}

@test "run: shows backlog status" {
    cat > BACKLOG.md << 'EOF'
- [ ] Pending 1
- [ ] Pending 2
- [x] Completed
- [!] Blocked
EOF
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run --single
    [[ "$output" == *"Pending:"* ]]
}

@test "run: displays workflow complete message" {
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run --single
    [[ "$output" == *"Workflow Complete"* ]]
}

@test "run: help flag shows usage" {
    run "$BUILDCREW_HOME/lib/workflow.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "run: exits with 0 when all tasks processed" {
    echo "- [ ] Only task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run
    [ "$status" -eq 0 ]
}
