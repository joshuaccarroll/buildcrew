#!/usr/bin/env bats
# Unit tests for TDD scaffold validation (__validate_tdd_scaffold, __run_with_timeout)

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# __run_with_timeout
# ─────────────────────────────────────────────────────────────────────────────

@test "__run_with_timeout: runs command successfully" {
    run __run_with_timeout 5 echo "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "__run_with_timeout: returns command exit code" {
    run __run_with_timeout 5 bash -c "exit 1"
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# __validate_tdd_scaffold
# ─────────────────────────────────────────────────────────────────────────────

@test "__validate_tdd_scaffold: no-op when TDD_MODE=false" {
    TDD_MODE=false
    run __validate_tdd_scaffold
    [ "$status" -eq 0 ]
}

@test "__validate_tdd_scaffold: no-op when manifest missing" {
    TDD_MODE=true
    run __validate_tdd_scaffold
    [ "$status" -eq 0 ]
}

@test "__validate_tdd_scaffold: no-op when test_command empty" {
    TDD_MODE=true
    mkdir -p .claude
    echo '{"test_command": ""}' > .claude/tdd-manifest.json
    run __validate_tdd_scaffold
    [ "$status" -eq 0 ]
}

@test "__validate_tdd_scaffold: passes when tests fail (expected)" {
    TDD_MODE=true
    mkdir -p .claude
    echo '{"test_command": "exit 1"}' > .claude/tdd-manifest.json
    run __validate_tdd_scaffold
    [ "$status" -eq 0 ]
    [[ "$output" == *"tests fail as expected"* ]]
}

@test "__validate_tdd_scaffold: fails when tests pass (unexpected)" {
    TDD_MODE=true
    mkdir -p .claude
    echo '{"test_command": "exit 0"}' > .claude/tdd-manifest.json
    run __validate_tdd_scaffold
    [ "$status" -eq 1 ]
    [[ "$output" == *"tests pass before build"* ]]
}

@test "__validate_tdd_scaffold: no-op when test_command key missing" {
    TDD_MODE=true
    mkdir -p .claude
    echo '{"test_files": ["a.ts"]}' > .claude/tdd-manifest.json
    run __validate_tdd_scaffold
    [ "$status" -eq 0 ]
}
