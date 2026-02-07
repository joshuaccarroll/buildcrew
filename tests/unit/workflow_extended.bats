#!/usr/bin/env bats
# Unit tests for untested functions in lib/workflow.sh

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# get_phase_max_turns tests
# ─────────────────────────────────────────────────────────────────────────────

@test "get_phase_max_turns: research returns 40" {
    run get_phase_max_turns "research"
    [ "$output" = "40" ]
}

@test "get_phase_max_turns: review returns 50" {
    run get_phase_max_turns "review"
    [ "$output" = "50" ]
}

@test "get_phase_max_turns: build returns 50" {
    run get_phase_max_turns "build"
    [ "$output" = "50" ]
}

@test "get_phase_max_turns: test returns 60" {
    run get_phase_max_turns "test"
    [ "$output" = "60" ]
}

@test "get_phase_max_turns: verify returns 30" {
    run get_phase_max_turns "verify"
    [ "$output" = "30" ]
}

@test "get_phase_max_turns: unknown phase returns 30" {
    run get_phase_max_turns "deploy"
    [ "$output" = "30" ]
}

@test "get_phase_max_turns: empty string returns 30" {
    run get_phase_max_turns ""
    [ "$output" = "30" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# task_to_branch_name tests
# ─────────────────────────────────────────────────────────────────────────────

@test "task_to_branch_name: adds buildcrew/ prefix" {
    run task_to_branch_name "simple task"
    [[ "$output" == buildcrew/* ]]
}

@test "task_to_branch_name: lowercases input" {
    run task_to_branch_name "Fix The BUG"
    [ "$output" = "buildcrew/fix-the-bug" ]
}

@test "task_to_branch_name: replaces non-alphanumeric with hyphens" {
    run task_to_branch_name "fix: bug in /api/users"
    [ "$output" = "buildcrew/fix-bug-in-api-users" ]
}

@test "task_to_branch_name: collapses multiple hyphens" {
    run task_to_branch_name "fix   multiple   spaces"
    [ "$output" = "buildcrew/fix-multiple-spaces" ]
}

@test "task_to_branch_name: trims leading and trailing hyphens" {
    run task_to_branch_name "---hello world---"
    [ "$output" = "buildcrew/hello-world" ]
}

@test "task_to_branch_name: truncates to 60 chars" {
    local long_task="this is a very long task name that should definitely be truncated because it exceeds sixty characters"
    run task_to_branch_name "$long_task"
    local slug="${output#buildcrew/}"
    [ "${#slug}" -le 60 ]
}

@test "task_to_branch_name: handles backticks and parentheses" {
    run task_to_branch_name "Create \`tests/e2e/seed.ts\` — a utility (v1.0+) module"
    [ "$output" = "buildcrew/create-tests-e2e-seed-ts-a-utility-v1-0-module" ]
}

@test "task_to_branch_name: handles pure alphanumeric" {
    run task_to_branch_name "task123"
    [ "$output" = "buildcrew/task123" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# check_stop_signal / clear_stop_signal / handle_stop tests
# ─────────────────────────────────────────────────────────────────────────────

@test "check_stop_signal: returns 1 when no stop file exists" {
    mkdir -p .buildcrew
    run check_stop_signal
    [ "$status" -eq 1 ]
}

@test "check_stop_signal: returns 0 when stop file exists" {
    mkdir -p .buildcrew
    touch .buildcrew/.stop-workflow
    run check_stop_signal
    [ "$status" -eq 0 ]
}

@test "clear_stop_signal: removes stop file" {
    mkdir -p .buildcrew
    touch .buildcrew/.stop-workflow
    clear_stop_signal
    [ ! -f .buildcrew/.stop-workflow ]
}

@test "clear_stop_signal: succeeds when no stop file" {
    run clear_stop_signal
    [ "$status" -eq 0 ]
}

@test "check_stop_signal: returns 1 after clear" {
    mkdir -p .buildcrew
    touch .buildcrew/.stop-workflow
    clear_stop_signal
    run check_stop_signal
    [ "$status" -eq 1 ]
}

@test "handle_stop: removes file and prints warning" {
    mkdir -p .buildcrew
    touch .buildcrew/.stop-workflow
    run handle_stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stop signal received"* ]]
    [ ! -f .buildcrew/.stop-workflow ]
}

# ─────────────────────────────────────────────────────────────────────────────
# parse_args tests
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --dry-run sets DRY_RUN=true" {
    parse_args --dry-run
    [ "$DRY_RUN" = "true" ]
}

@test "parse_args: --single sets SINGLE_TASK=true" {
    parse_args --single
    [ "$SINGLE_TASK" = "true" ]
}

@test "parse_args: --review sets HUMAN_REVIEW=true" {
    parse_args --review
    [ "$HUMAN_REVIEW" = "true" ]
}

@test "parse_args: --branch sets GIT_BRANCH=true" {
    parse_args --branch
    [ "$GIT_BRANCH" = "true" ]
}

@test "parse_args: --teams sets USE_TEAMS=true" {
    parse_args --teams
    [ "$USE_TEAMS" = "true" ]
}

@test "parse_args: multiple flags combined" {
    parse_args --dry-run --single --review --branch --teams
    [ "$DRY_RUN" = "true" ]
    [ "$SINGLE_TASK" = "true" ]
    [ "$HUMAN_REVIEW" = "true" ]
    [ "$GIT_BRANCH" = "true" ]
    [ "$USE_TEAMS" = "true" ]
}

@test "parse_args: no args preserves defaults" {
    parse_args
    [ "$DRY_RUN" = "false" ]
    [ "$SINGLE_TASK" = "false" ]
    [ "$HUMAN_REVIEW" = "false" ]
    [ "$GIT_BRANCH" = "false" ]
    [ "$USE_TEAMS" = "false" ]
}

@test "parse_args: --help exits 0" {
    run parse_args --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "parse_args: -h exits 0" {
    run parse_args -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "parse_args: unknown option exits 1" {
    run parse_args --invalid
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# is_phase_isolation_available tests
# ─────────────────────────────────────────────────────────────────────────────

@test "is_phase_isolation_available: returns 1 when no skill file" {
    run is_phase_isolation_available
    [ "$status" -eq 1 ]
}

@test "is_phase_isolation_available: returns 1 when skill file lacks marker" {
    mkdir -p .claude/skills/buildcrew
    echo "# BuildCrew Skill" > .claude/skills/buildcrew/SKILL.md
    run is_phase_isolation_available
    [ "$status" -eq 1 ]
}

@test "is_phase_isolation_available: returns 1 when marker exists but dirs missing" {
    mkdir -p .claude/skills/buildcrew
    echo "phase-isolation enabled" > .claude/skills/buildcrew/SKILL.md
    # Only create some dirs, not all 5
    mkdir -p .claude/skills/buildcrew-research
    mkdir -p .claude/skills/buildcrew-review
    run is_phase_isolation_available
    [ "$status" -eq 1 ]
}

@test "is_phase_isolation_available: returns 0 when marker and all dirs exist" {
    mkdir -p .claude/skills/buildcrew
    echo "phase-isolation enabled" > .claude/skills/buildcrew/SKILL.md
    mkdir -p .claude/skills/buildcrew-research
    mkdir -p .claude/skills/buildcrew-review
    mkdir -p .claude/skills/buildcrew-build
    mkdir -p .claude/skills/buildcrew-test
    mkdir -p .claude/skills/buildcrew-verify
    run is_phase_isolation_available
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# handle_human_review early-return path tests
# ─────────────────────────────────────────────────────────────────────────────

@test "handle_human_review: returns 0 when HUMAN_REVIEW=false" {
    HUMAN_REVIEW=false
    run handle_human_review "task" "description" "artifact"
    [ "$status" -eq 0 ]
}

@test "handle_human_review: returns 0 with warning when non-interactive" {
    HUMAN_REVIEW=true
    run handle_human_review "task" "description" "artifact"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Non-interactive terminal"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# save_original_branch / ensure_clean_worktree tests
# ─────────────────────────────────────────────────────────────────────────────

@test "save_original_branch: sets ORIGINAL_BRANCH to current branch" {
    git init
    git config user.email "test@buildcrew.test"
    git config user.name "Test"
    git commit --allow-empty -m "init"

    local expected_branch
    expected_branch=$(git rev-parse --abbrev-ref HEAD)

    save_original_branch
    [ "$ORIGINAL_BRANCH" = "$expected_branch" ]
}

@test "ensure_clean_worktree: returns 0 on clean tree" {
    git init
    git config user.email "test@buildcrew.test"
    git config user.name "Test"
    git commit --allow-empty -m "init"

    run ensure_clean_worktree
    [ "$status" -eq 0 ]
}

@test "ensure_clean_worktree: returns 1 when untracked files exist" {
    git init
    git config user.email "test@buildcrew.test"
    git config user.name "Test"
    git commit --allow-empty -m "init"
    echo "untracked" > newfile.txt

    run ensure_clean_worktree
    [ "$status" -eq 1 ]
}
