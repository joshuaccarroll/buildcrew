#!/usr/bin/env bats
# Integration tests for CLI command dispatch in bin/buildcrew

load '../setup.bash'

setup() {
    setup_test_dir
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# version command tests
# ─────────────────────────────────────────────────────────────────────────────

@test "cli: version prints version string" {
    run "$BUILDCREW_HOME/bin/buildcrew" version
    [ "$status" -eq 0 ]
    [[ "$output" == *"BuildCrew"* ]]
    [[ "$output" == *"v"* ]]
}

@test "cli: --version prints version string" {
    run "$BUILDCREW_HOME/bin/buildcrew" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"BuildCrew"* ]]
}

@test "cli: -v prints version string" {
    run "$BUILDCREW_HOME/bin/buildcrew" -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"BuildCrew"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# help command tests
# ─────────────────────────────────────────────────────────────────────────────

@test "cli: help prints usage" {
    run "$BUILDCREW_HOME/bin/buildcrew" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE:"* ]]
}

@test "cli: --help prints usage" {
    run "$BUILDCREW_HOME/bin/buildcrew" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE:"* ]]
}

@test "cli: -h prints usage" {
    run "$BUILDCREW_HOME/bin/buildcrew" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE:"* ]]
}

@test "cli: no args prints usage" {
    run "$BUILDCREW_HOME/bin/buildcrew"
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE:"* ]]
}

@test "cli: help mentions --sequential flag" {
    run "$BUILDCREW_HOME/bin/buildcrew" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--sequential"* ]]
}

@test "cli: help marks --batch as deprecated" {
    run "$BUILDCREW_HOME/bin/buildcrew" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--batch"* ]]
    [[ "$output" == *"deprecated"* ]]
}

@test "cli: help mentions --max-parallel without 'with run --batch' qualifier" {
    run "$BUILDCREW_HOME/bin/buildcrew" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--max-parallel"* ]]
    # Should not say "with 'run --batch'" — batch is now default
    [[ "$output" != *"with 'run --batch'"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# unknown command test
# ─────────────────────────────────────────────────────────────────────────────

@test "cli: unknown command exits 1" {
    run "$BUILDCREW_HOME/bin/buildcrew" foobar
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# stop command test
# ─────────────────────────────────────────────────────────────────────────────

@test "cli: stop creates stop signal file" {
    run "$BUILDCREW_HOME/bin/buildcrew" stop
    [ "$status" -eq 0 ]
    [ -f .buildcrew/.stop-workflow ]
    [[ "$output" == *"Stop signal sent"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# reset command tests
# ─────────────────────────────────────────────────────────────────────────────

@test "cli: reset fails without BACKLOG.md" {
    run "$BUILDCREW_HOME/bin/buildcrew" reset
    [ "$status" -eq 1 ]
    [[ "$output" == *"No BACKLOG.md found"* ]]
}

@test "cli: reset clears blocked tasks to pending" {
    cat > BACKLOG.md << 'EOF'
# Backlog
- [x] Completed task
- [!] Blocked task one (blocked: Plan rejected)
- [ ] Pending task
- [!] Blocked task two (blocked: Build failed after 2 attempts)
EOF
    run "$BUILDCREW_HOME/bin/buildcrew" reset
    [ "$status" -eq 0 ]
    [[ "$output" == *"Reset 2 blocked task"* ]]
    # Verify blocked tasks are now pending
    run grep -c '^\- \[ \]' BACKLOG.md
    [ "$output" = "3" ]
    # Verify no blocked tasks remain
    run grep -c '^\- \[!\]' BACKLOG.md
    [ "$output" = "0" ]
    # Verify completed task is untouched
    run grep -c '^\- \[x\]' BACKLOG.md
    [ "$output" = "1" ]
}

@test "cli: reset removes .claude artifacts" {
    cat > BACKLOG.md << 'EOF'
# Backlog
- [ ] Task one
EOF
    mkdir -p .claude
    echo "research" > .claude/research.md
    echo "plan" > .claude/current-plan.md
    echo '{"status":"complete"}' > .claude/workflow-status.json
    run "$BUILDCREW_HOME/bin/buildcrew" reset
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed 3 artifact"* ]]
    [ ! -f .claude/research.md ]
    [ ! -f .claude/current-plan.md ]
    [ ! -f .claude/workflow-status.json ]
}

@test "cli: reset removes stale state files" {
    cat > BACKLOG.md << 'EOF'
# Backlog
- [ ] Task one
EOF
    mkdir -p .buildcrew
    echo "12345" > .buildcrew/.workflow-lock
    echo '{"task":"test"}' > .buildcrew/task-progress.json
    echo "test task" > .buildcrew/.current-task
    touch .buildcrew/.stop-workflow
    run "$BUILDCREW_HOME/bin/buildcrew" reset
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed 4 state"* ]]
    [ ! -f .buildcrew/.workflow-lock ]
    [ ! -f .buildcrew/task-progress.json ]
    [ ! -f .buildcrew/.current-task ]
    [ ! -f .buildcrew/.stop-workflow ]
}

@test "cli: reset with nothing to clean shows no-op messages" {
    cat > BACKLOG.md << 'EOF'
# Backlog
- [ ] Task one
- [x] Completed task
EOF
    run "$BUILDCREW_HOME/bin/buildcrew" reset
    [ "$status" -eq 0 ]
    [[ "$output" == *"No blocked tasks"* ]]
    [[ "$output" == *"No artifacts"* ]]
    [[ "$output" == *"No stale state"* ]]
    [[ "$output" == *"Reset complete"* ]]
}

@test "cli: reset strips blocked reason from task name" {
    cat > BACKLOG.md << 'EOF'
# Backlog
- [!] Add user auth (blocked: Plan review failed to converge after 3 cycles)
EOF
    run "$BUILDCREW_HOME/bin/buildcrew" reset
    [ "$status" -eq 0 ]
    # Task name should be clean, without the reason
    run grep '^\- \[ \] Add user auth$' BACKLOG.md
    [ "$status" -eq 0 ]
}
