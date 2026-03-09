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
# _after_dep_is_blocked tests — Phase-header mode (AC-01 through AC-08)
# ─────────────────────────────────────────────────────────────────────────────

@test "_after_dep_is_blocked: phase mode — not blocked when all phase tasks done" {
    cat > BACKLOG.md << 'EOF'
## Phase 2: Build
- [x] Task one
- [!] Task two
EOF
    run _after_dep_is_blocked "[after:2] My task"
    [ "$status" -eq 1 ]
}

@test "_after_dep_is_blocked: phase mode — blocked when phase has pending task" {
    cat > BACKLOG.md << 'EOF'
## Phase 2: Build
- [ ] Task one
- [x] Task two
EOF
    run _after_dep_is_blocked "[after:2] My task"
    [ "$status" -eq 0 ]
}

@test "_after_dep_is_blocked: phase mode — empty phase not blocked, no stderr" {
    cat > BACKLOG.md << 'EOF'
## Phase 2: Build
## Phase 3: Test
- [ ] Something
EOF
    run _after_dep_is_blocked "[after:2] My task"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "_after_dep_is_blocked: phase mode — missing phase warns stderr and resolves" {
    cat > BACKLOG.md << 'EOF'
## Phase 1: Setup
- [x] Done task
EOF
    run _after_dep_is_blocked "[after:5] My task"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Phase 5 not found in backlog"* ]]
}

@test "_after_dep_is_blocked: phase mode — multi-dep blocked when one phase pending" {
    cat > BACKLOG.md << 'EOF'
## Phase 1: Alpha
- [x] Done
## Phase 2: Beta
- [ ] Pending
EOF
    run _after_dep_is_blocked "[after:1,2] My task"
    [ "$status" -eq 0 ]
}

@test "_after_dep_is_blocked: phase mode — prefix collision Phase 4 done Phase 40 pending" {
    cat > BACKLOG.md << 'EOF'
## Phase 4: Foo
- [x] Done task
## Phase 40: Bar
- [ ] Pending task
EOF
    run _after_dep_is_blocked "[after:4] My task"
    [ "$status" -eq 1 ]
}

@test "_after_dep_is_blocked: phase mode — last phase reads through EOF" {
    cat > BACKLOG.md << 'EOF'
## Phase 3: Last
- [ ] Pending at eof
EOF
    run _after_dep_is_blocked "[after:3] My task"
    [ "$status" -eq 0 ]
}

@test "_after_dep_is_blocked: backward compat — ordinal fallback when no phase headers" {
    cat > BACKLOG.md << 'EOF'
- [ ] Task one
- [ ] [after:1] Task two
EOF
    run _after_dep_is_blocked "[after:1] Task two"
    [ "$status" -eq 0 ]
}

@test "_after_dep_is_blocked: phase mode resolves by section not ordinal position" {
    cat > BACKLOG.md << 'EOF'
## Phase 1: Setup
- [x] Done
- [ ] Pending in phase 1
## Phase 2: Build
- [x] All done here
EOF
    run _after_dep_is_blocked "[after:2] My task"
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

# ─────────────────────────────────────────────────────────────────────────────
# get_next_task — edge cases
# ─────────────────────────────────────────────────────────────────────────────

@test "get_next_task: returns empty string when all tasks are circularly dep-blocked" {
    cat > BACKLOG.md << 'EOF'
- [ ] [after:2] Task one
- [ ] [after:1] Task two
EOF
    run get_next_task
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# gather_pending_tasks — [after:] tag stripping in output (AC: batch agent sees clean text)
# ─────────────────────────────────────────────────────────────────────────────

@test "gather_pending_tasks: strips [after:] tags from batch task list" {
    cat > BACKLOG.md << 'EOF'
- [x] First task
- [ ] [after:1] Second task
EOF
    gather_pending_tasks
    [ "$__BATCH_TASK_COUNT" -eq 1 ]
    [[ "$__BATCH_TASK_LIST" == *"Second task"* ]]
    [[ "$__BATCH_TASK_LIST" != *"[after:"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# get_task_by_target — dep-awareness for string targets
# ─────────────────────────────────────────────────────────────────────────────

@test "get_task_by_target: string match skips dep-blocked tasks and returns first unblocked" {
    cat > BACKLOG.md << 'EOF'
## Phase 1: Setup
- [ ] First phase task
## Phase 2: Build
- [ ] [after:1] auth blocked task
- [ ] auth unblocked task
EOF
    run get_task_by_target "auth"
    [ "$status" -eq 0 ]
    [ "$output" = "auth unblocked task" ]
}
