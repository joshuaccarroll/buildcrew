#!/usr/bin/env bats
# TDD Scaffold: buildcrew status — context files + config display
# Covers: AC-01, AC-02, AC-03, AC-04, AC-05, AC-06, AC-07, AC-08

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
# AC-01: context files present — show with size; absent — show (not set)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01a: status shows context file present with size (users.md)" {
    mkdir -p .buildcrew/context
    printf 'hello world content here\n' > .buildcrew/context/users.md

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"users.md"* ]]
    [[ "$output" == *"KB"* ]]
    [[ "$output" == *"✓"* ]]
}

@test "AC-01b: status shows context file present with size (principles.md)" {
    mkdir -p .buildcrew/context
    printf 'some principles text\n' > .buildcrew/context/principles.md

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"principles.md"* ]]
    [[ "$output" == *"KB"* ]]
    [[ "$output" == *"✓"* ]]
}

@test "AC-01c: status shows context file absent with (not set)" {
    mkdir -p .buildcrew/context
    # only users.md exists; domain.md is absent

    printf 'users content\n' > .buildcrew/context/users.md

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"domain.md"* ]]
    [[ "$output" == *"(not set)"* ]]
    [[ "$output" == *"○"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: context dir missing — show "Not initialized" note, no section header
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02: status shows 'Not initialized' when .buildcrew/context/ missing" {
    # Ensure .buildcrew/context does NOT exist
    rm -rf .buildcrew/context

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Not initialized"* ]]
}

@test "AC-02b: status does not show context section header when context dir missing" {
    rm -rf .buildcrew/context

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    # When context dir missing, "Project Context:" header should still appear
    # but the not-initialized message replaces the file list
    [[ "$output" != *"users.md"* ]]
    [[ "$output" != *"principles.md"* ]]
    [[ "$output" != *"domain.md"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: project-rules.md NOT listed
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03: status does NOT include project-rules.md in context files" {
    mkdir -p .buildcrew/context
    printf 'rules\n' > .buildcrew/context/users.md

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" != *"project-rules.md"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: config section shows all 6 keys
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04a: status shows config section with all 6 keys (with config file)" {
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
}

@test "AC-04b: status config shows custom value when set in config file" {
    mkdir -p .buildcrew
    printf 'AUTO_MODE=true\nMAX_INVOCATIONS=20\n' > .buildcrew/config

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO_MODE=true"* ]]
    [[ "$output" == *"MAX_INVOCATIONS=20"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: (defaults) label
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-05a: status config shows (defaults) when no config file exists" {
    rm -f .buildcrew/config

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"(defaults)"* ]]
}

@test "AC-05b: status config does NOT show (defaults) when config file exists" {
    mkdir -p .buildcrew
    printf 'AUTO_MODE=false\n' > .buildcrew/config

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" != *"(defaults)"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-06: actual config key names used (not abbreviations)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-06a: status config uses TDD_MODE not abbreviated form" {
    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"TDD_MODE="* ]]
}

@test "AC-06b: status config uses AUTO_MODE not abbreviated form" {
    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO_MODE="* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-07: correct default values for all 6 keys
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-07a: status shows MAX_INVOCATIONS default as 15" {
    rm -f .buildcrew/config

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"MAX_INVOCATIONS=15"* ]]
}

@test "AC-07b: status shows COMPLEXITY_AWARE default as true" {
    rm -f .buildcrew/config

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMPLEXITY_AWARE=true"* ]]
}

@test "AC-07c: status shows AUTO_MODE default as false" {
    rm -f .buildcrew/config

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO_MODE=false"* ]]
}

@test "AC-07d: status shows TDD_MODE default as false" {
    rm -f .buildcrew/config

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"TDD_MODE=false"* ]]
}

@test "AC-07e: status shows KEEP_LOGS default as false" {
    rm -f .buildcrew/config

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"KEEP_LOGS=false"* ]]
}

@test "AC-07f: status shows MAX_PARALLEL default as 5" {
    rm -f .buildcrew/config

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"MAX_PARALLEL=5"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-08: combined scenarios
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-08a: status shows context files + config when both exist" {
    mkdir -p .buildcrew/context
    printf 'users content\n' > .buildcrew/context/users.md
    mkdir -p .buildcrew
    printf 'TDD_MODE=true\n' > .buildcrew/config

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"users.md"* ]]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"TDD_MODE=true"* ]]
    [[ "$output" != *"(defaults)"* ]]
}

@test "AC-08b: status shows context not initialized + default config when neither exist" {
    rm -rf .buildcrew/context
    rm -f .buildcrew/config

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Not initialized"* ]]
    [[ "$output" == *"MAX_INVOCATIONS=15"* ]]
    [[ "$output" == *"(defaults)"* ]]
}

@test "AC-08c: status shows context files with partial config override" {
    mkdir -p .buildcrew/context
    printf 'principles text\n' > .buildcrew/context/principles.md
    mkdir -p .buildcrew
    printf 'MAX_INVOCATIONS=30\n' > .buildcrew/config

    run "$BUILDCREW_HOME/bin/buildcrew" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"principles.md"* ]]
    [[ "$output" == *"MAX_INVOCATIONS=30"* ]]
    [[ "$output" == *"AUTO_MODE=false"* ]]
    [[ "$output" != *"(defaults)"* ]]
}
