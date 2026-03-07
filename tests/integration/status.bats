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

# ─────────────────────────────────────────────────────────────────────────────
# Project Context section tests
# ─────────────────────────────────────────────────────────────────────────────

@test "status: shows context files with size when present" {
    mkdir -p .buildcrew/context
    printf 'hello world\n' > .buildcrew/context/users.md
    printf 'some principles\n' > .buildcrew/context/principles.md

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"users.md"* ]]
    [[ "$output" == *"principles.md"* ]]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"KB"* ]]
}

@test "status: shows context dir missing message when not initialized" {
    rm -rf .buildcrew/context

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Not initialized"* ]]
    [[ "$output" == *"buildcrew init"* ]]
}

@test "status: shows (not set) for absent context file" {
    command mkdir -p .buildcrew/context
    printf 'users\n' > .buildcrew/context/users.md
    # principles.md and domain.md absent

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"(not set)"* ]]
    [[ "$output" == *"○"* ]]
}

@test "status: does not include project-rules.md in context section" {
    mkdir -p .buildcrew/context
    printf 'rules\n' > .buildcrew/context/users.md

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" != *"project-rules.md"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Config section tests
# ─────────────────────────────────────────────────────────────────────────────

@test "status: shows config section with all 6 keys when config file present" {
    mkdir -p .buildcrew
    printf 'AUTO_MODE=true\n' > .buildcrew/config

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"MAX_INVOCATIONS="* ]]
    [[ "$output" == *"COMPLEXITY_AWARE="* ]]
    [[ "$output" == *"AUTO_MODE="* ]]
    [[ "$output" == *"TDD_MODE="* ]]
    [[ "$output" == *"KEEP_LOGS="* ]]
    [[ "$output" == *"MAX_PARALLEL="* ]]
    [[ "$output" != *"(defaults)"* ]]
}

@test "status: shows (defaults) in config section when no config file" {
    rm -f .buildcrew/config

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"(defaults)"* ]]
    [[ "$output" == *"MAX_INVOCATIONS=15"* ]]
    [[ "$output" == *"AUTO_MODE=false"* ]]
    [[ "$output" == *"TDD_MODE=false"* ]]
}
