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

@test "is_fresh_backlog: returns 1 when PROJECT file exists with no pending tasks" {
    echo "- [x] Completed task" > BACKLOG.md
    echo "# Project" > PROJECT_test.md
    run is_fresh_backlog
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# has_project_file tests
# ─────────────────────────────────────────────────────────────────────────────

@test "has_project_file: returns 0 when PROJECT file exists" {
    echo "# Project" > PROJECT_test.md
    run has_project_file
    [ "$status" -eq 0 ]
}

@test "has_project_file: returns 1 when no PROJECT file" {
    run has_project_file
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# is_completed_phase tests
# ─────────────────────────────────────────────────────────────────────────────

@test "is_completed_phase: returns 0 when project exists with no pending" {
    echo "- [x] Completed task" > BACKLOG.md
    echo "# Project" > PROJECT_test.md
    run is_completed_phase
    [ "$status" -eq 0 ]
}

@test "is_completed_phase: returns 1 when pending tasks exist" {
    echo "- [ ] Pending task" > BACKLOG.md
    echo "# Project" > PROJECT_test.md
    run is_completed_phase
    [ "$status" -eq 1 ]
}

@test "is_completed_phase: returns 1 when no project file" {
    echo "- [x] Completed task" > BACKLOG.md
    run is_completed_phase
    [ "$status" -eq 1 ]
}

@test "is_completed_phase: returns 0 when project exists with empty backlog" {
    echo "# Empty backlog" > BACKLOG.md
    echo "# Project" > PROJECT_test.md
    run is_completed_phase
    [ "$status" -eq 0 ]
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
# get_task_by_target tests
# ─────────────────────────────────────────────────────────────────────────────

@test "get_task_by_target: returns Nth pending task by number" {
    cat > BACKLOG.md << 'EOF'
- [x] Completed task
- [ ] First pending task
- [ ] Second pending task
- [ ] Third pending task
EOF
    run get_task_by_target "2"
    [ "$output" = "Second pending task" ]
}

@test "get_task_by_target: returns first pending task with number 1" {
    cat > BACKLOG.md << 'EOF'
- [x] Completed task
- [ ] First pending task
- [ ] Second pending task
EOF
    run get_task_by_target "1"
    [ "$output" = "First pending task" ]
}

@test "get_task_by_target: returns empty for out-of-range number" {
    cat > BACKLOG.md << 'EOF'
- [ ] Only task
EOF
    run get_task_by_target "5"
    [ "$output" = "" ]
}

@test "get_task_by_target: finds task by name substring" {
    cat > BACKLOG.md << 'EOF'
- [ ] Build the authentication system
- [ ] Add user profile page
- [ ] Fix login bug
EOF
    run get_task_by_target "profile"
    [ "$output" = "Add user profile page" ]
}

@test "get_task_by_target: name match is case-insensitive" {
    cat > BACKLOG.md << 'EOF'
- [ ] Build the Authentication System
- [ ] Add user profile page
EOF
    run get_task_by_target "authentication"
    [ "$output" = "Build the Authentication System" ]
}

@test "get_task_by_target: returns empty when no name match" {
    cat > BACKLOG.md << 'EOF'
- [ ] Build the auth system
- [ ] Add profile page
EOF
    run get_task_by_target "nonexistent"
    [ "$output" = "" ]
}

@test "get_task_by_target: skips completed and blocked tasks" {
    cat > BACKLOG.md << 'EOF'
- [x] Completed auth task
- [!] Blocked auth task
- [ ] Pending auth task
EOF
    run get_task_by_target "auth"
    [ "$output" = "Pending auth task" ]
}

@test "get_task_by_target: returns empty when no BACKLOG.md" {
    run get_task_by_target "anything"
    [ "$output" = "" ]
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

@test "mark_task_complete: handles regex metacharacters" {
    echo '- [ ] Create `tests/e2e/seed.ts` — a utility (v1.0+) module.' > BACKLOG.md
    mark_task_complete 'Create `tests/e2e/seed.ts` — a utility (v1.0+) module.'
    grep -q '\[x\]' BACKLOG.md
}

@test "mark_task_blocked: handles regex metacharacters" {
    echo '- [ ] Create `tests/e2e/seed.ts` — a utility (v1.0+) module.' > BACKLOG.md
    mark_task_blocked 'Create `tests/e2e/seed.ts` — a utility (v1.0+) module.' "needs review"
    grep -q '\[!\]' BACKLOG.md
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

# ─────────────────────────────────────────────────────────────────────────────
# update_workflow_state / clear_workflow_state tests
# ─────────────────────────────────────────────────────────────────────────────

@test "update_workflow_state: creates state file with correct key=value pairs" {
    mkdir -p .buildcrew
    __INVOCATION_COUNT=3
    MAX_INVOCATIONS=15
    __WF_TASK_NUM=2
    __WF_TOTAL_TASKS=5
    __WF_TASK_NAME="Build the auth system"
    update_workflow_state "research" "running"
    [ -f ".buildcrew/.workflow-state" ]
    grep -q "^PHASE=research$" .buildcrew/.workflow-state
    grep -q "^PHASE_STATUS=running$" .buildcrew/.workflow-state
    grep -q "^TASK_NUM=2$" .buildcrew/.workflow-state
    grep -q "^TOTAL_TASKS=5$" .buildcrew/.workflow-state
    grep -q "^INVOCATION_COUNT=3$" .buildcrew/.workflow-state
    grep -q "^MAX_INVOCATIONS=15$" .buildcrew/.workflow-state
}

@test "update_workflow_state: write is atomic (no partial file visible)" {
    mkdir -p .buildcrew
    __INVOCATION_COUNT=1
    MAX_INVOCATIONS=15
    __WF_TASK_NUM=1
    __WF_TOTAL_TASKS=1
    __WF_TASK_NAME="test task"
    update_workflow_state "build" "running"
    # Only the final state file should exist; temp files should be cleaned up
    [ -f ".buildcrew/.workflow-state" ]
    # No orphaned temp files should remain
    run bash -c 'ls .buildcrew/.workflow-state.tmp.* 2>/dev/null'
    [ "$output" = "" ]
}

@test "update_workflow_state: stores INVOCATION_COUNT and MAX_INVOCATIONS correctly" {
    mkdir -p .buildcrew
    __INVOCATION_COUNT=7
    MAX_INVOCATIONS=20
    __WF_TASK_NUM=""
    __WF_TOTAL_TASKS=""
    __WF_TASK_NAME=""
    update_workflow_state "test" "complete"
    grep -q "^INVOCATION_COUNT=7$" .buildcrew/.workflow-state
    grep -q "^MAX_INVOCATIONS=20$" .buildcrew/.workflow-state
}

@test "clear_workflow_state: removes state file" {
    mkdir -p .buildcrew
    touch .buildcrew/.workflow-state
    clear_workflow_state
    [ ! -f ".buildcrew/.workflow-state" ]
}

@test "clear_workflow_state: is safe when no state file exists" {
    run clear_workflow_state
    [ "$status" -eq 0 ]
}

@test "clear_workflow_state: removes orphaned temp files" {
    mkdir -p .buildcrew
    touch ".buildcrew/.workflow-state.tmp.12345"
    touch ".buildcrew/.workflow-state.tmp.67890"
    clear_workflow_state
    # No temp files should remain
    run bash -c 'ls .buildcrew/.workflow-state.tmp.* 2>/dev/null'
    [ "$output" = "" ]
}
