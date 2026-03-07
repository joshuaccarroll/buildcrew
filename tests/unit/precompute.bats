#!/usr/bin/env bats
# Unit tests for lib/precompute.sh — phase precomputation

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "common.sh"
    source_lib "precompute.sh"
}

teardown() {
    teardown_test_dir
    __LOG_FILE=""
}

# ─────────────────────────────────────────────────────────────────────────────
# detect_test_runner tests
# ─────────────────────────────────────────────────────────────────────────────

@test "detect_test_runner: test.sh exists and is executable" {
    mkdir -p .claude/precompute
    touch test.sh && chmod +x test.sh
    detect_test_runner
    [ -f .claude/precompute/test-runner.md ]
    grep -q "Framework: test.sh" .claude/precompute/test-runner.md
    grep -q "Command: ./test.sh" .claude/precompute/test-runner.md
}

@test "detect_test_runner: test.sh not executable is skipped" {
    mkdir -p .claude/precompute
    touch test.sh
    chmod -x test.sh
    echo '{"scripts":{"test":"jest"}}' > package.json
    detect_test_runner
    grep -q "Framework: npm" .claude/precompute/test-runner.md
}

@test "detect_test_runner: Makefile with test target" {
    mkdir -p .claude/precompute
    printf 'test:\n\t@echo testing\n' > Makefile
    detect_test_runner
    grep -q "Framework: Make" .claude/precompute/test-runner.md
    grep -q "Command: make test" .claude/precompute/test-runner.md
}

@test "detect_test_runner: package.json with test script" {
    mkdir -p .claude/precompute
    echo '{"scripts":{"test":"jest"}}' > package.json
    detect_test_runner
    grep -q "Framework: npm" .claude/precompute/test-runner.md
    grep -q "Command: npm test" .claude/precompute/test-runner.md
}

@test "detect_test_runner: pyproject.toml" {
    mkdir -p .claude/precompute
    echo '[project]' > pyproject.toml
    detect_test_runner
    grep -q "Framework: Pytest" .claude/precompute/test-runner.md
    grep -q "Command: pytest" .claude/precompute/test-runner.md
}

@test "detect_test_runner: Cargo.toml" {
    mkdir -p .claude/precompute
    echo '[package]' > Cargo.toml
    detect_test_runner
    grep -q "Framework: Cargo" .claude/precompute/test-runner.md
    grep -q "Command: cargo test" .claude/precompute/test-runner.md
}

@test "detect_test_runner: bats files found" {
    mkdir -p .claude/precompute
    mkdir -p tests
    touch tests/example.bats
    detect_test_runner
    grep -q "Framework: Bats" .claude/precompute/test-runner.md
    grep -q "Command: bats ./tests" .claude/precompute/test-runner.md
}

@test "detect_test_runner: Go test files found" {
    mkdir -p .claude/precompute
    touch main_test.go
    detect_test_runner
    grep -q "Framework: Go" .claude/precompute/test-runner.md
    grep -q "Command: go test" .claude/precompute/test-runner.md
}

@test "detect_test_runner: no runner detected" {
    mkdir -p .claude/precompute
    detect_test_runner
    grep -q "No test runner detected" .claude/precompute/test-runner.md
}

@test "detect_test_runner: priority — test.sh wins over Makefile" {
    mkdir -p .claude/precompute
    touch test.sh && chmod +x test.sh
    printf 'test:\n\t@echo testing\n' > Makefile
    detect_test_runner
    grep -q "Framework: test.sh" .claude/precompute/test-runner.md
}

# ─────────────────────────────────────────────────────────────────────────────
# detect_project_stack tests
# ─────────────────────────────────────────────────────────────────────────────

@test "detect_project_stack: Node project" {
    mkdir -p .claude/precompute
    echo '{"name":"test","dependencies":{"express":"1.0"}}' > package.json
    detect_project_stack
    [ -f .claude/precompute/project-stack.md ]
    grep -q "JavaScript" .claude/precompute/project-stack.md
    grep -q "package.json" .claude/precompute/project-stack.md
}

@test "detect_project_stack: Python project" {
    mkdir -p .claude/precompute
    echo '[project]' > pyproject.toml
    detect_project_stack
    grep -q "Python" .claude/precompute/project-stack.md
    grep -q "pyproject.toml" .claude/precompute/project-stack.md
}

@test "detect_project_stack: Go project" {
    mkdir -p .claude/precompute
    printf 'module example.com/test\n\ngo 1.21\n' > go.mod
    detect_project_stack
    grep -q "Go" .claude/precompute/project-stack.md
    grep -q "go.mod" .claude/precompute/project-stack.md
}

@test "detect_project_stack: Rust project" {
    mkdir -p .claude/precompute
    echo '[package]' > Cargo.toml
    detect_project_stack
    grep -q "Rust" .claude/precompute/project-stack.md
    grep -q "Cargo.toml" .claude/precompute/project-stack.md
}

@test "detect_project_stack: Shell project" {
    mkdir -p .claude/precompute lib
    touch lib/a.sh lib/b.sh lib/c.sh lib/d.sh
    detect_project_stack
    grep -q "Shell" .claude/precompute/project-stack.md
}

@test "detect_project_stack: detects source directories" {
    mkdir -p .claude/precompute src lib
    echo '{}' > package.json
    detect_project_stack
    grep -q "src/" .claude/precompute/project-stack.md
    grep -q "lib/" .claude/precompute/project-stack.md
}

@test "detect_project_stack: unknown project" {
    mkdir -p .claude/precompute
    detect_project_stack
    [ -f .claude/precompute/project-stack.md ]
    grep -q "Unknown" .claude/precompute/project-stack.md
}

# ─────────────────────────────────────────────────────────────────────────────
# compute_codebase_structure tests
# ─────────────────────────────────────────────────────────────────────────────

@test "compute_codebase_structure: generates valid markdown" {
    mkdir -p .claude/precompute src
    touch src/main.js src/util.js README.md
    compute_codebase_structure
    [ -f .claude/precompute/codebase-structure.md ]
    grep -q "# Codebase Structure" .claude/precompute/codebase-structure.md
    grep -q "Total files:" .claude/precompute/codebase-structure.md
    grep -q "Directory tree" .claude/precompute/codebase-structure.md
}

@test "compute_codebase_structure: excludes .git directory" {
    mkdir -p .claude/precompute .git/objects
    touch file.txt
    compute_codebase_structure
    ! grep -q ".git" .claude/precompute/codebase-structure.md
}

@test "compute_codebase_structure: shows file extension stats" {
    mkdir -p .claude/precompute
    touch a.js b.js c.py
    compute_codebase_structure
    grep -q "Files by extension" .claude/precompute/codebase-structure.md
    grep -q "js" .claude/precompute/codebase-structure.md
}

# ─────────────────────────────────────────────────────────────────────────────
# run_precompute tests
# ─────────────────────────────────────────────────────────────────────────────

@test "run_precompute: creates precompute directory" {
    run_precompute
    [ -d .claude/precompute ]
}

@test "run_precompute: creates all output files" {
    run_precompute
    [ -f .claude/precompute/test-runner.md ]
    [ -f .claude/precompute/project-stack.md ]
    [ -f .claude/precompute/codebase-structure.md ]
}

@test "run_precompute: idempotent" {
    run_precompute
    run_precompute
    [ -f .claude/precompute/test-runner.md ]
    [ -f .claude/precompute/project-stack.md ]
    [ -f .claude/precompute/codebase-structure.md ]
}

# ─────────────────────────────────────────────────────────────────────────────
# precompute_uat tests
# ─────────────────────────────────────────────────────────────────────────────

@test "precompute_uat: writes artifact-type.md" {
    mkdir -p .claude/precompute
    # Source artifact.sh for detect_artifact_type
    source_lib "artifact.sh"
    echo '{"scripts":{"start":"node index.js"}}' > package.json
    precompute_uat
    [ -f .claude/precompute/artifact-type.md ]
    grep -q "# Artifact Type" .claude/precompute/artifact-type.md
    grep -q "Type:" .claude/precompute/artifact-type.md
}

@test "precompute_uat: detects Dockerfile as api type" {
    mkdir -p .claude/precompute
    source_lib "artifact.sh"
    echo "FROM node:18" > Dockerfile
    precompute_uat
    grep -q "Type: api" .claude/precompute/artifact-type.md
}
