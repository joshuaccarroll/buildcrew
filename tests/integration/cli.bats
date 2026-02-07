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
