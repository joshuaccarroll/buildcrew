#!/usr/bin/env bats
# Unit tests for lib/workflow.sh

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# is_fresh_backlog tests
# ─────────────────────────────────────────────────────────────────────────────

@test "is_fresh_backlog: returns 0 when no BACKLOG.md exists" {
    run is_fresh_backlog
    [ "$status" -eq 0 ]
}

@test "is_fresh_backlog: returns 0 when template placeholder present" {
    echo "- [ ] Your first task here" > BACKLOG.md
    run is_fresh_backlog
    [ "$status" -eq 0 ]
}

@test "is_fresh_backlog: returns 0 when no pending tasks" {
    echo "- [x] Completed task" > BACKLOG.md
    run is_fresh_backlog
    [ "$status" -eq 0 ]
}

@test "is_fresh_backlog: returns 1 when real tasks present" {
    echo "- [ ] Build the authentication system" > BACKLOG.md
    run is_fresh_backlog
    [ "$status" -eq 1 ]
}

@test "is_fresh_backlog: returns 1 with multiple real tasks" {
    cat > BACKLOG.md << 'EOF'
# Backlog
- [ ] Task one
- [ ] Task two
- [x] Completed task
EOF
    run is_fresh_backlog
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# get_next_task tests
# ─────────────────────────────────────────────────────────────────────────────

@test "get_next_task: returns empty when no BACKLOG.md" {
    run get_next_task
    [ "$output" = "" ]
}

@test "get_next_task: returns empty when no pending tasks" {
    echo "- [x] Completed task" > BACKLOG.md
    run get_next_task
    [ "$output" = "" ]
}

@test "get_next_task: extracts first pending task" {
    cat > BACKLOG.md << 'EOF'
- [x] Completed task
- [ ] Pending task 1
- [ ] Pending task 2
EOF
    run get_next_task
    [ "$output" = "Pending task 1" ]
}

@test "get_next_task: handles task with special characters" {
    echo '- [ ] Fix bug in user/profile endpoint' > BACKLOG.md
    run get_next_task
    [ "$output" = "Fix bug in user/profile endpoint" ]
}

@test "get_next_task: handles task with brackets" {
    echo '- [ ] Update [README] documentation' > BACKLOG.md
    run get_next_task
    [ "$output" = "Update [README] documentation" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# mark_task_complete tests
# ─────────────────────────────────────────────────────────────────────────────

@test "mark_task_complete: changes [ ] to [x]" {
    echo "- [ ] Test task" > BACKLOG.md
    mark_task_complete "Test task"
    grep -q "\[x\] Test task" BACKLOG.md
}

@test "mark_task_complete: only marks exact match" {
    cat > BACKLOG.md << 'EOF'
- [ ] Task
- [ ] Task with more text
EOF
    mark_task_complete "Task"
    grep -q "\[x\] Task$" BACKLOG.md
    grep -q "\[ \] Task with more text" BACKLOG.md
}

@test "mark_task_complete: handles special characters" {
    echo '- [ ] Fix bug in /api/users endpoint' > BACKLOG.md
    mark_task_complete "Fix bug in /api/users endpoint"
    grep -q "\[x\] Fix bug in /api/users endpoint" BACKLOG.md
}

# ─────────────────────────────────────────────────────────────────────────────
# mark_task_blocked tests
# ─────────────────────────────────────────────────────────────────────────────

@test "mark_task_blocked: changes [ ] to [!] with reason" {
    echo "- [ ] Test task" > BACKLOG.md
    mark_task_blocked "Test task" "needs clarification"
    grep -q "\[!\] Test task (blocked: needs clarification)" BACKLOG.md
}

@test "mark_task_blocked: handles empty reason" {
    echo "- [ ] Test task" > BACKLOG.md
    mark_task_blocked "Test task" ""
    grep -q "\[!\] Test task (blocked: )" BACKLOG.md
}

# ─────────────────────────────────────────────────────────────────────────────
# count_tasks tests
# ─────────────────────────────────────────────────────────────────────────────

@test "count_tasks: counts pending tasks" {
    cat > BACKLOG.md << 'EOF'
- [ ] Task 1
- [ ] Task 2
- [x] Completed
- [!] Blocked
EOF
    run count_tasks "pending"
    [ "$output" = "2" ]
}

@test "count_tasks: counts completed tasks" {
    cat > BACKLOG.md << 'EOF'
- [ ] Pending
- [x] Completed 1
- [x] Completed 2
- [x] Completed 3
EOF
    run count_tasks "completed"
    [ "$output" = "3" ]
}

@test "count_tasks: counts blocked tasks" {
    cat > BACKLOG.md << 'EOF'
- [ ] Pending
- [!] Blocked 1
- [!] Blocked 2
EOF
    run count_tasks "blocked"
    [ "$output" = "2" ]
}

@test "count_tasks: returns 0 for empty backlog" {
    echo "# Empty backlog" > BACKLOG.md
    run count_tasks "pending"
    [ "$output" = "0" ]
}

@test "count_tasks: returns 0 when file missing" {
    run count_tasks "pending"
    [ "$output" = "0" ]
}
