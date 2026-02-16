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

# ─────────────────────────────────────────────────────────────────────────────
# create_task_branch tests
# ─────────────────────────────────────────────────────────────────────────────

@test "create_task_branch: creates branch from current" {
    git init
    git config user.email "test@buildcrew.test"
    git config user.name "Test"
    git commit --allow-empty -m "init"
    ORIGINAL_BRANCH="main"

    run create_task_branch "Test task"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Created branch"* ]]

    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    [ "$current_branch" = "buildcrew/test-task" ]
}

@test "create_task_branch: recreates existing branch" {
    git init
    git config user.email "test@buildcrew.test"
    git config user.name "Test"
    git commit --allow-empty -m "init"
    ORIGINAL_BRANCH="main"
    git checkout -b "buildcrew/test-task"
    git checkout main

    run create_task_branch "Test task"
    [ "$status" -eq 0 ]
    [[ "$output" == *"exists from a previous run"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Lockfile tests
# ─────────────────────────────────────────────────────────────────────────────

@test "cleanup: removes lockfile" {
    mkdir -p .buildcrew
    echo "12345" > "$LOCKFILE"
    cleanup
    [ ! -f "$LOCKFILE" ]
}

@test "cleanup: handles missing lockfile gracefully" {
    run cleanup
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Global invocation ceiling tests
# ─────────────────────────────────────────────────────────────────────────────

@test "MAX_INVOCATIONS: defaults to 15" {
    [ "$MAX_INVOCATIONS" -eq 15 ]
}

@test "MAX_INVOCATIONS: can be overridden via env var" {
    MAX_INVOCATIONS=25
    [ "$MAX_INVOCATIONS" -eq 25 ]
}

@test "__INVOCATION_COUNT: starts at 0 after sourcing" {
    [ "$__INVOCATION_COUNT" -eq 0 ]
}

@test "run_phase_group: returns 1 when invocation ceiling reached" {
    __INVOCATION_COUNT=15
    MAX_INVOCATIONS=15
    run run_phase_group "build" "test task"
    [ "$status" -eq 1 ]
}

@test "run_phase_group: error message mentions invocation ceiling" {
    __INVOCATION_COUNT=15
    MAX_INVOCATIONS=15
    run run_phase_group "build" "test task"
    [[ "$output" == *"invocation ceiling"* ]]
}

@test "run_phase_group: error message includes count and max" {
    __INVOCATION_COUNT=15
    MAX_INVOCATIONS=15
    run run_phase_group "build" "test task"
    [[ "$output" == *"15/15"* ]]
}

@test "run_phase_group: passes ceiling check when under limit" {
    __INVOCATION_COUNT=14
    MAX_INVOCATIONS=15
    # Will fail because there's no real claude command, but should get past
    # the initial ceiling check — the Phase: info line proves it passed
    run run_phase_group "build" "test task"
    [[ "$output" == *"Phase: build"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Task progress tracking tests (--resume)
# ─────────────────────────────────────────────────────────────────────────────

@test "save_task_progress: creates valid JSON file" {
    echo "- [ ] Test task" > BACKLOG.md
    save_task_progress "Test task" "research review" 4
    [ -f "$PROGRESS_FILE" ]
    jq -e . "$PROGRESS_FILE" >/dev/null
}

@test "save_task_progress: stores correct task name" {
    echo "- [ ] Test task" > BACKLOG.md
    save_task_progress "Test task" "research" 2
    local stored_task
    stored_task=$(jq -r '.task' "$PROGRESS_FILE")
    [ "$stored_task" = "Test task" ]
}

@test "save_task_progress: stores completed phases as array" {
    echo "- [ ] Test task" > BACKLOG.md
    save_task_progress "Test task" "research review" 4
    local count
    count=$(jq '.completed_phases | length' "$PROGRESS_FILE")
    [ "$count" -eq 2 ]
    [ "$(jq -r '.completed_phases[0]' "$PROGRESS_FILE")" = "research" ]
    [ "$(jq -r '.completed_phases[1]' "$PROGRESS_FILE")" = "review" ]
}

@test "save_task_progress: stores invocation count" {
    echo "- [ ] Test task" > BACKLOG.md
    save_task_progress "Test task" "research" 7
    local count
    count=$(jq '.invocation_count' "$PROGRESS_FILE")
    [ "$count" -eq 7 ]
}

@test "save_task_progress: stores timestamp" {
    echo "- [ ] Test task" > BACKLOG.md
    save_task_progress "Test task" "research" 1
    local ts
    ts=$(jq -r '.timestamp' "$PROGRESS_FILE")
    [ -n "$ts" ]
    [ "$ts" != "null" ]
}

@test "save_task_progress: handles special characters in task name" {
    echo '- [ ] Create `tests/e2e/seed.ts` — a utility (v1.0+) module.' > BACKLOG.md
    save_task_progress 'Create `tests/e2e/seed.ts` — a utility (v1.0+) module.' "research" 1
    jq -e . "$PROGRESS_FILE" >/dev/null
    local stored_task
    stored_task=$(jq -r '.task' "$PROGRESS_FILE")
    [ "$stored_task" = 'Create `tests/e2e/seed.ts` — a utility (v1.0+) module.' ]
}

@test "load_task_progress: returns 1 when no file exists" {
    echo "- [ ] Test task" > BACKLOG.md
    run load_task_progress
    [ "$status" -eq 1 ]
}

@test "load_task_progress: returns 1 with invalid JSON" {
    echo "- [ ] Test task" > BACKLOG.md
    mkdir -p .buildcrew
    echo "not valid json" > "$PROGRESS_FILE"
    run load_task_progress
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid progress file"* ]]
}

@test "load_task_progress: returns 1 when task is empty" {
    echo "- [ ] Test task" > BACKLOG.md
    mkdir -p .buildcrew
    echo '{"task": "", "completed_phases": [], "invocation_count": 0}' > "$PROGRESS_FILE"
    run load_task_progress
    [ "$status" -eq 1 ]
}

@test "load_task_progress: returns 1 when task no longer pending" {
    echo "- [x] Completed task" > BACKLOG.md
    mkdir -p .buildcrew
    echo '{"task": "Completed task", "completed_phases": ["research"], "invocation_count": 2}' > "$PROGRESS_FILE"
    run load_task_progress
    [ "$status" -eq 1 ]
    [[ "$output" == *"no longer pending"* ]]
    # Progress file should be cleared
    [ ! -f "$PROGRESS_FILE" ]
}

@test "load_task_progress: sets globals on success" {
    echo "- [ ] Test task" > BACKLOG.md
    mkdir -p .buildcrew
    echo '{"task": "Test task", "completed_phases": ["research", "review"], "invocation_count": 5, "timestamp": "2024-01-15T10:30:00"}' > "$PROGRESS_FILE"
    load_task_progress
    [ "$__RESUME_TASK" = "Test task" ]
    [ "$__RESUME_PHASES" = "research review" ]
    [ "$__RESUME_INVOCATIONS" -eq 5 ]
}

@test "clear_task_progress: removes progress file" {
    mkdir -p .buildcrew
    echo '{}' > "$PROGRESS_FILE"
    clear_task_progress
    [ ! -f "$PROGRESS_FILE" ]
}

@test "clear_task_progress: succeeds when no file exists" {
    run clear_task_progress
    [ "$status" -eq 0 ]
}

@test "phase_completed: returns 0 for completed phase" {
    __RESUME_PHASES="research review"
    run phase_completed "research"
    [ "$status" -eq 0 ]
}

@test "phase_completed: returns 0 for second completed phase" {
    __RESUME_PHASES="research review"
    run phase_completed "review"
    [ "$status" -eq 0 ]
}

@test "phase_completed: returns 1 for incomplete phase" {
    __RESUME_PHASES="research review"
    run phase_completed "build"
    [ "$status" -eq 1 ]
}

@test "phase_completed: returns 1 when no phases completed" {
    __RESUME_PHASES=""
    run phase_completed "research"
    [ "$status" -eq 1 ]
}

@test "parse_args: --resume sets RESUME_MODE=true" {
    parse_args --resume
    [ "$RESUME_MODE" = "true" ]
}

@test "parse_args: --resume combined with --single" {
    parse_args --resume --single
    [ "$RESUME_MODE" = "true" ]
    [ "$SINGLE_TASK" = "true" ]
}

@test "parse_args: no args leaves RESUME_MODE=false" {
    parse_args
    [ "$RESUME_MODE" = "false" ]
}

@test "parse_args: --help mentions --resume" {
    run parse_args --help
    [[ "$output" == *"--resume"* ]]
}
