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
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run --single
    [ "$status" -eq 0 ]
    # Dry run should NOT mark tasks complete (no side effects)
    grep -q "\[ \] Test task" BACKLOG.md
    [[ "$output" == *"[DRY RUN]"* ]]
}

@test "run: single mode processes only one task" {
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

# ─────────────────────────────────────────────────────────────────────────────
# --teams mode tests
# ─────────────────────────────────────────────────────────────────────────────

@test "run: --teams without env var fails with error" {
    unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 2>/dev/null || true
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --teams --single
    [ "$status" -ne 0 ]
    [[ "$output" == *"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"* ]]
}

@test "run: --teams --dry-run --single succeeds with env var" {
    export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --teams --dry-run --single
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent teams"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# --branch mode tests
# ─────────────────────────────────────────────────────────────────────────────

@test "run: --branch --dry-run with phase-isolation mentions branch name" {
    # Set up phase-isolation structure
    mkdir -p .claude/skills/buildcrew
    echo "phase-isolation enabled" > .claude/skills/buildcrew/SKILL.md
    mkdir -p .claude/skills/buildcrew-research
    mkdir -p .claude/skills/buildcrew-review
    mkdir -p .claude/skills/buildcrew-build
    mkdir -p .claude/skills/buildcrew-test
    mkdir -p .claude/skills/buildcrew-verify

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

@test "run: --branch --dry-run without phase-isolation warns and disables" {
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --branch --dry-run --single
    [ "$status" -eq 0 ]
    [[ "$output" == *"--branch requires phase-isolated mode"* ]]
    [[ "$output" != *"buildcrew/"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Unknown flag test
# ─────────────────────────────────────────────────────────────────────────────

@test "run: unknown flag exits 1" {
    run "$BUILDCREW_HOME/lib/workflow.sh" --invalid
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}
