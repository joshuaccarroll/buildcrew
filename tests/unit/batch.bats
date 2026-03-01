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
# _build_batch_prompt tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_build_batch_prompt: includes task count and /batch instruction" {
    __BATCH_TASK_COUNT=3
    BACKLOG_FILE="BACKLOG.md"
    run _build_batch_prompt "1. Task one
2. Task two
3. Task three"
    [[ "$output" == *"3 tasks"* ]]
    [[ "$output" == *"/batch"* ]]
    [[ "$output" == *"Use /batch now"* ]]
}

@test "_build_batch_prompt: includes project context when lessons file exists" {
    __BATCH_TASK_COUNT=1
    BACKLOG_FILE="BACKLOG.md"
    mkdir -p .buildcrew
    echo "Always use TypeScript" > .buildcrew/lessons.md
    run _build_batch_prompt "1. A task"
    [[ "$output" == *"Always use TypeScript"* ]]
}

@test "_build_batch_prompt: produces valid prompt without project context" {
    __BATCH_TASK_COUNT=2
    BACKLOG_FILE="BACKLOG.md"
    # Ensure no .buildcrew directory
    rm -rf .buildcrew
    run _build_batch_prompt "1. Task one
2. Task two"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 tasks"* ]]
    [[ "$output" == *"Task one"* ]]
    [[ "$output" == *"Task two"* ]]
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
