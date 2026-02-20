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

@test "run: dry-run mode does not mutate backlog" {
    setup_phase_isolation
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run --single
    [ "$status" -eq 0 ]
    # Dry run should NOT mark tasks complete (no side effects)
    grep -q "\[ \] Test task" BACKLOG.md
    [[ "$output" == *"[DRY RUN]"* ]]
}

@test "run: single mode processes only one task" {
    setup_phase_isolation
    cat > BACKLOG.md << 'EOF'
- [ ] Task 1
- [ ] Task 2
- [ ] Task 3
EOF
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run --single
    [ "$status" -eq 0 ]
    # Dry run should only mention the first task
    [[ "$output" == *"Task 1"* ]]
    # Should exit after single task mode message
    [[ "$output" == *"Single task mode"* ]]
}

@test "run: shows backlog status" {
    setup_phase_isolation
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
    setup_phase_isolation
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
    setup_phase_isolation
    echo "- [ ] Only task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# --branch mode tests
# ─────────────────────────────────────────────────────────────────────────────

@test "run: --branch --dry-run with phase-isolation mentions branch name" {
    setup_phase_isolation
    echo "- [ ] Test task" > BACKLOG.md

    # Initialize git repo (required for --branch)
    git init
    git config user.email "test@buildcrew.test"
    git config user.name "Test"
    # Commit everything so worktree is clean
    git add -A
    git commit -m "init"

    run "$BUILDCREW_HOME/lib/workflow.sh" --branch --dry-run --single
    [ "$status" -eq 0 ]
    [[ "$output" == *"buildcrew/"* ]]
}

@test "run: exits with error when phase-isolation is not installed" {
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run --single
    [ "$status" -ne 0 ]
    [[ "$output" == *"buildcrew init"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Unknown flag test
# ─────────────────────────────────────────────────────────────────────────────

@test "run: unknown flag exits 1" {
    run "$BUILDCREW_HOME/lib/workflow.sh" --invalid
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "run: --max-invocations flag is accepted" {
    setup_phase_isolation
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --max-invocations 25 --dry-run --single
    [ "$status" -eq 0 ]
}

@test "run: .buildcrew/config MAX_INVOCATIONS is loaded" {
    setup_phase_isolation
    echo "- [ ] Test task" > BACKLOG.md
    mkdir -p .buildcrew
    echo "MAX_INVOCATIONS=25" > .buildcrew/config
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run --single
    [ "$status" -eq 0 ]
}
