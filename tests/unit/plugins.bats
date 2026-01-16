#!/usr/bin/env bats
# Unit tests for lib/plugins.sh

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "plugins.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# detect_project_type tests
# ─────────────────────────────────────────────────────────────────────────────

@test "detect_project_type: returns 'any' for empty directory" {
    run detect_project_type
    [[ "$output" == *"any"* ]]
}

@test "detect_project_type: detects TypeScript project" {
    touch tsconfig.json
    run detect_project_type
    [[ "$output" == *"typescript"* ]]
}

@test "detect_project_type: detects Python project with pyproject.toml" {
    touch pyproject.toml
    run detect_project_type
    [[ "$output" == *"python"* ]]
}

@test "detect_project_type: detects Python project with requirements.txt" {
    touch requirements.txt
    run detect_project_type
    [[ "$output" == *"python"* ]]
}

@test "detect_project_type: detects Go project" {
    touch go.mod
    run detect_project_type
    [[ "$output" == *"go"* ]]
}

@test "detect_project_type: detects Rust project" {
    touch Cargo.toml
    run detect_project_type
    [[ "$output" == *"rust"* ]]
}

@test "detect_project_type: detects git repository" {
    mkdir .git
    run detect_project_type
    [[ "$output" == *"git"* ]]
}

@test "detect_project_type: detects React frontend" {
    cat > package.json << 'EOF'
{
  "dependencies": {
    "react": "^18.0.0"
  }
}
EOF
    run detect_project_type
    [[ "$output" == *"frontend"* ]]
}

@test "detect_project_type: detects Express backend" {
    cat > package.json << 'EOF'
{
  "dependencies": {
    "express": "^4.0.0"
  }
}
EOF
    run detect_project_type
    [[ "$output" == *"backend"* ]]
}

@test "detect_project_type: detects multiple types" {
    touch tsconfig.json
    mkdir .git
    run detect_project_type
    [[ "$output" == *"typescript"* ]]
    [[ "$output" == *"git"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# get_installed_skills tests
# ─────────────────────────────────────────────────────────────────────────────

@test "get_installed_skills: returns empty for no .claude/skills" {
    run get_installed_skills
    [ "$output" = "" ]
}

@test "get_installed_skills: returns skill names" {
    mkdir -p .claude/skills/my-skill
    mkdir -p .claude/skills/another-skill
    run get_installed_skills
    [[ "$output" == *"my-skill"* ]]
    [[ "$output" == *"another-skill"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# plugins_already_checked tests
# ─────────────────────────────────────────────────────────────────────────────

@test "plugins_already_checked: returns 1 when not checked" {
    run plugins_already_checked
    [ "$status" -eq 1 ]
}

@test "plugins_already_checked: returns 0 after mark_plugins_checked" {
    mark_plugins_checked
    run plugins_already_checked
    [ "$status" -eq 0 ]
}

@test "mark_plugins_checked: creates marker file" {
    mark_plugins_checked
    [ -f ".buildcrew/.plugins-checked" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# show_plugin_tip tests
# ─────────────────────────────────────────────────────────────────────────────

@test "show_plugin_tip: no tip for empty directory (just git/any)" {
    mkdir .git
    run show_plugin_tip
    [[ "$output" != *"buildcrew plugins"* ]]
    # But should still mark as checked
    [ -f ".buildcrew/.plugins-checked" ]
}

@test "show_plugin_tip: shows tip when project files exist" {
    touch tsconfig.json
    run show_plugin_tip
    [[ "$output" == *"buildcrew plugins"* ]]
    [ -f ".buildcrew/.plugins-checked" ]
}

@test "show_plugin_tip: marks plugins as checked" {
    show_plugin_tip
    run plugins_already_checked
    [ "$status" -eq 0 ]
}
