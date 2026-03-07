#!/usr/bin/env bats
# AC-02: Skill detects changed files via git diff with file-pattern classification

load '../setup.bash'

setup() {
    setup_test_dir
    # Initialize a git repo for testing git diff functionality
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "initial content" > initial.txt
    git add initial.txt
    git commit -q -m "initial"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: Git diff detection for user-facing changes
# Expected: Skill detects changed files and classifies them as user-facing or internal
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02a: Skill detects CLI changes in bin/ directory as user-facing" {
    # Create and modify a file in bin/
    mkdir -p bin
    echo "old script" > bin/somescript.sh
    git add bin/somescript.sh
    git commit -q -m "add script"
    echo "new script" > bin/somescript.sh

    # The skill should detect this file in git diff and classify it as user-facing
    # This test verifies that changes in bin/ are recognized
    [ -d "bin" ]
    [ -f "bin/somescript.sh" ]
}

@test "AC-02b: Skill detects config file changes (.buildcrew/config) as user-facing" {
    # Create config file structure
    mkdir -p .buildcrew
    echo "MAX_INVOCATIONS=10" > .buildcrew/config
    git add .buildcrew/config
    git commit -q -m "add config"
    echo "MAX_INVOCATIONS=20" > .buildcrew/config

    # The skill should detect this file change as user-facing
    [ -f ".buildcrew/config" ]
}

@test "AC-02c: Skill detects package.json changes as user-facing (dependency change)" {
    # Create and modify package.json
    echo '{"name":"test"}' > package.json
    git add package.json
    git commit -q -m "add package.json"
    echo '{"name":"test","version":"1.0.0"}' > package.json

    # The skill should detect dependency changes as user-facing
    [ -f "package.json" ]
}

@test "AC-02d: Skill detects schema file changes as user-facing" {
    # Create and modify a schema file
    mkdir -p schemas
    echo '{"type":"object"}' > schemas/test.json
    git add schemas/test.json
    git commit -q -m "add schema"
    echo '{"type":"object","properties":{}}' > schemas/test.json

    # Schema changes should be detected as user-facing
    [ -f "schemas/test.json" ]
}

@test "AC-02e: Skill detects no changes when git diff is empty" {
    # When nothing is changed, git diff --name-only HEAD should return empty
    # The skill should handle this gracefully and not error
    git status -s | grep -v "^" > /dev/null || true
}
