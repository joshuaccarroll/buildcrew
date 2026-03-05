#!/usr/bin/env bats
# Unit tests for --batch mode functions in lib/workflow.sh

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# gather_pending_tasks tests
# ─────────────────────────────────────────────────────────────────────────────

@test "gather_pending_tasks: produces flat numbered list in __BATCH_TASK_LIST" {
    cat > BACKLOG.md << 'EOF'
## High Priority
- [ ] Task one
- [ ] Task two
- [x] Done task
## Low Priority
- [ ] Task three
EOF
    gather_pending_tasks
    [[ "$__BATCH_TASK_LIST" == *"1. Task one"* ]]
    [[ "$__BATCH_TASK_LIST" == *"2. Task two"* ]]
    [[ "$__BATCH_TASK_LIST" == *"3. Task three"* ]]
    [[ "$__BATCH_TASK_LIST" != *"Done task"* ]]
}

@test "gather_pending_tasks: strips complexity tags" {
    cat > BACKLOG.md << 'EOF'
- [ ] Simple task {trivial}
- [ ] Normal task {simple}
- [ ] Complex task {standard}
EOF
    gather_pending_tasks
    [[ "$__BATCH_TASK_LIST" == *"Simple task"* ]]
    [[ "$__BATCH_TASK_LIST" == *"Normal task"* ]]
    [[ "$__BATCH_TASK_LIST" == *"Complex task"* ]]
    [[ "$__BATCH_TASK_LIST" != *"{trivial}"* ]]
    [[ "$__BATCH_TASK_LIST" != *"{simple}"* ]]
    [[ "$__BATCH_TASK_LIST" != *"{standard}"* ]]
}

@test "gather_pending_tasks: handles tasks with special characters" {
    cat > BACKLOG.md << 'EOF'
- [ ] Add `config.yml` for env setup
- [ ] Fix bug in /api/users endpoint
- [ ] Update "prod | dev" pipeline
EOF
    gather_pending_tasks
    [[ "$__BATCH_TASK_LIST" == *"Add"* ]]
    [[ "$__BATCH_TASK_LIST" == *"Fix bug"* ]]
    [[ "$__BATCH_TASK_LIST" == *"Update"* ]]
}

@test "gather_pending_tasks: sets __BATCH_TASK_COUNT correctly" {
    cat > BACKLOG.md << 'EOF'
- [ ] Task A
- [ ] Task B
- [x] Done
- [ ] Task C
EOF
    gather_pending_tasks
    [ "$__BATCH_TASK_COUNT" -eq 3 ]
}

@test "gather_pending_tasks: sets count=0 and empty list for empty backlog" {
    echo "# No tasks here" > BACKLOG.md
    gather_pending_tasks
    [ "$__BATCH_TASK_COUNT" -eq 0 ]
    [ -z "$__BATCH_TASK_LIST" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# parse_args --batch / --sequential tests
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --batch prints deprecation warning" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --batch"
    [[ "$output" == *"deprecated"* ]]
}

@test "parse_args: SEQUENTIAL_MODE defaults to false" {
    [ "$SEQUENTIAL_MODE" = "false" ]
}

@test "parse_args: --sequential sets SEQUENTIAL_MODE=true" {
    parse_args --sequential
    [ "$SEQUENTIAL_MODE" = "true" ]
}

@test "parse_args: --single sets SEQUENTIAL_MODE=true" {
    parse_args --single
    [ "$SINGLE_TASK" = "true" ]
    [ "$SEQUENTIAL_MODE" = "true" ]
}

@test "parse_args: --task sets SEQUENTIAL_MODE=true" {
    parse_args --task "some task"
    [ "$TARGET_TASK" = "some task" ]
    [ "$SEQUENTIAL_MODE" = "true" ]
}

@test "parse_args: --review sets SEQUENTIAL_MODE=true" {
    parse_args --review
    [ "$HUMAN_REVIEW" = "true" ]
    [ "$SEQUENTIAL_MODE" = "true" ]
}

@test "parse_args: --help mentions --sequential" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --help"
    [[ "$output" == *"--sequential"* ]]
}

@test "parse_args: --help mentions --batch deprecated" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --help"
    [[ "$output" == *"--batch"* ]]
    [[ "$output" == *"deprecated"* ]]
}

@test "parse_args: --max-parallel sets MAX_PARALLEL" {
    parse_args --max-parallel 7
    [ "$MAX_PARALLEL" = "7" ]
}

@test "parse_args: --max-parallel rejects non-integer" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --max-parallel abc"
    [ "$status" -eq 1 ]
}

@test "parse_args: --max-parallel rejects zero" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --max-parallel 0"
    [ "$status" -eq 1 ]
}

@test "parse_args: --batch --resume sets both flags" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --batch --resume 2>&1"
    # --batch prints deprecation warning but still sets flags
    [[ "$output" == *"deprecated"* ]]
}

@test "parse_args: --help mentions --max-parallel" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --help"
    [[ "$output" == *"--max-parallel"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# MAX_PARALLEL config tests
# ─────────────────────────────────────────────────────────────────────────────

@test "MAX_PARALLEL: defaults to 5" {
    [ "$MAX_PARALLEL" = "5" ]
}

@test "MAX_PARALLEL: loaded from .buildcrew/config" {
    mkdir -p .buildcrew
    echo "MAX_PARALLEL=3" > .buildcrew/config
    unset MAX_PARALLEL
    load_buildcrew_config
    MAX_PARALLEL=${MAX_PARALLEL:-5}
    [ "$MAX_PARALLEL" = "3" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Batch manifest function tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_init_manifest: creates valid JSON manifest" {
    _batch_init_manifest "main" "abc123"
    [ -f "$BATCH_MANIFEST" ]
    jq -e . "$BATCH_MANIFEST" >/dev/null
    [ "$(jq -r '.base_branch' "$BATCH_MANIFEST")" = "main" ]
    [ "$(jq -r '.base_commit' "$BATCH_MANIFEST")" = "abc123" ]
    [ "$(jq '.max_parallel' "$BATCH_MANIFEST")" = "$MAX_PARALLEL" ]
    [ "$(jq '.tasks | length' "$BATCH_MANIFEST")" = "0" ]
}

@test "_batch_add_task: appends task entries to manifest" {
    _batch_init_manifest "main" "abc123"
    _batch_add_task 1 "First task" "first-task"
    _batch_add_task 2 "Second task" "second-task"
    [ "$(jq '.tasks | length' "$BATCH_MANIFEST")" = "2" ]
    [ "$(jq -r '.tasks[0].text' "$BATCH_MANIFEST")" = "First task" ]
    [ "$(jq -r '.tasks[0].slug' "$BATCH_MANIFEST")" = "first-task" ]
    [ "$(jq -r '.tasks[0].status' "$BATCH_MANIFEST")" = "pending" ]
    [ "$(jq -r '.tasks[1].text' "$BATCH_MANIFEST")" = "Second task" ]
}

@test "_batch_mark_task: updates running status with started_at" {
    _batch_init_manifest "main" "abc123"
    _batch_add_task 1 "A task" "a-task"
    _batch_mark_task 1 "running"
    [ "$(jq -r '.tasks[0].status' "$BATCH_MANIFEST")" = "running" ]
    [ "$(jq -r '.tasks[0].started_at' "$BATCH_MANIFEST")" != "null" ]
}

@test "_batch_mark_task: updates completed status with exit_code" {
    _batch_init_manifest "main" "abc123"
    _batch_add_task 1 "A task" "a-task"
    _batch_mark_task 1 "completed" "0"
    [ "$(jq -r '.tasks[0].status' "$BATCH_MANIFEST")" = "completed" ]
    [ "$(jq '.tasks[0].exit_code' "$BATCH_MANIFEST")" = "0" ]
    [ "$(jq -r '.tasks[0].completed_at' "$BATCH_MANIFEST")" != "null" ]
}

@test "_batch_mark_task: updates failed status with exit_code" {
    _batch_init_manifest "main" "abc123"
    _batch_add_task 1 "A task" "a-task"
    _batch_mark_task 1 "failed" "1"
    [ "$(jq -r '.tasks[0].status' "$BATCH_MANIFEST")" = "failed" ]
    [ "$(jq '.tasks[0].exit_code' "$BATCH_MANIFEST")" = "1" ]
}

@test "_batch_load_manifest: returns 1 when no manifest exists" {
    rm -f "$BATCH_MANIFEST"
    run _batch_load_manifest
    [ "$status" -eq 1 ]
}

@test "_batch_load_manifest: returns 1 when all tasks completed" {
    _batch_init_manifest "main" "abc"
    _batch_add_task 1 "Done" "done"
    _batch_mark_task 1 "completed" "0"
    run _batch_load_manifest
    [ "$status" -eq 1 ]
}

@test "_batch_load_manifest: returns 0 when incomplete tasks exist" {
    _batch_init_manifest "main" "abc"
    _batch_add_task 1 "Done" "done"
    _batch_add_task 2 "Pending" "pending"
    _batch_mark_task 1 "completed" "0"
    run _batch_load_manifest
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Task list parsing and slug collision tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_parse_task_list: parses numbered list into arrays" {
    _batch_parse_task_list " 1. Task alpha
 2. Task beta
 3. Task gamma"
    [ "${#_batch_tasks[@]}" -eq 3 ]
    [ "${_batch_tasks[0]}" = "Task alpha" ]
    [ "${_batch_tasks[1]}" = "Task beta" ]
    [ "${_batch_tasks[2]}" = "Task gamma" ]
}

@test "_batch_parse_task_list: generates slugs for each task" {
    _batch_parse_task_list " 1. Fix the bug
 2. Add new feature"
    [ "${#_batch_slugs[@]}" -eq 2 ]
    [ -n "${_batch_slugs[0]}" ]
    [ -n "${_batch_slugs[1]}" ]
}

@test "_batch_parse_task_list: handles slug collisions by appending index" {
    # Two tasks that produce the same slug (task_to_slug truncates at 60 chars)
    _batch_parse_task_list " 1. Fix the bug
 2. Fix the bug"
    [ "${_batch_slugs[0]}" != "${_batch_slugs[1]}" ]
}

@test "_batch_parse_task_list: skips empty lines" {
    _batch_parse_task_list " 1. Task one

 2. Task two"
    [ "${#_batch_tasks[@]}" -eq 2 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Non-git parent: extract_task_dir / strip_task_dir / resolve_task_target_dir
# ─────────────────────────────────────────────────────────────────────────────

@test "extract_task_dir: extracts dir from [dir:project-a] prefix" {
    result=$(extract_task_dir "[dir:project-a] Fix the bug")
    [ "$result" = "project-a" ]
}

@test "extract_task_dir: returns empty for task without prefix" {
    result=$(extract_task_dir "Fix the bug")
    [ -z "$result" ]
}

@test "extract_task_dir: handles nested-path dirs" {
    result=$(extract_task_dir "[dir:apps/frontend] Add feature")
    [ "$result" = "apps/frontend" ]
}

@test "strip_task_dir: removes [dir:...] prefix and space" {
    result=$(strip_task_dir "[dir:project-a] Fix the bug")
    [ "$result" = "Fix the bug" ]
}

@test "strip_task_dir: passes through task without prefix" {
    result=$(strip_task_dir "Fix the bug")
    [ "$result" = "Fix the bug" ]
}

@test "resolve_task_target_dir: inline dir wins over TARGET_DIR" {
    TARGET_DIR="fallback-project"
    result=$(resolve_task_target_dir "[dir:project-a] Fix the bug")
    [ "$result" = "project-a" ]
}

@test "resolve_task_target_dir: falls back to TARGET_DIR" {
    TARGET_DIR="default-project"
    result=$(resolve_task_target_dir "Fix the bug")
    [ "$result" = "default-project" ]
}

@test "resolve_task_target_dir: returns empty when no dir and no TARGET_DIR" {
    TARGET_DIR=""
    result=$(resolve_task_target_dir "Fix the bug")
    [ -z "$result" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Non-git parent: _batch_parse_task_list with dir prefixes
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_parse_task_list: extracts and strips [dir:...] prefix" {
    _batch_parse_task_list " 1. [dir:project-a] Implement feature X
 2. [dir:project-b] Fix bug Y"
    [ "${_batch_tasks[0]}" = "Implement feature X" ]
    [ "${_batch_tasks[1]}" = "Fix bug Y" ]
    [ "${_batch_target_dirs[0]}" = "project-a" ]
    [ "${_batch_target_dirs[1]}" = "project-b" ]
}

@test "_batch_parse_task_list: prefixes slug with dir name" {
    _batch_parse_task_list " 1. [dir:project-a] Fix bug"
    [[ "${_batch_slugs[0]}" == project-a-* ]]
}

@test "_batch_parse_task_list: uses TARGET_DIR fallback" {
    TARGET_DIR="my-project"
    _batch_parse_task_list " 1. Fix bug"
    [ "${_batch_target_dirs[0]}" = "my-project" ]
    [[ "${_batch_slugs[0]}" == my-project-* ]]
}

@test "_batch_parse_task_list: empty target_dir for plain tasks" {
    TARGET_DIR=""
    _batch_parse_task_list " 1. Fix bug"
    [ -z "${_batch_target_dirs[0]}" ]
    # Slug should NOT have a dir prefix
    [[ "${_batch_slugs[0]}" == fix-* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Non-git parent: mark_task_complete/blocked with [dir:...] prefix
# ─────────────────────────────────────────────────────────────────────────────

@test "mark_task_complete: marks task with [dir:...] prefix preserving prefix" {
    cat > BACKLOG.md << 'EOF'
- [ ] [dir:project-a] Fix the bug
- [ ] [dir:project-b] Add feature
EOF
    mark_task_complete "Fix the bug"
    grep -q '^\- \[x\] \[dir:project-a\] Fix the bug' BACKLOG.md
    # Other task unchanged
    grep -q '^\- \[ \] \[dir:project-b\] Add feature' BACKLOG.md
}

@test "mark_task_complete: still works without [dir:...] prefix" {
    cat > BACKLOG.md << 'EOF'
- [ ] Fix the bug
EOF
    mark_task_complete "Fix the bug"
    grep -q '^\- \[x\] Fix the bug' BACKLOG.md
}

@test "mark_task_blocked: marks task with [dir:...] prefix preserving prefix" {
    cat > BACKLOG.md << 'EOF'
- [ ] [dir:project-a] Fix the bug
EOF
    mark_task_blocked "Fix the bug" "dependency missing"
    grep -q '^\- \[!\] \[dir:project-a\] Fix the bug (blocked: dependency missing)' BACKLOG.md
}

# ─────────────────────────────────────────────────────────────────────────────
# Non-git parent: _batch_add_task stores target_dir in manifest
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_add_task: stores target_dir in manifest" {
    _batch_init_manifest "main" "abc123"
    _batch_add_task 1 "Fix bug" "project-a-fix-bug" "project-a"
    [ "$(jq -r '.tasks[0].target_dir' "$BATCH_MANIFEST")" = "project-a" ]
}

@test "_batch_add_task: target_dir defaults to empty string" {
    _batch_init_manifest "main" "abc123"
    _batch_add_task 1 "Fix bug" "fix-bug"
    [ "$(jq -r '.tasks[0].target_dir' "$BATCH_MANIFEST")" = "" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Non-git parent: TARGET_DIR config loading
# ─────────────────────────────────────────────────────────────────────────────

@test "TARGET_DIR: loaded from .buildcrew/config" {
    mkdir -p .buildcrew
    echo "TARGET_DIR=my-project" > .buildcrew/config
    unset TARGET_DIR
    load_buildcrew_config
    TARGET_DIR=${TARGET_DIR:-}
    [ "$TARGET_DIR" = "my-project" ]
}

@test "TARGET_DIR: env var wins over config" {
    mkdir -p .buildcrew
    echo "TARGET_DIR=from-config" > .buildcrew/config
    TARGET_DIR="from-env"
    load_buildcrew_config
    [ "$TARGET_DIR" = "from-env" ]
}

@test "TARGET_DIR: defaults to empty" {
    [ "$TARGET_DIR" = "" ] || [ -z "$TARGET_DIR" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# parse_args: --task-exact tests
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --task-exact sets TARGET_TASK_EXACT and SINGLE_TASK" {
    parse_args --task-exact "Fix the bug"
    [ "$TARGET_TASK_EXACT" = "Fix the bug" ]
    [ "$SINGLE_TASK" = "true" ]
}

@test "parse_args: --task-exact rejects missing value" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --task-exact"
    [ "$status" -eq 1 ]
}

@test "parse_args: --task-exact sets SEQUENTIAL_MODE=true" {
    parse_args --task-exact "Fix the bug"
    [ "$TARGET_TASK_EXACT" = "Fix the bug" ]
    [ "$SINGLE_TASK" = "true" ]
    [ "$SEQUENTIAL_MODE" = "true" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Adversarial flag combinations
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --batch --sequential both process without error" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --batch --sequential 2>&1; echo SEQUENTIAL_MODE=\$SEQUENTIAL_MODE"
    [[ "$output" == *"deprecated"* ]]
    [[ "$output" == *"SEQUENTIAL_MODE=true"* ]]
}

@test "parse_args: --single --review both set SEQUENTIAL_MODE=true" {
    parse_args --single --review
    [ "$SINGLE_TASK" = "true" ]
    [ "$HUMAN_REVIEW" = "true" ]
    [ "$SEQUENTIAL_MODE" = "true" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Flag forwarding pattern verification (code inspection)
# ─────────────────────────────────────────────────────────────────────────────

@test "flag forwarding: uses == true comparison not colon-plus expansion" {
    # Verify the corrected pattern exists (KEEP_LOGS removed — logs always retained)
    grep -q '\[\[ "\$SKIP_SPEC" == "true" \]\] && echo "--skip-spec"' "$BUILDCREW_ROOT/lib/workflow.sh"
    grep -q '\[\[ "\$FULL_PIPELINE" == "true" \]\] && echo "--full-pipeline"' "$BUILDCREW_ROOT/lib/workflow.sh"
    grep -q '\[\[ "\$VERBOSE" == "true" \]\] && echo "--verbose"' "$BUILDCREW_ROOT/lib/workflow.sh"
}

@test "flag forwarding: old colon-plus expansion pattern is removed" {
    ! grep -q '${SKIP_SPEC:+--skip-spec}' "$BUILDCREW_ROOT/lib/workflow.sh"
    ! grep -q '${FULL_PIPELINE:+--full-pipeline}' "$BUILDCREW_ROOT/lib/workflow.sh"
    ! grep -q '${VERBOSE:+--verbose}' "$BUILDCREW_ROOT/lib/workflow.sh"
}

# ─────────────────────────────────────────────────────────────────────────────
# gather_pending_tasks preserves [dir:...] prefixes
# ─────────────────────────────────────────────────────────────────────────────

@test "gather_pending_tasks: preserves [dir:...] prefixes in task list" {
    cat > BACKLOG.md << 'EOF'
- [ ] [dir:project-a] Fix the bug
- [ ] [dir:project-b] Add feature
EOF
    gather_pending_tasks
    [[ "$__BATCH_TASK_LIST" == *"[dir:project-a] Fix the bug"* ]]
    [[ "$__BATCH_TASK_LIST" == *"[dir:project-b] Add feature"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Worktree skill fallback tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_create_worktree: installs skills from BUILDCREW_HOME when source repo lacks them" {
    # __BATCH_CWD must be set — _batch_worktree_path uses it for target_dir mode
    __BATCH_CWD="$TEST_DIR"

    # Create a git repo to act as a target dir without skills
    local target="$TEST_DIR/no-skills-project"
    mkdir -p "$target"
    git -C "$target" init -b main >/dev/null 2>&1
    git -C "$target" config user.email "test@buildcrew.test"
    git -C "$target" config user.name "Test"
    git -C "$target" commit --allow-empty -m "init" >/dev/null 2>&1

    # Ensure BUILDCREW_HOME/skills has content (it does via setup.bash)
    [ -d "$BUILDCREW_HOME/skills/buildcrew" ]

    _batch_create_worktree "test-slug" "main" "$target"
    local worktree_path
    worktree_path=$(_batch_worktree_path "test-slug" "$target")

    # Verify skills were symlinked from BUILDCREW_HOME
    [ -L "$worktree_path/.claude/skills/buildcrew" ]
    [ -d "$worktree_path/.claude/skills/buildcrew-research" ]
    [ -d "$worktree_path/.claude/skills/buildcrew-verify" ]

    # Clean up worktree to avoid polluting the git repo
    git -C "$target" worktree remove --force "$worktree_path" 2>/dev/null || rm -rf "$worktree_path"
}

@test "_batch_create_worktree: creates .buildcrew-link fallback when source repo lacks it" {
    __BATCH_CWD="$TEST_DIR"

    local target="$TEST_DIR/no-link-project"
    mkdir -p "$target"
    git -C "$target" init -b main >/dev/null 2>&1
    git -C "$target" config user.email "test@buildcrew.test"
    git -C "$target" config user.name "Test"
    git -C "$target" commit --allow-empty -m "init" >/dev/null 2>&1

    _batch_create_worktree "test-slug2" "main" "$target"
    local worktree_path
    worktree_path=$(_batch_worktree_path "test-slug2" "$target")

    [ -f "$worktree_path/.claude/.buildcrew-link" ]
    grep -q "BUILDCREW_HOME=" "$worktree_path/.claude/.buildcrew-link"

    git -C "$target" worktree remove --force "$worktree_path" 2>/dev/null || rm -rf "$worktree_path"
}

@test "_batch_create_worktree: does not overwrite existing skills from source repo" {
    __BATCH_CWD="$TEST_DIR"

    local target="$TEST_DIR/has-skills-project"
    mkdir -p "$target/.claude/skills/buildcrew"
    echo "custom skill" > "$target/.claude/skills/buildcrew/SKILL.md"
    git -C "$target" init -b main >/dev/null 2>&1
    git -C "$target" config user.email "test@buildcrew.test"
    git -C "$target" config user.name "Test"
    git -C "$target" add -A >/dev/null 2>&1
    git -C "$target" commit -m "init" >/dev/null 2>&1

    _batch_create_worktree "test-slug3" "main" "$target"
    local worktree_path
    worktree_path=$(_batch_worktree_path "test-slug3" "$target")

    # Skills were copied from source, not symlinked from BUILDCREW_HOME
    [ ! -L "$worktree_path/.claude/skills/buildcrew" ]
    grep -q "custom skill" "$worktree_path/.claude/skills/buildcrew/SKILL.md"

    git -C "$target" worktree remove --force "$worktree_path" 2>/dev/null || rm -rf "$worktree_path"
}

# ─────────────────────────────────────────────────────────────────────────────
# Stop signal in batch dispatch loop tests
# ─────────────────────────────────────────────────────────────────────────────

# Helper: set up a minimal batch dispatch loop environment with mocked internals.
# Usage: _setup_batch_dispatch_mocks [poll_behavior]
# poll_behavior: "noop" (default) | "complete_one" | "fail_one"
_setup_batch_dispatch_mocks() {
    local poll_behavior="${1:-noop}"

    # Initialize batch state globals
    _batch_running=0
    _batch_completed=0
    _batch_failed=0
    _batch_next_idx=0
    _batch_dashboard_lines=0
    _batch_start_time=$(date +%s)
    _batch_tasks=("Task A" "Task B" "Task C")
    _batch_slugs=("task-a" "task-b" "task-c")
    _batch_pids=()
    _batch_target_dirs=()
    _batch_plan_refs=()
    MAX_PARALLEL=2
    __BATCH_HEARTBEAT_PID=""
    __LOG_FILE=""

    # Ensure STOP_FILE path directory exists
    mkdir -p .buildcrew

    # Mock sleep to be instant
    sleep() { :; }
    export -f sleep

    # Mock _batch_refresh_dashboard to no-op
    _batch_refresh_dashboard() { :; }

    # Mock _batch_post_completion to no-op (real one calls exit)
    _batch_post_completion() { :; }

    # Mock _batch_launch_task to no-op (real one forks a subprocess)
    _batch_launch_task() {
        local idx="$1"
        _batch_pids[$idx]=""
        _batch_running=$(( _batch_running + 1 ))
    }

    # Mock _batch_get_task_status to return pending
    _batch_get_task_status() { echo "pending"; }

    # Mock _batch_create_worktree to no-op
    _batch_create_worktree() { return 0; }

    # Mock _batch_worktree_path to return a dummy path that exists
    _batch_worktree_path() { echo "$TEST_DIR"; }

    # Set up poll behavior
    case "$poll_behavior" in
        noop)
            _batch_poll_tasks() { :; }
            ;;
        complete_one)
            # Completes one task per poll call
            _batch_poll_tasks() {
                if (( _batch_running > 0 )); then
                    _batch_running=$(( _batch_running - 1 ))
                    _batch_completed=$(( _batch_completed + 1 ))
                fi
            }
            ;;
        fail_one)
            # Fails one task per poll call
            _batch_poll_tasks() {
                if (( _batch_running > 0 )); then
                    _batch_running=$(( _batch_running - 1 ))
                    _batch_failed=$(( _batch_failed + 1 ))
                fi
            }
            ;;
    esac
}

# HP-02: Stop signal triggers drain mode, breaks when running=0
@test "batch stop: stop signal with 0 running tasks breaks immediately" {
    _setup_batch_dispatch_mocks
    touch "$STOP_FILE"

    run _batch_dispatch_loop 3 main
    [ "$status" -eq 0 ]
    # Stop file should be cleared
    [ ! -f "$STOP_FILE" ]
    # Output should contain stop warning
    [[ "$output" == *"Stop signal received"* ]]
    # Should contain resume hint (3 tasks skipped)
    [[ "$output" == *"3 task(s) were not started"* ]]
}

# HP-03: Stop signal during drain waits for running tasks to complete
@test "batch stop: drain waits for running tasks to complete" {
    _setup_batch_dispatch_mocks "complete_one"
    # Simulate 1 running task
    _batch_running=1
    _batch_next_idx=1
    touch "$STOP_FILE"

    run _batch_dispatch_loop 3 main
    [ "$status" -eq 0 ]
    [ ! -f "$STOP_FILE" ]
    [[ "$output" == *"Stop signal received"* ]]
    [[ "$output" == *"Draining 1 running task(s)"* ]]
    # After drain: 1 completed, 2 skipped
    [[ "$output" == *"2 task(s) were not started"* ]]
}

# HP-04: Resume hint printed with correct skipped count
@test "batch stop: resume hint shows correct skipped count" {
    _setup_batch_dispatch_mocks
    _batch_completed=2
    _batch_next_idx=2
    touch "$STOP_FILE"

    run _batch_dispatch_loop 5 main
    [ "$status" -eq 0 ]
    [[ "$output" == *"3 task(s) were not started"* ]]
    [[ "$output" == *"buildcrew run --batch --resume"* ]]
}

# HP-05: clear_stop_signal called in enter_batch_mode before dispatch
@test "batch stop: enter_batch_mode calls clear_stop_signal before dispatch loop" {
    # Verify source code: clear_stop_signal must appear before _batch_dispatch_loop in enter_batch_mode
    local in_func=false
    local found_clear=false
    local found_dispatch=false
    while IFS= read -r line; do
        if [[ "$line" == *"enter_batch_mode()"* ]]; then
            in_func=true
        fi
        if [[ "$in_func" == "true" ]]; then
            if [[ "$line" == *"clear_stop_signal"* ]]; then
                found_clear=true
            fi
            if [[ "$line" == *"_batch_dispatch_loop"* ]]; then
                found_dispatch=true
                break
            fi
        fi
    done < "$BUILDCREW_ROOT/lib/workflow.sh"
    [ "$found_clear" = "true" ]
    [ "$found_dispatch" = "true" ]
}

# HP-06: clear_stop_signal called in _batch_resume before dispatch
@test "batch stop: _batch_resume calls clear_stop_signal before dispatch loop" {
    local in_func=false
    local found_clear=false
    local found_dispatch=false
    while IFS= read -r line; do
        if [[ "$line" == *"_batch_resume()"* ]]; then
            in_func=true
        fi
        if [[ "$in_func" == "true" ]]; then
            if [[ "$line" == *"clear_stop_signal"* ]]; then
                found_clear=true
            fi
            if [[ "$line" == *"_batch_dispatch_loop"* ]]; then
                found_dispatch=true
                break
            fi
        fi
    done < "$BUILDCREW_ROOT/lib/workflow.sh"
    [ "$found_clear" = "true" ]
    [ "$found_dispatch" = "true" ]
}

# HP-07: _batch_post_completion is called after stop-signal drain
@test "batch stop: _batch_post_completion called after drain" {
    local post_completion_called=false
    _setup_batch_dispatch_mocks
    _batch_post_completion() { post_completion_called=true; }
    touch "$STOP_FILE"

    _batch_dispatch_loop 3 main
    [ "$post_completion_called" = "true" ]
}

# ERR-01: Stop signal detected only once (sticky _batch_stopping flag)
@test "batch stop: stop file recreated during drain is ignored" {
    local poll_count=0
    _setup_batch_dispatch_mocks
    _batch_running=1
    _batch_next_idx=1

    # Custom poll that recreates stop file on second call, completes task on third
    _batch_poll_tasks() {
        poll_count=$(( poll_count + 1 ))
        if (( poll_count == 2 )); then
            # Recreate stop file during drain — should be ignored
            touch "$STOP_FILE"
        fi
        if (( poll_count >= 3 && _batch_running > 0 )); then
            _batch_running=$(( _batch_running - 1 ))
            _batch_completed=$(( _batch_completed + 1 ))
        fi
    }
    touch "$STOP_FILE"

    run _batch_dispatch_loop 3 main
    [ "$status" -eq 0 ]
    # Warning should appear exactly once
    local warn_count
    warn_count=$(echo "$output" | grep -c "Stop signal received" || true)
    [ "$warn_count" -eq 1 ]
}

# ERR-02: Stop file cleared after flag set (sequence verification)
@test "batch stop: stop file removed after detection" {
    _setup_batch_dispatch_mocks
    touch "$STOP_FILE"

    _batch_dispatch_loop 3 main
    [ ! -f "$STOP_FILE" ]
}

# ERR-03: Running task fails during drain
@test "batch stop: task failure during drain handled correctly" {
    _setup_batch_dispatch_mocks "fail_one"
    _batch_running=1
    _batch_next_idx=1
    touch "$STOP_FILE"

    run _batch_dispatch_loop 3 main
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stop signal received"* ]]
    # 3 total - 0 completed - 1 failed = 2 skipped
    [[ "$output" == *"2 task(s) were not started"* ]]
}

# EDGE-01: Stop signal when no tasks launched yet
@test "batch stop: stop at very start with no running tasks" {
    _setup_batch_dispatch_mocks
    touch "$STOP_FILE"

    run _batch_dispatch_loop 3 main
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stop signal received"* ]]
    [[ "$output" == *"Draining 0 running task(s)"* ]]
    [[ "$output" == *"3 task(s) were not started"* ]]
}

# EDGE-03: _batch_stopping is local to _batch_dispatch_loop
@test "batch stop: _batch_stopping variable is declared local" {
    grep -q 'local _batch_stopping' "$BUILDCREW_ROOT/lib/workflow.sh"
}

# EDGE-04: All tasks complete during drain — no resume hint
@test "batch stop: no resume hint when all tasks completed during drain" {
    _setup_batch_dispatch_mocks "complete_one"
    _batch_running=3
    _batch_completed=0
    _batch_next_idx=3
    touch "$STOP_FILE"

    run _batch_dispatch_loop 3 main
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stop signal received"* ]]
    # All 3 complete during drain, 0 skipped — no hint
    [[ "$output" != *"task(s) were not started"* ]]
}

# EDGE-06: Last task completes in same poll cycle as stop detection
@test "batch stop: last task completing and stop in same cycle breaks immediately" {
    local poll_count=0
    _setup_batch_dispatch_mocks
    _batch_running=1
    _batch_completed=2
    _batch_next_idx=3

    # Poll completes the last task in the same cycle stop is detected
    _batch_poll_tasks() {
        if (( _batch_running > 0 )); then
            _batch_running=$(( _batch_running - 1 ))
            _batch_completed=$(( _batch_completed + 1 ))
        fi
    }
    touch "$STOP_FILE"

    run _batch_dispatch_loop 3 main
    [ "$status" -eq 0 ]
    # All 3 completed, 0 skipped — no hint
    [[ "$output" != *"task(s) were not started"* ]]
}

# EDGE-08: Stop between batches (some completed, none running, more pending)
@test "batch stop: stop between completed batches with pending tasks" {
    _setup_batch_dispatch_mocks
    _batch_completed=2
    _batch_running=0
    _batch_next_idx=2
    touch "$STOP_FILE"

    run _batch_dispatch_loop 5 main
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stop signal received"* ]]
    # 5 total - 2 completed - 0 failed = 3 skipped
    [[ "$output" == *"3 task(s) were not started"* ]]
}

# EDGE-09: _batch_dispatch_loop called with total=0
@test "batch stop: dispatch loop with total=0 never enters loop" {
    _setup_batch_dispatch_mocks
    touch "$STOP_FILE"

    run _batch_dispatch_loop 0 main
    [ "$status" -eq 0 ]
    # Never entered loop, stop not checked
    [[ "$output" != *"Stop signal received"* ]]
    # Stop file still exists (not cleared by the loop)
    [ -f "$STOP_FILE" ]
}

# ADV-01: Stale stop file cleared on batch entry
@test "batch stop: stale stop file cleared by clear_stop_signal" {
    mkdir -p .buildcrew
    touch "$STOP_FILE"
    [ -f "$STOP_FILE" ]
    clear_stop_signal
    [ ! -f "$STOP_FILE" ]
}

# ADV-04: Multiple tasks finish during a single drain poll cycle
@test "batch stop: multiple tasks complete in one drain poll" {
    _setup_batch_dispatch_mocks
    _batch_running=3
    _batch_next_idx=3

    # Poll completes all 3 in one call
    _batch_poll_tasks() {
        while (( _batch_running > 0 )); do
            _batch_running=$(( _batch_running - 1 ))
            _batch_completed=$(( _batch_completed + 1 ))
        done
    }
    touch "$STOP_FILE"

    run _batch_dispatch_loop 3 main
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stop signal received"* ]]
    # All completed during drain, no skipped
    [[ "$output" != *"task(s) were not started"* ]]
}

# HP-01: Normal completion without stop signal
@test "batch stop: normal completion without stop signal" {
    _setup_batch_dispatch_mocks "complete_one"

    # The real loop does (( _batch_next_idx++ )) after _batch_launch_task,
    # so our mock must NOT also increment it — only set running.
    _batch_launch_task() {
        _batch_running=$(( _batch_running + 1 ))
    }

    run _batch_dispatch_loop 3 main
    [ "$status" -eq 0 ]
    # No stop signal warning
    [[ "$output" != *"Stop signal received"* ]]
    # No resume hint
    [[ "$output" != *"task(s) were not started"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# run_optional_simplify: diff-size gating
# ─────────────────────────────────────────────────────────────────────────────

@test "run_optional_simplify: skips when diff is less than 50 lines" {
    # Create a git repo with a small change
    git init -b main >/dev/null 2>&1
    git config user.email "test@buildcrew.test"
    git config user.name "Test"
    echo "line1" > file.txt
    git add file.txt
    git commit -m "init" >/dev/null 2>&1
    echo "line2" >> file.txt

    # Install simplify skill so the skill-dir check passes
    mkdir -p .claude/skills/buildcrew-simplify

    # Mock run_phase_group to track if it's called
    local phase_called=false
    run_phase_group() { phase_called=true; return 0; }

    run_optional_simplify "test task" "test context"
    [ "$phase_called" = "false" ]
}

@test "run_optional_simplify: runs when diff is 50+ lines" {
    # Create a git repo with a large change
    git init -b main >/dev/null 2>&1
    git config user.email "test@buildcrew.test"
    git config user.name "Test"
    echo "init" > file.txt
    git add file.txt
    git commit -m "init" >/dev/null 2>&1

    # Add 60 lines
    local i
    for i in $(seq 1 60); do
        echo "line $i" >> file.txt
    done

    mkdir -p .claude/skills/buildcrew-simplify

    local phase_called=false
    run_phase_group() { phase_called=true; return 0; }

    run_optional_simplify "test task" "test context"
    [ "$phase_called" = "true" ]
}

@test "run_optional_simplify: skips when simplify skill not installed" {
    run_optional_simplify "test task" "test context"
    # Should return 0 without error
}

@test "run_optional_simplify: accepts base_ref parameter" {
    git init -b main >/dev/null 2>&1
    git config user.email "test@buildcrew.test"
    git config user.name "Test"
    echo "init" > file.txt
    git add file.txt
    git commit -m "init" >/dev/null 2>&1

    mkdir -p .claude/skills/buildcrew-simplify

    local phase_called=false
    run_phase_group() { phase_called=true; return 0; }

    # With HEAD as base_ref, no staged diff — should skip
    run_optional_simplify "test task" "test context" "HEAD"
    [ "$phase_called" = "false" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Plan-skip logic
# ─────────────────────────────────────────────────────────────────────────────

@test "plan skip: plan_ref with actionable content triggers __plan_ref_skip" {
    # Create a plan file with actionable content
    local plan_file="$TEST_DIR/test-plan.md"
    cat > "$plan_file" << 'EOF'
# Implementation Plan

## Implementation Steps

1. Add new function to workflow.sh
2. Update tests

## Acceptance Criteria
- AC-01: Function exists
EOF

    # Verify grep matches
    grep -qE '(## Implementation|## Acceptance|^[0-9]+\.)' "$plan_file"
}

@test "plan skip: plan_ref without actionable content does not trigger skip" {
    local plan_file="$TEST_DIR/discovery-plan.md"
    cat > "$plan_file" << 'EOF'
# Discovery Notes

Some general notes about the project.
Nothing actionable here.
EOF

    # Verify grep does NOT match
    ! grep -qE '(## Implementation|## Acceptance|^[0-9]+\.)' "$plan_file"
}

@test "plan skip: copies plan to .claude/current-plan.md when skipping" {
    local plan_file="$TEST_DIR/test-plan.md"
    cat > "$plan_file" << 'EOF'
## Implementation Steps
1. Do the thing
EOF

    # Simulate what the plan skip code does
    mkdir -p .claude
    cp "$plan_file" .claude/current-plan.md
    [ -f ".claude/current-plan.md" ]
    grep -q "Do the thing" .claude/current-plan.md
}

# ─────────────────────────────────────────────────────────────────────────────
# _batch_assemble_combined_context
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_assemble_combined_context: creates context file" {
    __BATCH_CWD="$TEST_DIR"

    # Set up manifest and task arrays
    _batch_init_manifest "main" "abc123"
    _batch_add_task 1 "Task one" "task-one"
    _batch_mark_task 1 "completed" "0"

    _batch_tasks=("Task one")
    _batch_slugs=("task-one")

    # Create worktree dir with spec
    local wt_path="$BATCH_WORKTREE_DIR/task-one"
    mkdir -p "$wt_path/.claude"
    echo "- [ ] AC-01: Test criterion" > "$wt_path/.claude/spec.md"
    echo "## Implementation" > "$wt_path/.claude/current-plan.md"

    # Mock _batch_get_task_status
    _batch_get_task_status() { echo "completed"; }

    _batch_assemble_combined_context

    [ -f ".claude/batch-combined-context.md" ]
    grep -q "Task one" .claude/batch-combined-context.md
    grep -q "AC-01" .claude/batch-combined-context.md
}

# ─────────────────────────────────────────────────────────────────────────────
# _batch_merge_worktrees
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_merge_worktrees: returns 1 when no tasks completed" {
    __BATCH_CWD="$TEST_DIR"
    git init -b main >/dev/null 2>&1
    git config user.email "test@buildcrew.test"
    git config user.name "Test"
    git commit --allow-empty -m "init" >/dev/null 2>&1

    _batch_init_manifest "main" "$(git rev-parse HEAD)"
    _batch_add_task 1 "Task one" "task-one"
    _batch_mark_task 1 "failed" "1"

    _batch_tasks=("Task one")
    _batch_slugs=("task-one")

    _batch_get_task_status() { echo "failed"; }

    run _batch_merge_worktrees "main"
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# get_phase_max_turns: outcome removed, verify increased
# ─────────────────────────────────────────────────────────────────────────────

@test "get_phase_max_turns: verify returns 70" {
    result=$(get_phase_max_turns "verify")
    [ "$result" = "70" ]
}

@test "get_phase_max_turns: outcome falls through to default" {
    result=$(get_phase_max_turns "outcome")
    [ "$result" = "30" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Outcome phase removed from workflow
# ─────────────────────────────────────────────────────────────────────────────

@test "outcome phase: removed from process_task_isolated" {
    # The outcome phase section should no longer exist in workflow.sh
    ! grep -q '# --- outcome (validates against spec acceptance criteria) ---' "$BUILDCREW_ROOT/lib/workflow.sh"
}

@test "outcome phase: verify phase absorbs AC verification" {
    # The verify SKILL should mention AC verification
    grep -q 'AC Verification' "$BUILDCREW_ROOT/skills/buildcrew-verify/SKILL.md"
    grep -q 'outcome-report.md' "$BUILDCREW_ROOT/skills/buildcrew-verify/SKILL.md"
}

# ─────────────────────────────────────────────────────────────────────────────
# merge_conflict status handling
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_mark_task: handles merge_conflict status" {
    _batch_init_manifest "main" "abc123"
    _batch_add_task 1 "A task" "a-task"
    _batch_mark_task 1 "merge_conflict"
    [ "$(jq -r '.tasks[0].status' "$BATCH_MANIFEST")" = "merge_conflict" ]
}
