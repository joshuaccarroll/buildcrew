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
    # Should show dry-run output (not process Task 2 or 3)
    [[ "$output" == *"[DRY RUN]"* ]]
    [[ "$output" != *"Task 2"* ]]
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

@test "run: dry-run single mode shows task info and exits cleanly" {
    setup_phase_isolation
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run --single
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN]"* ]]
    [[ "$output" == *"Test task"* ]]
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

# ─────────────────────────────────────────────────────────────────────────────
# batch/sequential mode tests (batch is now the default)
# ─────────────────────────────────────────────────────────────────────────────

@test "run: default mode (no flags) enters batch path with --dry-run" {
    cat > BACKLOG.md << 'EOF'
- [ ] Task one
- [ ] Task two
- [ ] Task three
EOF
    git init && git config user.email "t@t.t" && git config user.name "T"
    git add . && git commit -m "init" --no-verify
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"3 tasks"* ]]
    [[ "$output" == *"parallel"* ]]
    [[ "$output" == *"Task one"* ]]
    [[ "$output" == *"Task two"* ]]
    [[ "$output" == *"Task three"* ]]
}

@test "run: --task forces sequential path" {
    setup_phase_isolation
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --task "Test task" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test task"* ]]
    [[ "$output" == *"[DRY RUN]"* ]]
}

@test "run: --resume exits with error when no manifest and no progress file" {
    echo "- [ ] Test task" > BACKLOG.md
    git init && git config user.email "t@t.t" && git config user.name "T"
    git add . && git commit -m "init" --no-verify
    run "$BUILDCREW_HOME/lib/workflow.sh" --resume
    [ "$status" -ne 0 ]
    [[ "$output" == *"No resumable run"* ]]
}

@test "run: empty backlog triggers discovery mode (not error)" {
    echo "# No tasks" > BACKLOG.md
    git init && git config user.email "t@t.t" && git config user.name "T"
    git add . && git commit -m "init" --no-verify
    run "$BUILDCREW_HOME/lib/workflow.sh"
    # Discovery mode runs claude which is mocked — check it doesn't error with "No pending tasks"
    [[ "$output" != *"No pending tasks"* ]]
    [[ "$output" == *"discovery"* ]] || [[ "$output" == *"backlog"* ]] || [[ "$output" == *"Empty backlog"* ]]
}

@test "run: all tasks complete triggers discovery mode (not error)" {
    echo "- [x] Done task" > BACKLOG.md
    git init && git config user.email "t@t.t" && git config user.name "T"
    git add . && git commit -m "init" --no-verify
    run "$BUILDCREW_HOME/lib/workflow.sh"
    [[ "$output" != *"No pending tasks"* ]]
}

@test "run: outside git repo without target dirs falls back to single task foreground" {
    echo "- [ ] Test task" > BACKLOG.md
    # TEST_DIR is not a git repo (setup_test_dir uses mktemp, no git init)
    run "$BUILDCREW_HOME/lib/workflow.sh"
    [[ "$output" == *"Running single task in foreground"* ]] || [[ "$output" == *"Non-git directory"* ]]
}

@test "run: outside git repo with [dir:...] prefix shows non-git info" {
    echo "- [ ] [dir:nonexistent] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh"
    [[ "$output" == *"Non-git parent directory"* ]]
}

@test "run: --dry-run (default batch) shows task list and count" {
    cat > BACKLOG.md << 'EOF'
- [ ] Task one
- [ ] Task two
- [ ] Task three
EOF
    git init && git config user.email "t@t.t" && git config user.name "T"
    git add . && git commit -m "init" --no-verify
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"3 tasks"* ]]
    [[ "$output" == *"Task one"* ]]
    [[ "$output" == *"Task two"* ]]
    [[ "$output" == *"Task three"* ]]
}

@test "run: --plan --dry-run exits 0 with message" {
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --plan --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN]"* ]]
    [[ "$output" == *"discovery mode"* ]]
}

@test "run: --review forces sequential (no batch path)" {
    setup_phase_isolation
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --review --dry-run --single
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN]"* ]]
}

@test "run: --batch prints deprecation warning" {
    echo "- [ ] Test task" > BACKLOG.md
    git init && git config user.email "t@t.t" && git config user.name "T"
    git add . && git commit -m "init" --no-verify
    run "$BUILDCREW_HOME/lib/workflow.sh" --batch --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"deprecated"* ]]
}

@test "run: --sequential --dry-run prints deprecation warning and shows dry-run output" {
    setup_phase_isolation
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --sequential --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"deprecated"* ]]
    [[ "$output" == *"[DRY RUN]"* ]]
}

@test "run: --batch --single --dry-run takes sequential path with deprecation warning" {
    setup_phase_isolation
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --batch --single --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"deprecated"* ]]
    [[ "$output" == *"[DRY RUN]"* ]]
}
