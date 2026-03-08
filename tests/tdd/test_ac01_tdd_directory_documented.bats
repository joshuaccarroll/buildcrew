#!/usr/bin/env bats
# AC-01: TDD directory role is documented

load '../setup.bash'

@test "AC-01: tests/README.md exists" {
    [ -f "tests/README.md" ]
}

@test "AC-01: tests/README.md contains 'TDD' reference" {
    grep -qi 'tdd' "tests/README.md"
}

@test "AC-01: tests/README.md explains what tests/tdd contains" {
    grep -qi 'pre-implementation\|scaffold\|failing' "tests/README.md"
}

@test "AC-01: tests/README.md explains why tests/tdd is excluded" {
    grep -qi 'excluded\|not yet\|exclude' "tests/README.md"
}
