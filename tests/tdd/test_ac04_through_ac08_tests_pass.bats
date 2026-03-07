#!/usr/bin/env bats
# AC-04 through AC-08: All test files pass

load '../setup.bash'

@test "AC-04: bats tests/unit/precompute.bats exits 0" {
    run bash -c 'cd "$(git rev-parse --show-toplevel)" && bats tests/unit/precompute.bats'
    [ "$status" -eq 0 ]
}

@test "AC-05: bats tests/unit/batch.bats exits 0" {
    run bash -c 'cd "$(git rev-parse --show-toplevel)" && bats tests/unit/batch.bats'
    [ "$status" -eq 0 ]
}

@test "AC-06: bats tests/unit/model_effort.bats exits 0" {
    run bash -c 'cd "$(git rev-parse --show-toplevel)" && bats tests/unit/model_effort.bats'
    [ "$status" -eq 0 ]
}

@test "AC-07: bats tests/unit/inline_uat.bats exits 0" {
    run bash -c 'cd "$(git rev-parse --show-toplevel)" && bats tests/unit/inline_uat.bats'
    [ "$status" -eq 0 ]
}

@test "AC-08: ./test.sh (full suite) exits 0" {
    run bash -c 'cd "$(git rev-parse --show-toplevel)" && ./test.sh'
    [ "$status" -eq 0 ]
}
