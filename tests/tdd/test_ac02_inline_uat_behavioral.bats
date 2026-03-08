#!/usr/bin/env bats
# AC-02: inline_uat.bats structural tests replaced with behavioral tests

load '../setup.bash'

@test "AC-02: inline_uat.bats no longer greps lib/workflow.sh for --no-uat" {
    # Test 4a: Should be replaced with parse_args --help behavioral test
    ! grep -n "grep.*'--no-uat'.*lib/workflow.sh" tests/unit/inline_uat.bats
}

@test "AC-02: inline_uat.bats no longer greps for inline UAT markers" {
    # Test 4b: Should be replaced with declare -f behavioral test
    ! grep -n "grep.*'── Inline UAT ──'.*lib/workflow.sh" tests/unit/inline_uat.bats
}

@test "AC-02: inline_uat.bats no longer greps for post-completion UAT order" {
    # Tests 4c/4f: Should be replaced with declare -f behavioral tests
    ! grep -n "grep.*'All backlog tasks processed'.*lib/workflow.sh" tests/unit/inline_uat.bats
}

@test "AC-02: inline_uat.bats no longer greps for UAT guards" {
    # Test 4d: Should be replaced with declare -f behavioral test
    ! grep -n "grep.*'NO_UAT.*failed.*README.*SINGLE_TASK'.*lib/workflow.sh" tests/unit/inline_uat.bats
}

@test "AC-02: inline_uat.bats no longer greps for task_result -eq 2" {
    # Test 4h: Should be replaced with declare -f behavioral test
    ! grep -n "grep.*'task_result -eq 2'.*lib/workflow.sh" tests/unit/inline_uat.bats
}

@test "AC-02: inline_uat.bats no longer greps bin/buildcrew for cmd_uat" {
    # Tests 4i/4j: Should be replaced with behavioral tests
    ! grep -n "grep.*bin/buildcrew" tests/unit/inline_uat.bats
}
