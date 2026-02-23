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

@test "init: creates .buildcrew/context directory" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ -d ".buildcrew/context" ]
}

@test "init: creates context/users.md.example" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ -f ".buildcrew/context/users.md.example" ]
}

@test "init: creates context/principles.md.example" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ -f ".buildcrew/context/principles.md.example" ]
}

@test "init: creates context/domain.md.example" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ -f ".buildcrew/context/domain.md.example" ]
}

@test "init: shows success message" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"BuildCrew initialized"* ]]
}

@test "init: links individual skills when .claude/skills is a real directory" {
    mkdir -p .claude/skills
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ "$status" -eq 0 ]
    # At least one phase-isolated skill subdirectory should exist as a symlink
    [ -L ".claude/skills/buildcrew-research" ] || [ -L ".claude/skills/buildcrew-build" ]
}

@test "init: does not overwrite real subdirectories inside .claude/skills" {
    mkdir -p .claude/skills/buildcrew-research
    echo "user content" > .claude/skills/buildcrew-research/custom.md
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ "$status" -eq 0 ]
    # Real directory must be preserved
    [ -d ".claude/skills/buildcrew-research" ] && [ ! -L ".claude/skills/buildcrew-research" ]
    grep -q "user content" ".claude/skills/buildcrew-research/custom.md"
}

@test "init: creates whole-tree symlink when .claude/skills does not exist" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ "$status" -eq 0 ]
    [ -L ".claude/skills" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# statusLine configuration tests
# ─────────────────────────────────────────────────────────────────────────────

@test "init: settings.json contains statusLine config" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ "$status" -eq 0 ]
    grep -q '"statusLine"' .claude/settings.json
}

@test "init: statusLine command points to statusline.sh" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ "$status" -eq 0 ]
    grep -q 'statusline.sh' .claude/settings.json
}

@test "init: statusLine command is resolved path not literal variable" {
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ "$status" -eq 0 ]
    # Should not contain literal $BUILDCREW_HOME string
    ! grep -q '\$BUILDCREW_HOME' .claude/settings.json
}

@test "init: re-running init adds statusLine when missing from existing settings.json" {
    mkdir -p .claude
    echo '{"permissions": {"allow": []}}' > .claude/settings.json
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ "$status" -eq 0 ]
    grep -q '"statusLine"' .claude/settings.json
}

@test "init: re-running init does not overwrite existing statusLine config" {
    mkdir -p .claude
    printf '{"statusLine": {"type": "command", "command": "/my/custom/statusline.sh"}}\n' > .claude/settings.json
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ "$status" -eq 0 ]
    grep -q '/my/custom/statusline.sh' .claude/settings.json
}

@test "init: re-running init on fully initialized project preserves statusLine" {
    # First init
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ "$status" -eq 0 ]
    local first_cmd
    first_cmd=$(jq -r '.statusLine.command' .claude/settings.json)
    # Second init
    run "$BUILDCREW_HOME/bin/buildcrew" init
    [ "$status" -eq 0 ]
    local second_cmd
    second_cmd=$(jq -r '.statusLine.command' .claude/settings.json)
    [ "$first_cmd" = "$second_cmd" ]
}
