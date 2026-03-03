#!/usr/bin/env bats
# Unit tests for [plan:] annotation support in lib/workflow.sh

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# extract_task_plan_ref tests
# ─────────────────────────────────────────────────────────────────────────────

@test "extract_task_plan_ref: extracts plan filename" {
    run extract_task_plan_ref "[plan:PROJECT_foo.md] Build auth system"
    [ "$status" -eq 0 ]
    [ "$output" = "PROJECT_foo.md" ]
}

@test "extract_task_plan_ref: returns empty when no annotation" {
    run extract_task_plan_ref "Build auth system"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "extract_task_plan_ref: handles hyphens in filename" {
    run extract_task_plan_ref "[plan:PROJECT_my-cool-app.md] Setup database"
    [ "$status" -eq 0 ]
    [ "$output" = "PROJECT_my-cool-app.md" ]
}

@test "extract_task_plan_ref: does not match mid-string annotation" {
    run extract_task_plan_ref "Build [plan:PROJECT_foo.md] auth system"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# strip_task_plan_ref tests
# ─────────────────────────────────────────────────────────────────────────────

@test "strip_task_plan_ref: strips plan prefix" {
    run strip_task_plan_ref "[plan:PROJECT_foo.md] Build auth system"
    [ "$status" -eq 0 ]
    [ "$output" = "Build auth system" ]
}

@test "strip_task_plan_ref: no-op when no annotation" {
    run strip_task_plan_ref "Build auth system"
    [ "$status" -eq 0 ]
    [ "$output" = "Build auth system" ]
}

@test "strip_task_plan_ref: chained strip with dir prefix" {
    local task="[plan:PROJECT_foo.md] [dir:myapp] Build auth system"
    run strip_task_plan_ref "$task"
    [ "$status" -eq 0 ]
    [ "$output" = "[dir:myapp] Build auth system" ]
    run strip_task_dir "$output"
    [ "$status" -eq 0 ]
    [ "$output" = "Build auth system" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# mark_task_complete with [plan:] tests
# ─────────────────────────────────────────────────────────────────────────────

@test "mark_task_complete: preserves [plan:] prefix" {
    cat > BACKLOG.md << 'EOF'
- [ ] [plan:PROJECT_foo.md] Build auth system
EOF
    mark_task_complete "Build auth system"
    run cat BACKLOG.md
    [ "$output" = "- [x] [plan:PROJECT_foo.md] Build auth system" ]
}

@test "mark_task_complete: preserves [plan:] + [dir:] prefixes" {
    cat > BACKLOG.md << 'EOF'
- [ ] [plan:PROJECT_foo.md] [dir:myapp] Build auth system
EOF
    mark_task_complete "Build auth system"
    run cat BACKLOG.md
    [ "$output" = "- [x] [plan:PROJECT_foo.md] [dir:myapp] Build auth system" ]
}

@test "mark_task_complete: works without [plan:] prefix (regression)" {
    cat > BACKLOG.md << 'EOF'
- [ ] Build auth system
EOF
    mark_task_complete "Build auth system"
    run cat BACKLOG.md
    [ "$output" = "- [x] Build auth system" ]
}

@test "mark_task_complete: strips complexity tag with [plan:] prefix" {
    cat > BACKLOG.md << 'EOF'
- [ ] [plan:PROJECT_foo.md] Simple task {trivial}
EOF
    mark_task_complete "Simple task"
    run cat BACKLOG.md
    [ "$output" = "- [x] [plan:PROJECT_foo.md] Simple task" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# mark_task_blocked with [plan:] tests
# ─────────────────────────────────────────────────────────────────────────────

@test "mark_task_blocked: preserves [plan:] prefix" {
    cat > BACKLOG.md << 'EOF'
- [ ] [plan:PROJECT_foo.md] Build auth system
EOF
    mark_task_blocked "Build auth system" "spec phase failed"
    run cat BACKLOG.md
    [ "$output" = "- [!] [plan:PROJECT_foo.md] Build auth system (blocked: spec phase failed)" ]
}

@test "mark_task_blocked: preserves [plan:] + [dir:] prefixes" {
    cat > BACKLOG.md << 'EOF'
- [ ] [plan:PROJECT_foo.md] [dir:myapp] Build auth system
EOF
    mark_task_blocked "Build auth system" "spec phase failed"
    run cat BACKLOG.md
    [ "$output" = "- [!] [plan:PROJECT_foo.md] [dir:myapp] Build auth system (blocked: spec phase failed)" ]
}

@test "mark_task_blocked: works without [plan:] prefix (regression)" {
    cat > BACKLOG.md << 'EOF'
- [ ] Build auth system
EOF
    mark_task_blocked "Build auth system" "too vague"
    run cat BACKLOG.md
    [ "$output" = "- [!] Build auth system (blocked: too vague)" ]
}

@test "extract_task_plan_ref: empty [plan:] value returns empty string" {
    run extract_task_plan_ref "[plan:] Build auth system"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}
