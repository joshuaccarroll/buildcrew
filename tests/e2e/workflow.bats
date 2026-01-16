#!/usr/bin/env bats
# End-to-end tests for BuildCrew
# These tests require a real Claude Code installation and API access
# Run with: BUILDCREW_E2E=1 bats tests/e2e/

load '../setup.bash'

setup() {
    # Skip if E2E not enabled
    if [ "$BUILDCREW_E2E" != "1" ]; then
        skip "E2E tests disabled. Set BUILDCREW_E2E=1 to enable."
    fi

    # Check for real claude
    if ! command -v claude &> /dev/null; then
        skip "Claude Code CLI not installed"
    fi

    setup_test_dir
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# Full workflow E2E tests
# ─────────────────────────────────────────────────────────────────────────────

@test "e2e: init and run creates expected structure" {
    "$BUILDCREW_HOME/bin/buildcrew" init

    # Verify init created everything
    [ -d ".claude" ]
    [ -d ".buildcrew" ]
    [ -f "BACKLOG.md" ]
    [ -f ".claude/settings.json" ]
}

@test "e2e: simple file creation task" {
    "$BUILDCREW_HOME/bin/buildcrew" init

    # Create a simple task
    cat > BACKLOG.md << 'EOF'
# Backlog

- [ ] Create a file called hello.txt containing the text "Hello, World!"
EOF

    # Run the workflow
    run "$BUILDCREW_HOME/bin/buildcrew" run --single
    [ "$status" -eq 0 ]

    # Verify the file was created
    [ -f "hello.txt" ]
    grep -q "Hello" hello.txt
}

@test "e2e: task marked complete after successful execution" {
    "$BUILDCREW_HOME/bin/buildcrew" init

    cat > BACKLOG.md << 'EOF'
# Backlog

- [ ] Create an empty file called test.txt
EOF

    run "$BUILDCREW_HOME/bin/buildcrew" run --single
    [ "$status" -eq 0 ]

    # Task should be marked complete
    grep -q "\[x\]" BACKLOG.md
}

@test "e2e: multiple tasks processed in sequence" {
    "$BUILDCREW_HOME/bin/buildcrew" init

    cat > BACKLOG.md << 'EOF'
# Backlog

- [ ] Create a file called one.txt with content "1"
- [ ] Create a file called two.txt with content "2"
EOF

    # Run all tasks
    run "$BUILDCREW_HOME/bin/buildcrew" run

    # Both files should exist
    [ -f "one.txt" ]
    [ -f "two.txt" ]

    # Both tasks should be marked complete
    [ "$(grep -c '\[x\]' BACKLOG.md)" -eq 2 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Smart backlog detection E2E tests
# ─────────────────────────────────────────────────────────────────────────────

@test "e2e: fresh project launches build mode" {
    "$BUILDCREW_HOME/bin/buildcrew" init

    # Keep the template backlog (has "Your first task here")
    # Running should detect this and launch build mode

    # This test is tricky because build mode is interactive
    # We'll just verify the detection logic works
    run bash -c 'source "$BUILDCREW_HOME/lib/workflow.sh" 2>/dev/null; is_fresh_backlog && echo "fresh" || echo "not fresh"'
    [ "$output" = "fresh" ]
}
