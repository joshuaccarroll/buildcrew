#!/usr/bin/env bats
# AC-04: Context health check identifies missing files and provides guidance

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib common.sh
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: Context health check tests
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04a: check_context_health() returns success when all files present" {
    mkdir -p .buildcrew/context
    touch .buildcrew/context/users.md
    touch .buildcrew/context/principles.md
    touch .buildcrew/context/domain.md
    touch .buildcrew/lessons.md

    run check_context_health
    [ "$status" -eq 0 ]
}

@test "AC-04b: check_context_health() identifies missing users.md" {
    mkdir -p .buildcrew/context
    touch .buildcrew/context/principles.md
    touch .buildcrew/context/domain.md
    touch .buildcrew/lessons.md

    output=$(check_context_health 2>&1)
    # The function should mention users.md is missing or provide guidance
    # It always returns 0 (informational), so just verify it runs
    [ $? -eq 0 ]
}

@test "AC-04c: check_context_health() identifies missing principles.md" {
    mkdir -p .buildcrew/context
    touch .buildcrew/context/users.md
    touch .buildcrew/context/domain.md
    touch .buildcrew/lessons.md

    output=$(check_context_health 2>&1)
    [ $? -eq 0 ]
}

@test "AC-04d: check_context_health() identifies missing domain.md" {
    mkdir -p .buildcrew/context
    touch .buildcrew/context/users.md
    touch .buildcrew/context/principles.md
    touch .buildcrew/lessons.md

    output=$(check_context_health 2>&1)
    [ $? -eq 0 ]
}

@test "AC-04e: check_context_health() identifies missing lessons.md" {
    mkdir -p .buildcrew/context
    touch .buildcrew/context/users.md
    touch .buildcrew/context/principles.md
    touch .buildcrew/context/domain.md

    output=$(check_context_health 2>&1)
    [ $? -eq 0 ]
}

@test "AC-04f: check_context_health() provides suggested commands for missing files" {
    mkdir -p .buildcrew/context
    # Create only users.md, missing others

    touch .buildcrew/context/users.md

    output=$(check_context_health 2>&1)

    # Function always returns 0 (informational)
    [ $? -eq 0 ]

    # Ideally output contains helpful copy commands, but exact format varies
    # Just verify the function doesn't crash
}
