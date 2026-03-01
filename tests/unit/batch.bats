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
