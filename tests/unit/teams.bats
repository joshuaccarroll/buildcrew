#!/usr/bin/env bats
# Unit tests for lib/teams.sh

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
    source_lib "teams.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# check_teams_prerequisites tests
# ─────────────────────────────────────────────────────────────────────────────

@test "check_teams_prerequisites: fails without env var" {
    unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 2>/dev/null || true
    run check_teams_prerequisites
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"* ]]
}

@test "check_teams_prerequisites: passes with env var set to 1" {
    export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
    run check_teams_prerequisites
    [ "$status" -eq 0 ]
}

@test "check_teams_prerequisites: fails when env var is 0" {
    export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0
    run check_teams_prerequisites
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# build_team_lead_prompt tests
# ─────────────────────────────────────────────────────────────────────────────

@test "build_team_lead_prompt: output includes task text" {
    run build_team_lead_prompt "Implement user authentication"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Implement user authentication"* ]]
}

@test "build_team_lead_prompt: output includes all 5 teammate roles" {
    run build_team_lead_prompt "Test task"
    [[ "$output" == *"researcher"* ]]
    [[ "$output" == *"principal-engineer"* ]]
    [[ "$output" == *"feature-engineer"* ]]
    [[ "$output" == *"qa-engineer"* ]]
    [[ "$output" == *"security-engineer"* ]]
}

@test "build_team_lead_prompt: includes project context when present" {
    mkdir -p .buildcrew/context
    echo "Our users are developers" > .buildcrew/context/users.md
    run build_team_lead_prompt "Test task"
    [[ "$output" == *"Our users are developers"* ]]
}

@test "build_team_lead_prompt: shows fallback when no context files" {
    run build_team_lead_prompt "Test task"
    [[ "$output" == *"No project context files found"* ]]
}
