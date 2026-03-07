#!/usr/bin/env bats
# AC-01: Builder writes all three context files before Step 5 on new-project path

load '../setup.bash'

setup() {
    setup_test_dir
    mkdir -p .buildcrew/context
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: Context files creation tests
# Expected: Builder skill writes these files after discovery completes.
# These tests expect the files to exist and contain structured content.
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01a: .buildcrew/context/users.md is created by builder during discovery" {
    # The builder skill should write users.md before Step 5 (backlog generation)
    # This test fails if the file doesn't exist (expected until builder is implemented)
    [ -f ".buildcrew/context/users.md" ]
    [ -s ".buildcrew/context/users.md" ]
}

@test "AC-01b: .buildcrew/context/principles.md is created by builder during discovery" {
    # The builder skill should write principles.md before Step 5
    [ -f ".buildcrew/context/principles.md" ]
    [ -s ".buildcrew/context/principles.md" ]
}

@test "AC-01c: .buildcrew/context/domain.md is created by builder during discovery" {
    # The builder skill should write domain.md before Step 5
    [ -f ".buildcrew/context/domain.md" ]
    [ -s ".buildcrew/context/domain.md" ]
}

@test "AC-01d: all three context files are readable after discovery" {
    # All three files must be readable after builder completes
    [ -r ".buildcrew/context/users.md" ]
    [ -r ".buildcrew/context/principles.md" ]
    [ -r ".buildcrew/context/domain.md" ]
}

@test "AC-01e: context files contain structured markdown content" {
    # Files should contain markdown structure (headers or bullet points)
    # users.md should describe target user segments
    grep -E "^#|^-" ".buildcrew/context/users.md" > /dev/null

    # principles.md should describe design principles
    grep -E "^#|^-" ".buildcrew/context/principles.md" > /dev/null

    # domain.md should contain domain terms and glossary
    grep -E "^#|^-" ".buildcrew/context/domain.md" > /dev/null
}
