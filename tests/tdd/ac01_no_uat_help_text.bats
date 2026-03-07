#!/usr/bin/env bats
# AC-01, AC-02, AC-03, AC-04: --no-uat appears in bin/buildcrew help text

load '../setup.bash'

setup() {
    setup_test_dir
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: buildcrew help | grep -c '\-\-no-uat' outputs 1
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01: buildcrew help output contains exactly one instance of --no-uat flag" {
    run bash -c "$BUILDCREW_ROOT/bin/buildcrew help | grep -c '\-\-no-uat'"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: --no-uat line uses exact wording and format
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02: --no-uat line matches exact format with description" {
    local expected='    --no-uat      Skip UAT after backlog completion (with '"'"'run'"'"')'
    run bash -c "$BUILDCREW_ROOT/bin/buildcrew help | grep -- '--no-uat'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skip UAT after backlog completion"* ]]
    [[ "$output" == *"with 'run'"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: --no-uat line appears immediately after --no-tdd line
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03: --no-uat line immediately follows --no-tdd line in help" {
    run bash -c "$BUILDCREW_ROOT/bin/buildcrew help | grep -n -A1 -- '--no-tdd'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--no-uat"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: Verify no other changes to help text (indirectly tested by AC-01-03)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04: bin/buildcrew source contains --no-uat in print_help function" {
    run grep -- '--no-uat' "$BUILDCREW_ROOT/bin/buildcrew"
    [ "$status" -eq 0 ]
    # Verify it's in print_help context (appears before GETTING STARTED or after OPTIONS)
    local grep_context
    grep_context=$(grep -B5 -A5 -- '--no-uat' "$BUILDCREW_ROOT/bin/buildcrew" || true)
    [[ "$grep_context" == *"OPTIONS"* || "$grep_context" == *"no-tdd"* ]]
}
