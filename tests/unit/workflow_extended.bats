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

@test "parse_args: multiple flags combined" {
    parse_args --dry-run --single --review --branch
    [ "$DRY_RUN" = "true" ]
    [ "$SINGLE_TASK" = "true" ]
    [ "$HUMAN_REVIEW" = "true" ]
    [ "$GIT_BRANCH" = "true" ]
}

@test "parse_args: no args preserves defaults" {
    parse_args
    [ "$DRY_RUN" = "false" ]
    [ "$SINGLE_TASK" = "false" ]
    [ "$HUMAN_REVIEW" = "false" ]
    [ "$GIT_BRANCH" = "false" ]
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
    mkdir -p .claude/skills/buildcrew-codereview
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

@test "handle_human_review: proceeds when --force passed even if HUMAN_REVIEW=false" {
    HUMAN_REVIEW=false
    # Non-interactive terminal, so it will hit the fallback path
    run handle_human_review "task" "description" "artifact" "--force"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Non-interactive terminal"* ]]
}

@test "handle_human_review: --force with HUMAN_REVIEW=true still reaches non-interactive check" {
    HUMAN_REVIEW=true
    run handle_human_review "task" "description" "artifact" "--force"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Non-interactive terminal"* ]]
}

@test "handle_human_review: returns 0 without --force when HUMAN_REVIEW=false (4-arg call)" {
    HUMAN_REVIEW=false
    run handle_human_review "task" "description" "artifact" ""
    [ "$status" -eq 0 ]
    # Should early-return without hitting the non-interactive check
    [[ "$output" != *"Non-interactive terminal"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# handle_spec_review early-return path tests
# ─────────────────────────────────────────────────────────────────────────────

@test "handle_spec_review: returns 0 with warning when non-interactive" {
    run handle_spec_review "my task" "3"
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

@test "parse_args: --task sets TARGET_TASK" {
    parse_args --task "Build auth system"
    [ "$TARGET_TASK" = "Build auth system" ]
}

@test "parse_args: --task with number sets TARGET_TASK" {
    parse_args --task 3
    [ "$TARGET_TASK" = "3" ]
}

@test "parse_args: --task without value exits 1" {
    run parse_args --task
    [ "$status" -eq 1 ]
}

@test "parse_args: --task combined with other flags" {
    parse_args --task "my task" --dry-run
    [ "$TARGET_TASK" = "my task" ]
    [ "$DRY_RUN" = "true" ]
}

@test "parse_args: no args leaves TARGET_TASK empty" {
    parse_args
    [ "$TARGET_TASK" = "" ]
}

@test "parse_args: --help mentions --task" {
    run parse_args --help
    [[ "$output" == *"--task"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# task_to_slug tests
# ─────────────────────────────────────────────────────────────────────────────

@test "task_to_slug: lowercases input" {
    run task_to_slug "Fix The BUG"
    [ "$output" = "fix-the-bug" ]
}

@test "task_to_slug: replaces non-alphanumeric with hyphens" {
    run task_to_slug "fix: bug in /api/users"
    [ "$output" = "fix-bug-in-api-users" ]
}

@test "task_to_slug: collapses multiple hyphens" {
    run task_to_slug "fix   multiple   spaces"
    [ "$output" = "fix-multiple-spaces" ]
}

@test "task_to_slug: trims leading and trailing hyphens" {
    run task_to_slug "---hello world---"
    [ "$output" = "hello-world" ]
}

@test "task_to_slug: truncates to 60 chars" {
    local long_task="this is a very long task name that should definitely be truncated because it exceeds sixty characters"
    run task_to_slug "$long_task"
    [ "${#output}" -le 60 ]
}

@test "task_to_slug: handles backticks and parentheses" {
    run task_to_slug "Create \`tests/e2e/seed.ts\` — a utility (v1.0+) module"
    [ "$output" = "create-tests-e2e-seed-ts-a-utility-v1-0-module" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# archive_task_artifacts tests
# ─────────────────────────────────────────────────────────────────────────────

@test "archive_task_artifacts: no-op when no artifacts exist" {
    run archive_task_artifacts
    [ "$status" -eq 0 ]
    [ ! -d ".buildcrew/history" ]
}

@test "archive_task_artifacts: archives existing artifacts" {
    mkdir -p .claude .buildcrew
    echo "# Research" > .claude/research.md
    echo "# Plan" > .claude/current-plan.md
    echo "Task A" > "$CURRENT_TASK_FILE"

    archive_task_artifacts

    # Should have created archive directory
    local archive_dir
    archive_dir=$(find .buildcrew/history/task-a -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
    [ -n "$archive_dir" ]
    [ -f "$archive_dir/research.md" ]
    [ -f "$archive_dir/current-plan.md" ]
}

@test "archive_task_artifacts: uses 'unknown' slug when no current-task file" {
    mkdir -p .claude
    echo "# Research" > .claude/research.md

    archive_task_artifacts

    local archive_dir
    archive_dir=$(find .buildcrew/history/unknown -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
    [ -n "$archive_dir" ]
    [ -f "$archive_dir/research.md" ]
}

@test "archive_task_artifacts: only copies files that exist" {
    mkdir -p .claude .buildcrew
    echo "# Plan" > .claude/current-plan.md
    echo "Task B" > "$CURRENT_TASK_FILE"

    archive_task_artifacts

    local archive_dir
    archive_dir=$(find .buildcrew/history/task-b -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
    [ -n "$archive_dir" ]
    [ -f "$archive_dir/current-plan.md" ]
    [ ! -f "$archive_dir/research.md" ]
}

@test "archive_task_artifacts: prints info message" {
    mkdir -p .claude .buildcrew
    echo "# Research" > .claude/research.md
    echo "Task C" > "$CURRENT_TASK_FILE"

    run archive_task_artifacts
    [[ "$output" == *"Archived artifacts to"* ]]
}

@test "archive_task_artifacts: archives phase-result and status files" {
    mkdir -p .claude .buildcrew
    echo '{"verdict": "blocked"}' > "$PHASE_RESULT_FILE"
    echo '{"status": "blocked"}' > "$STATUS_FILE"
    echo "Task D" > "$CURRENT_TASK_FILE"

    archive_task_artifacts

    local archive_dir
    archive_dir=$(find .buildcrew/history/task-d -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
    [ -n "$archive_dir" ]
    [ -f "$archive_dir/phase-result.json" ]
    [ -f "$archive_dir/workflow-status.json" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# New phase turns (spec, outcome, codereview)
# ─────────────────────────────────────────────────────────────────────────────

@test "get_phase_max_turns: spec returns 50" {
    run get_phase_max_turns "spec"
    [ "$output" = "50" ]
}

@test "get_phase_max_turns: outcome returns 40" {
    run get_phase_max_turns "outcome"
    [ "$output" = "40" ]
}

@test "get_phase_max_turns: codereview returns 40" {
    run get_phase_max_turns "codereview"
    [ "$output" = "40" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# New flags: --skip-spec and --strict
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --skip-spec sets SKIP_SPEC=true" {
    parse_args --skip-spec
    [ "$SKIP_SPEC" = "true" ]
}

@test "parse_args: --strict sets STRICT_MODE=true" {
    parse_args --strict
    [ "$STRICT_MODE" = "true" ]
}

@test "parse_args: no args leaves SKIP_SPEC=false" {
    parse_args
    [ "$SKIP_SPEC" = "false" ]
}

@test "parse_args: no args leaves STRICT_MODE=true (strict by default)" {
    parse_args
    [ "$STRICT_MODE" = "true" ]
}

@test "parse_args: --skip-spec combined with other flags" {
    parse_args --skip-spec --strict --dry-run
    [ "$SKIP_SPEC" = "true" ]
    [ "$STRICT_MODE" = "true" ]
    [ "$DRY_RUN" = "true" ]
}

@test "parse_args: --no-strict sets STRICT_MODE=false" {
    parse_args --no-strict
    [ "$STRICT_MODE" = "false" ]
}

@test "parse_args: --no-strict sets STRICT_EXPLICIT=true" {
    parse_args --no-strict
    [ "$STRICT_EXPLICIT" = "true" ]
}

@test "parse_args: --strict sets STRICT_EXPLICIT=true" {
    parse_args --strict
    [ "$STRICT_EXPLICIT" = "true" ]
}

@test "parse_args: no args leaves STRICT_EXPLICIT=false" {
    parse_args
    [ "$STRICT_EXPLICIT" = "false" ]
}

@test "parse_args: --strict --no-strict last wins (STRICT_MODE=false, STRICT_EXPLICIT=true)" {
    parse_args --strict --no-strict
    [ "$STRICT_MODE" = "false" ]
    [ "$STRICT_EXPLICIT" = "true" ]
}

@test "parse_args: --no-strict --strict last wins (STRICT_MODE=true, STRICT_EXPLICIT=true)" {
    parse_args --no-strict --strict
    [ "$STRICT_MODE" = "true" ]
    [ "$STRICT_EXPLICIT" = "true" ]
}

@test "parse_args: --help mentions --skip-spec" {
    run parse_args --help
    [[ "$output" == *"--skip-spec"* ]]
}

@test "parse_args: --help mentions --strict" {
    run parse_args --help
    [[ "$output" == *"--strict"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Lessons system (append_lesson, LESSONS_FILE)
# ─────────────────────────────────────────────────────────────────────────────

@test "append_lesson: creates lessons file when none exists" {
    mkdir -p .buildcrew
    append_lesson "review" "plan failed" "re-planned" "always validate approach before review"
    [ -f "$LESSONS_FILE" ]
}

@test "append_lesson: creates valid markdown lesson entry" {
    mkdir -p .buildcrew
    append_lesson "build" "syntax error" "fixed typo" "run syntax check before committing"
    grep -q "## Lesson 1:" "$LESSONS_FILE"
    grep -qF "**Phase**: build" "$LESSONS_FILE"
    grep -qF "**Rule**: run syntax check before committing" "$LESSONS_FILE"
}

@test "append_lesson: increments lesson number on second call" {
    mkdir -p .buildcrew
    append_lesson "build" "error one" "fix one" "rule one"
    append_lesson "test" "error two" "fix two" "rule two"
    grep -q "## Lesson 1:" "$LESSONS_FILE"
    grep -q "## Lesson 2:" "$LESSONS_FILE"
}

@test "append_lesson: prints info message" {
    mkdir -p .buildcrew
    run append_lesson "verify" "test failure" "fixed test" "write better tests"
    [[ "$output" == *"Lesson recorded"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# _summarize_old_lessons regression (Fix 1)
# ─────────────────────────────────────────────────────────────────────────────

@test "_summarize_old_lessons: preserves existing Patterns bullet rules on second summarization" {
    mkdir -p .buildcrew
    LESSONS_SUMMARIZE_COUNT=2

    # Seed a lessons file with an existing Patterns section plus 3 lesson entries.
    # total_lessons=3 > LESSONS_SUMMARIZE_COUNT=2, so summarization will run.
    cat > "$LESSONS_FILE" << 'EOF'
# Lessons

## Patterns (condensed from oldest 2 lessons)

*The following patterns were extracted from the first 2 lessons:*

- existing preserved pattern

---

## Lesson 3: 2024-01-01

**Phase**: build
**Observation**: error three
**Action**: fix three
**Rule**: rule three

---

## Lesson 4: 2024-01-01

**Phase**: build
**Observation**: error four
**Action**: fix four
**Rule**: rule four

---

## Lesson 5: 2024-01-01

**Phase**: build
**Observation**: error five
**Action**: fix five
**Rule**: rule five

---
EOF

    _summarize_old_lessons

    # Preserved bullet rule from prior condensation cycle must still be present
    grep -q "existing preserved pattern" "$LESSONS_FILE"
    # Rules from lessons 3 and 4 appear as bullets in the new Patterns section
    grep -q "rule three" "$LESSONS_FILE"
    grep -q "rule four" "$LESSONS_FILE"
    # Lesson 5 remains as an active lesson entry
    grep -q "^## Lesson 5:" "$LESSONS_FILE"
    # Lessons 3 and 4 no longer appear as standalone lesson headers
    ! grep -q "^## Lesson 3:" "$LESSONS_FILE"
    ! grep -q "^## Lesson 4:" "$LESSONS_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Circuit breaker integration (Fix coverage items 2 & 3)
# Decision: bats function-override approach — process_task_isolated is too
# entangled to extract a testable helper without invasive refactoring.
# ─────────────────────────────────────────────────────────────────────────────

@test "circuit breaker: marks task blocked after two consecutive build failures and re-plan" {
    mkdir -p .buildcrew .claude
    echo "- [ ] test task" > BACKLOG.md
    SKIP_SPEC=true
    STRICT_MODE=false
    HUMAN_REVIEW=false
    # Pre-mark research and review as completed so they're skipped via phase_completed
    __RESUME_PHASES="research review"

    # Temp file persists across the subshell created by bats `run`
    local blocked_file
    blocked_file=$(mktemp)

    archive_task_artifacts() { :; }
    clear_task_progress()    { :; }
    save_task_progress()     { :; }
    append_lesson()          { :; }
    handle_human_review()    { return 0; }
    mark_task_blocked()      { echo "$*" > "$blocked_file"; }
    # Always fail: both build and test return needs_rebuild
    run_phase_group() {
        mkdir -p .claude
        echo '{"verdict":"needs_rebuild","details":"stub failure"}' > "$PHASE_RESULT_FILE"
        return 0
    }

    run process_task_isolated "test task"
    [ "$status" -eq 1 ]
    [ -s "$blocked_file" ]
    rm -f "$blocked_file"
}

@test "AC count resume: spec with 1 AC triggers re-run" {
    mkdir -p .buildcrew ".claude/skills/buildcrew-spec"
    printf '# Spec\n- [ ] AC-01: only one criterion\n' > .claude/spec.md
    echo "- [ ] test task" > BACKLOG.md
    SKIP_SPEC=false
    STRICT_MODE=true
    HUMAN_REVIEW=false
    # Simulate a resume — RESUME_MODE=true causes process_task_isolated to take
    # the resume path, which skips the artifact cleanup (so spec.md is preserved).
    # load_task_progress is mocked to inject __RESUME_PHASES directly.
    RESUME_MODE=true

    local spec_rerun_file
    spec_rerun_file=$(mktemp)

    archive_task_artifacts() { :; }
    clear_task_progress()    { :; }
    save_task_progress()     { :; }
    append_lesson()          { :; }
    handle_human_review()    { return 0; }
    handle_spec_review()     { return 0; }  # required: spec re-run calls this
    mark_task_blocked()      { :; }
    # Mock load_task_progress: inject resume state with spec+downstream complete
    load_task_progress() {
        __RESUME_TASK="test task"
        __RESUME_PHASES="spec research review build"
        __RESUME_INVOCATIONS=0
        return 0
    }
    run_phase_group() {
        local phase="$1"
        mkdir -p .claude
        if [[ "$phase" == "spec" ]]; then
            echo "spec" >> "$spec_rerun_file"
            # Write a spec with 2 ACs so the retry passes
            printf '# Spec\n- [ ] AC-01: first\n- [ ] AC-02: second\n' > .claude/spec.md
        fi
        echo '{"verdict":"complete","details":"stub"}' > "$PHASE_RESULT_FILE"
        return 0
    }

    run process_task_isolated "test task"
    # spec must have been re-run
    [ -s "$spec_rerun_file" ]
    # the spec on disk after re-run must satisfy the 2-AC minimum (the mock writes 2 ACs)
    local ac_count_after
    ac_count_after=$(grep -c '^- \[ \] AC-' .claude/spec.md 2>/dev/null || echo 0)
    [ "$ac_count_after" -ge 2 ]
    rm -f "$spec_rerun_file"
}

@test "outcome strict mode: marks task blocked after two consecutive partial failures" {
    mkdir -p .buildcrew ".claude/skills/buildcrew-outcome"
    echo "# Spec" > .claude/spec.md
    echo "- [ ] test task" > BACKLOG.md
    SKIP_SPEC=false
    STRICT_MODE=true
    HUMAN_REVIEW=false
    # Skip research, review, and build — go directly to the outcome phase
    __RESUME_PHASES="research review build"

    local blocked_file
    blocked_file=$(mktemp)

    archive_task_artifacts() { :; }
    clear_task_progress()    { :; }
    save_task_progress()     { :; }
    append_lesson()          { :; }
    handle_human_review()    { return 0; }
    mark_task_blocked()      { echo "$*" > "$blocked_file"; }
    # Outcome always returns partial; rebuild calls (build/test) return approved
    run_phase_group() {
        local phase="$1"
        mkdir -p .claude
        case "$phase" in
            outcome)
                echo '{"verdict":"partial","details":"stub partial"}' > "$PHASE_RESULT_FILE" ;;
            *)
                echo '{"verdict":"approved","details":"stub approved"}' > "$PHASE_RESULT_FILE" ;;
        esac
        return 0
    }

    run process_task_isolated "test task"
    [ "$status" -eq 1 ]
    [ -s "$blocked_file" ]
    rm -f "$blocked_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# cmd_lessons prune: non-interactive terminal (Fix coverage item 4)
# ─────────────────────────────────────────────────────────────────────────────

@test "cmd_lessons prune: exits 1 and prints warning in non-interactive terminal" {
    mkdir -p .buildcrew
    # Lessons file must exist to reach the TTY check
    echo "## Lesson 1: 2024-01-01" > .buildcrew/lessons.md

    run "$BUILDCREW_ROOT/bin/buildcrew" lessons prune < /dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Non-interactive terminal"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# --max-invocations CLI flag tests
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --max-invocations flag sets MAX_INVOCATIONS" {
    parse_args --max-invocations 25
    [ "$MAX_INVOCATIONS" -eq 25 ]
}

@test "parse_args: --max-invocations overrides env var" {
    MAX_INVOCATIONS=10
    parse_args --max-invocations 25
    [ "$MAX_INVOCATIONS" -eq 25 ]
}

@test "parse_args: --max-invocations without value exits with error" {
    run parse_args --max-invocations
    [ "$status" -ne 0 ]
}

@test "parse_args: --max-invocations with non-numeric value exits with error" {
    run parse_args --max-invocations abc
    [ "$status" -ne 0 ]
}

@test "parse_args: --max-invocations 0 exits with error" {
    run parse_args --max-invocations 0
    [ "$status" -ne 0 ]
}

@test "parse_args: --max-invocations with leading zeros exits with error" {
    run parse_args --max-invocations 007
    [ "$status" -ne 0 ]
}

@test "parse_args: --help mentions --max-invocations" {
    run parse_args --help
    [[ "$output" == *"--max-invocations"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# load_buildcrew_config tests
# ─────────────────────────────────────────────────────────────────────────────

@test "load_buildcrew_config: sets MAX_INVOCATIONS from config file" {
    unset MAX_INVOCATIONS
    mkdir -p .buildcrew
    echo "MAX_INVOCATIONS=20" > .buildcrew/config
    load_buildcrew_config
    [ "$MAX_INVOCATIONS" -eq 20 ]
}

@test "load_buildcrew_config: env var takes precedence over config file" {
    mkdir -p .buildcrew
    echo "MAX_INVOCATIONS=20" > .buildcrew/config
    MAX_INVOCATIONS=30
    load_buildcrew_config
    [ "$MAX_INVOCATIONS" -eq 30 ]
}

@test "load_buildcrew_config: ignores comments and blank lines" {
    unset MAX_INVOCATIONS
    mkdir -p .buildcrew
    printf '# This is a comment\n\nMAX_INVOCATIONS=20\n' > .buildcrew/config
    load_buildcrew_config
    [ "$MAX_INVOCATIONS" -eq 20 ]
}

@test "load_buildcrew_config: no-op when config file missing" {
    run load_buildcrew_config
    [ "$status" -eq 0 ]
}

@test "load_buildcrew_config: ignores unknown keys" {
    mkdir -p .buildcrew
    echo "UNKNOWN_KEY=foo" > .buildcrew/config
    run load_buildcrew_config
    [ "$status" -eq 0 ]
}

@test "load_buildcrew_config: rejects invalid value with warning" {
    unset MAX_INVOCATIONS
    mkdir -p .buildcrew
    echo "MAX_INVOCATIONS=0" > .buildcrew/config
    load_buildcrew_config 2>/dev/null
    [ -z "${MAX_INVOCATIONS:-}" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# --verbose / --debug flag tests
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --verbose sets VERBOSE=true" {
    parse_args --verbose
    [ "$VERBOSE" = "true" ]
}

@test "parse_args: --debug sets VERBOSE=true" {
    parse_args --debug
    [ "$VERBOSE" = "true" ]
}

@test "parse_args: no args leaves VERBOSE=false" {
    parse_args
    [ "$VERBOSE" = "false" ]
}

@test "parse_args: --verbose combined with other flags" {
    parse_args --verbose --dry-run --single
    [ "$VERBOSE" = "true" ]
    [ "$DRY_RUN" = "true" ]
    [ "$SINGLE_TASK" = "true" ]
}

@test "parse_args: --help mentions --verbose" {
    run parse_args --help
    [[ "$output" == *"--verbose"* ]]
}

@test "parse_args: --help mentions --debug" {
    run parse_args --help
    [[ "$output" == *"--debug"* ]]
}

@test "print_debug outputs when VERBOSE=true" {
    VERBOSE=true
    run print_debug "hello from debug"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[debug]"* ]]
    [[ "$output" == *"hello from debug"* ]]
}

@test "print_debug is silent when VERBOSE=false" {
    VERBOSE=false
    run print_debug "should not appear"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "guarded print_debug skips expensive evaluation when VERBOSE=false" {
    VERBOSE=false
    local marker_file
    marker_file=$(mktemp)
    rm -f "$marker_file"
    # Wrap in if/then/fi so the subshell is not entered when VERBOSE=false
    if [[ "$VERBOSE" == "true" ]]; then
        print_debug "result=$(touch "$marker_file"; echo evaluated)"
    fi
    [ ! -f "$marker_file" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase group failure: marks task blocked (prevents infinite loop in main)
# ─────────────────────────────────────────────────────────────────────────────

@test "phase group failure: marks task blocked when spec phase produces no result" {
    mkdir -p .buildcrew ".claude/skills/buildcrew-spec"
    echo "- [ ] test task" > BACKLOG.md
    SKIP_SPEC=false
    STRICT_MODE=false
    HUMAN_REVIEW=false
    __RESUME_PHASES=""

    local blocked_file
    blocked_file=$(mktemp)

    archive_task_artifacts() { :; }
    clear_task_progress()    { :; }
    save_task_progress()     { :; }
    append_lesson()          { :; }
    handle_human_review()    { return 0; }
    handle_spec_review()     { return 0; }
    mark_task_blocked()      { echo "$*" > "$blocked_file"; }
    run_phase_group()        { return 1; }

    run process_task_isolated "test task"
    [ "$status" -eq 1 ]
    [ -s "$blocked_file" ]
    grep -q "spec" "$blocked_file"
    rm -f "$blocked_file"
}

@test "phase group failure: marks task blocked when research phase produces no result" {
    mkdir -p .buildcrew
    echo "- [ ] test task" > BACKLOG.md
    SKIP_SPEC=true
    STRICT_MODE=false
    HUMAN_REVIEW=false
    __RESUME_PHASES=""

    local blocked_file
    blocked_file=$(mktemp)

    archive_task_artifacts() { :; }
    clear_task_progress()    { :; }
    save_task_progress()     { :; }
    append_lesson()          { :; }
    handle_human_review()    { return 0; }
    mark_task_blocked()      { echo "$*" > "$blocked_file"; }
    run_phase_group()        { return 1; }

    run process_task_isolated "test task"
    [ "$status" -eq 1 ]
    [ -s "$blocked_file" ]
    grep -q "research" "$blocked_file"
    rm -f "$blocked_file"
}

@test "phase group failure: marks task blocked when review phase produces no result" {
    mkdir -p .buildcrew
    echo "- [ ] test task" > BACKLOG.md
    SKIP_SPEC=true
    STRICT_MODE=false
    HUMAN_REVIEW=false
    __RESUME_PHASES="research"

    local blocked_file
    blocked_file=$(mktemp)

    archive_task_artifacts() { :; }
    clear_task_progress()    { :; }
    save_task_progress()     { :; }
    append_lesson()          { :; }
    handle_human_review()    { return 0; }
    mark_task_blocked()      { echo "$*" > "$blocked_file"; }
    run_phase_group()        { return 1; }

    run process_task_isolated "test task"
    [ "$status" -eq 1 ]
    [ -s "$blocked_file" ]
    grep -q "review" "$blocked_file"
    rm -f "$blocked_file"
}
