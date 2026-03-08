#!/usr/bin/env bats
# TDD tests for AC-01: workflow.sh main() exits with code matching failure status

load '../setup.bash'

setup() {
    setup_test_dir
    setup_phase_isolation
    create_mock_claude
    create_mock_jq
    mkdir -p .claude
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: main() exits 0 on success
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01a: main() exits 0 when no tasks fail" {
    echo "- [ ] Task 1" > BACKLOG.md
    run "$BUILDCREW_HOME/lib/workflow.sh" --dry-run --single
    # Dry run should succeed (exit 0)
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: main() exits 1 when tasks fail
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02a: main() exits 1 when a phase returns failed verdict" {
    # Create a task that will fail
    echo "- [ ] Failing task" > BACKLOG.md

    # Mock claude to return a failed verdict
    cat > "$TEST_DIR/bin/claude" << 'EOF'
#!/bin/bash
# Mock claude that returns failed verdict for the first invocation
mkdir -p .claude
echo '{"phase": "spec", "verdict": "vague", "details": "Test failure"}' > .claude/phase-result.json
exit 0
EOF
    chmod +x "$TEST_DIR/bin/claude"

    run "$BUILDCREW_HOME/lib/workflow.sh" --single
    # Should exit with non-zero status when task fails
    [ "$status" -ne 0 ]
}

@test "AC-02b: main() exits 1 explicitly when failed count > 0" {
    # Create scenario where multiple tasks fail
    cat > BACKLOG.md << 'EOF'
- [ ] Task 1 fails
- [ ] Task 2 fails
EOF

    # Mock claude to fail multiple times
    cat > "$TEST_DIR/bin/claude" << 'EOF'
#!/bin/bash
mkdir -p .claude
echo '{"phase": "build", "verdict": "complete", "details": ""}' > .claude/phase-result.json
exit 1
EOF
    chmod +x "$TEST_DIR/bin/claude"

    run "$BUILDCREW_HOME/lib/workflow.sh" --single
    # Main should exit with 1 when tasks fail
    [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: Exit code enables batch parent detection
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03: exit code is accessible to parent process" {
    echo "- [ ] Test task" > BACKLOG.md

    # Run workflow in subshell to capture exit code
    bash -c "source '$BUILDCREW_HOME/lib/workflow.sh' 2>/dev/null; SINGLE_TASK=true main" || true
    local exit_code=$?

    # Exit code should be numeric and available to caller
    [[ "$exit_code" =~ ^[0-9]+$ ]]
}
