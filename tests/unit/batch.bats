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
# parse_args --batch tests
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --batch sets BATCH_MODE=true" {
    parse_args --batch
    [ "$BATCH_MODE" = "true" ]
}

@test "parse_args: BATCH_MODE defaults to false" {
    # BATCH_MODE is initialized to false at module load
    [ "$BATCH_MODE" = "false" ]
}

@test "parse_args: --help mentions --batch" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --help"
    [[ "$output" == *"--batch"* ]]
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
    parse_args --batch --resume
    [ "$BATCH_MODE" = "true" ]
    [ "$RESUME_MODE" = "true" ]
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
