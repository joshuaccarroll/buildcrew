#!/usr/bin/env bats
# Integration tests for buildcrew init command

load '../setup.bash'

setup() {
    setup_test_dir
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# buildcrew init tests
# ─────────────────────────────────────────────────────────────────────────────

@test "init: creates .claude directory" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ -d ".claude" ]
}

@test "init: creates .buildcrew-link file" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ -f ".claude/.buildcrew-link" ]
}

@test "init: .buildcrew-link contains BUILDCREW_HOME" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    grep -q "BUILDCREW_HOME=" ".claude/.buildcrew-link"
}

@test "init: creates .buildcrew directory" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ -d ".buildcrew" ]
}

@test "init: creates .buildcrew/rules directory" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ -d ".buildcrew/rules" ]
}

@test "init: creates workflow.md.example" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ -f ".buildcrew/workflow.md.example" ]
}

@test "init: creates project-rules.md.example" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ -f ".buildcrew/rules/project-rules.md.example" ]
}

@test "init: creates BACKLOG.md" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ -f "BACKLOG.md" ]
}

@test "init: creates settings.json" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ -f ".claude/settings.json" ]
}

@test "init: settings.json contains permissions" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    grep -q '"permissions"' ".claude/settings.json"
}

@test "init: does not overwrite existing BACKLOG.md" {
    echo "My existing backlog" > BACKLOG.md
    run "$BUILDCREW_HOME/bin/buildcrew" init
    grep -q "My existing backlog" BACKLOG.md
}

@test "init: does not overwrite existing settings.json" {
    mkdir -p .claude
    echo '{"custom": true}' > .claude/settings.json
    run "$BUILDCREW_HOME/bin/buildcrew" init
    grep -q '"custom"' ".claude/settings.json"
}

@test "init: shows success message" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"BuildCrew initialized"* ]]
}
