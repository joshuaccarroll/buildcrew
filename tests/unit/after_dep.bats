#!/usr/bin/env bats
# Unit tests for [after:] dependency support in lib/workflow.sh

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# extract_task_after_deps tests
# ─────────────────────────────────────────────────────────────────────────────

@test "extract_task_after_deps: extracts single dep" {
    run extract_task_after_deps "[after:3] Build auth system"
    [ "$status" -eq 0 ]
    [ "$output" = "3" ]
}

@test "extract_task_after_deps: extracts multiple comma-separated deps" {
    run extract_task_after_deps "[after:3,5,7] Build auth system"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3"* ]]
    [[ "$output" == *"5"* ]]
    [[ "$output" == *"7"* ]]
}

@test "extract_task_after_deps: returns empty when no annotation" {
    run extract_task_after_deps "Build auth system"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "extract_task_after_deps: works mid-string (after [dir:])" {
    run extract_task_after_deps "[dir:myapp] [after:2] Build auth system"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# strip_task_after tests
# ─────────────────────────────────────────────────────────────────────────────

@test "strip_task_after: strips [after:N] annotation" {
    run strip_task_after "[after:3] Build auth system"
    [ "$status" -eq 0 ]
    [ "$output" = "Build auth system" ]
}

@test "strip_task_after: strips [after:N,M] annotation" {
    run strip_task_after "[after:3,5] Build auth system"
    [ "$status" -eq 0 ]
    [ "$output" = "Build auth system" ]
}

@test "strip_task_after: no-op when no annotation" {
    run strip_task_after "Build auth system"
    [ "$status" -eq 0 ]
    [ "$output" = "Build auth system" ]
}

@test "strip_task_after: strips mid-string annotation" {
    run strip_task_after "[dir:myapp] [after:2] Build auth system"
    [ "$status" -eq 0 ]
    [ "$output" = "[dir:myapp] Build auth system" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# _after_dep_is_blocked tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_after_dep_is_blocked: not blocked when no deps" {
    cat > BACKLOG.md << 'EOF'
- [ ] Task one
- [ ] Task two
EOF
    run _after_dep_is_blocked "Task two"
    [ "$status" -eq 1 ]
}

@test "_after_dep_is_blocked: blocked when dep is pending" {
    cat > BACKLOG.md << 'EOF'
- [ ] Task one
- [ ] [after:1] Task two
EOF
    run _after_dep_is_blocked "[after:1] Task two"
    [ "$status" -eq 0 ]
}

@test "_after_dep_is_blocked: not blocked when dep is completed" {
    cat > BACKLOG.md << 'EOF'
- [x] Task one
- [ ] [after:1] Task two
EOF
    run _after_dep_is_blocked "[after:1] Task two"
    [ "$status" -eq 1 ]
}

@test "_after_dep_is_blocked: not blocked when dep is blocked" {
    cat > BACKLOG.md << 'EOF'
- [!] Task one (blocked: reason)
- [ ] [after:1] Task two
EOF
    run _after_dep_is_blocked "[after:1] Task two"
    [ "$status" -eq 1 ]
}

@test "_after_dep_is_blocked: blocked when any dep is pending (multiple deps)" {
    cat > BACKLOG.md << 'EOF'
- [x] Task one
- [ ] Task two
- [ ] [after:1,2] Task three
EOF
    run _after_dep_is_blocked "[after:1,2] Task three"
    [ "$status" -eq 0 ]
}

@test "_after_dep_is_blocked: not blocked when all deps resolved (multiple deps)" {
    cat > BACKLOG.md << 'EOF'
- [x] Task one
- [x] Task two
- [ ] [after:1,2] Task three
EOF
    run _after_dep_is_blocked "[after:1,2] Task three"
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# get_next_task with [after:] deps
# ─────────────────────────────────────────────────────────────────────────────

@test "get_next_task: skips dep-blocked task" {
    cat > BACKLOG.md << 'EOF'
- [ ] [after:99] Blocked task
- [ ] Available task
EOF
    # dep 99 doesn't exist (out of range), so it's not pending → not blocked
    # Let me use a real pending dep instead
    cat > BACKLOG.md << 'EOF'
- [ ] First task
- [ ] [after:1] Second task
EOF
    run get_next_task
    [ "$status" -eq 0 ]
    [ "$output" = "First task" ]
}

@test "get_next_task: returns dep-blocked task after dep completes" {
    cat > BACKLOG.md << 'EOF'
- [x] First task
- [ ] [after:1] Second task
EOF
    run get_next_task
    [ "$status" -eq 0 ]
    [ "$output" = "[after:1] Second task" ]
}

@test "get_next_task: skips all blocked tasks and returns first available" {
    cat > BACKLOG.md << 'EOF'
- [ ] First task
- [ ] [after:1] Second task
- [ ] Available third task
EOF
    # First task has no deps, so it's returned
    run get_next_task
    [ "$status" -eq 0 ]
    [ "$output" = "First task" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# gather_pending_tasks with [after:] deps
# ─────────────────────────────────────────────────────────────────────────────

@test "gather_pending_tasks: excludes dep-blocked tasks" {
    cat > BACKLOG.md << 'EOF'
- [ ] First task
- [ ] [after:1] Second task
- [ ] Third task
EOF
    gather_pending_tasks
    [ "$__BATCH_TASK_COUNT" -eq 2 ]
    [[ "$__BATCH_TASK_LIST" == *"First task"* ]]
    [[ "$__BATCH_TASK_LIST" == *"Third task"* ]]
    [[ "$__BATCH_TASK_LIST" != *"Second task"* ]]
}

@test "gather_pending_tasks: includes task when deps are resolved" {
    cat > BACKLOG.md << 'EOF'
- [x] First task
- [ ] [after:1] Second task
- [ ] Third task
EOF
    gather_pending_tasks
    [ "$__BATCH_TASK_COUNT" -eq 2 ]
    [[ "$__BATCH_TASK_LIST" == *"Second task"* ]]
    [[ "$__BATCH_TASK_LIST" == *"Third task"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# mark_task_complete / mark_task_blocked with [after:] prefix
# ─────────────────────────────────────────────────────────────────────────────

@test "mark_task_complete: preserves [after:] prefix" {
    cat > BACKLOG.md << 'EOF'
- [ ] [after:1] Build auth system
EOF
    mark_task_complete "Build auth system"
    run cat BACKLOG.md
    [ "$output" = "- [x] [after:1] Build auth system" ]
}

@test "mark_task_complete: preserves [plan:] + [dir:] + [after:] prefixes" {
    cat > BACKLOG.md << 'EOF'
- [ ] [plan:PROJECT_foo.md] [dir:myapp] [after:1] Build auth system
EOF
    mark_task_complete "Build auth system"
    run cat BACKLOG.md
    [ "$output" = "- [x] [plan:PROJECT_foo.md] [dir:myapp] [after:1] Build auth system" ]
}

@test "mark_task_blocked: preserves [after:] prefix" {
    cat > BACKLOG.md << 'EOF'
- [ ] [after:1] Build auth system
EOF
    mark_task_blocked "Build auth system" "spec failed"
    run cat BACKLOG.md
    [ "$output" = "- [!] [after:1] Build auth system (blocked: spec failed)" ]
}

@test "mark_task_blocked: preserves [plan:] + [dir:] + [after:] prefixes" {
    cat > BACKLOG.md << 'EOF'
- [ ] [plan:PROJECT_foo.md] [dir:myapp] [after:2] Build auth system
EOF
    mark_task_blocked "Build auth system" "too vague"
    run cat BACKLOG.md
    [ "$output" = "- [!] [plan:PROJECT_foo.md] [dir:myapp] [after:2] Build auth system (blocked: too vague)" ]
}
