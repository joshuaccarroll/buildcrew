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

# ─────────────────────────────────────────────────────────────────────────────
# --batch flag tests
# ─────────────────────────────────────────────────────────────────────────────

@test "run: --batch --single exits with error" {
    echo "- [ ] Test task" > BACKLOG.md
    git init && git config user.email "t@t.t" && git config user.name "T"
    run "$BUILDCREW_HOME/lib/workflow.sh" --batch --single
    [ "$status" -ne 0 ]
    [[ "$output" == *"--batch cannot be combined with --single"* ]]
}

@test "run: --batch --task exits with error" {
    echo "- [ ] Test task" > BACKLOG.md
    git init && git config user.email "t@t.t" && git config user.name "T"
    run "$BUILDCREW_HOME/lib/workflow.sh" --batch --task "some task"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--batch cannot be combined"* ]]
}

@test "run: --batch --resume exits with error when no manifest" {
    echo "- [ ] Test task" > BACKLOG.md
    git init && git config user.email "t@t.t" && git config user.name "T"
    git add . && git commit -m "init" --no-verify
    run "$BUILDCREW_HOME/lib/workflow.sh" --batch --resume
    [ "$status" -ne 0 ]
    [[ "$output" == *"No resumable batch"* ]]
}

@test "run: --batch with empty backlog exits with error" {
    echo "# No tasks" > BACKLOG.md
    git init && git config user.email "t@t.t" && git config user.name "T"
    git add . && git commit -m "init" --no-verify
    run "$BUILDCREW_HOME/lib/workflow.sh" --batch
    [ "$status" -ne 0 ]
    [[ "$output" == *"No pending tasks"* ]]
}

@test "run: --batch with all tasks complete exits with error" {
    echo "- [x] Done task" > BACKLOG.md
    git init && git config user.email "t@t.t" && git config user.name "T"
    git add . && git commit -m "init" --no-verify
    run "$BUILDCREW_HOME/lib/workflow.sh" --batch
    [ "$status" -ne 0 ]
    [[ "$output" == *"No pending tasks"* ]]
}

@test "run: --batch outside git repo without target dirs exits with validation error" {
    echo "- [ ] Test task" > BACKLOG.md
    # TEST_DIR is not a git repo (setup_test_dir uses mktemp, no git init)
    # Without [dir:...] prefix or TARGET_DIR, validation fails
    run "$BUILDCREW_HOME/lib/workflow.sh" --batch
    [ "$status" -ne 0 ]
    [[ "$output" == *"no target directory"* ]]
}

@test "run: --batch outside git repo shows non-git info message" {
    echo "- [ ] [dir:nonexistent] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --batch
    [[ "$output" == *"Non-git parent directory"* ]]
}

@test "run: --batch --dry-run shows task list and count" {
    cat > BACKLOG.md << 'EOF'
- [ ] Task one
- [ ] Task two
- [ ] Task three
EOF
    git init && git config user.email "t@t.t" && git config user.name "T"
    git add . && git commit -m "init" --no-verify
    run "$BUILDCREW_HOME/lib/workflow.sh" --batch --dry-run
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

# ─────────────────────────────────────────────────────────────────────────────
# --interactive flag compatibility tests
# ─────────────────────────────────────────────────────────────────────────────

@test "run: --interactive --batch exits with error" {
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --interactive --batch
    [ "$status" -ne 0 ]
    [[ "$output" == *"--interactive cannot be combined with --batch"* ]]
}

@test "run: --interactive --uat exits with error" {
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --interactive --uat
    [ "$status" -ne 0 ]
    [[ "$output" == *"--interactive cannot be combined with --uat"* ]]
}

@test "run: --uat --interactive exits with error (reversed order)" {
    echo "- [ ] Test task" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --uat --interactive
    [ "$status" -ne 0 ]
    [[ "$output" == *"--interactive cannot be combined with --uat"* ]]
}

@test "run: --batch --review prints warning and no error" {
    echo "- [ ] Test task" > BACKLOG.md
    git init && git config user.email "t@t.t" && git config user.name "T"
    git add . && git commit -m "init" --no-verify
    run "$BUILDCREW_HOME/lib/workflow.sh" --batch --review --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"--review has no effect"* ]]
}
