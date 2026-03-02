#!/usr/bin/env bats
# Unit tests for lib/artifact.sh — artifact publishing and management

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "artifact.sh"

    # Override HOME so tests write to a temp directory, not the real ~/.buildcrew
    export ORIGINAL_HOME="$HOME"
    export HOME="$TEST_DIR/fakehome"
    mkdir -p "$HOME"
}

teardown() {
    export HOME="$ORIGINAL_HOME"
    teardown_test_dir
    __LOG_FILE=""
}

# ─────────────────────────────────────────────────────────────────────────────
# sha256_hash tests
# ─────────────────────────────────────────────────────────────────────────────

@test "sha256_hash: computes hash of a file" {
    echo "hello world" > testfile.txt
    run sha256_hash testfile.txt
    [ "$status" -eq 0 ]
    # The hash should be a 64-char hex string
    [[ "${#output}" -eq 64 ]]
    [[ "$output" =~ ^[0-9a-f]+$ ]]
}

@test "sha256_hash: same content produces same hash" {
    echo "identical" > file1.txt
    echo "identical" > file2.txt
    hash1=$(sha256_hash file1.txt)
    hash2=$(sha256_hash file2.txt)
    [ "$hash1" = "$hash2" ]
}

@test "sha256_hash: different content produces different hash" {
    echo "content A" > file1.txt
    echo "content B" > file2.txt
    hash1=$(sha256_hash file1.txt)
    hash2=$(sha256_hash file2.txt)
    [ "$hash1" != "$hash2" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# read_config_key tests
# ─────────────────────────────────────────────────────────────────────────────

@test "read_config_key: returns empty when no config file" {
    run read_config_key "UAT_ARTIFACT_TYPE"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "read_config_key: reads existing key" {
    mkdir -p .buildcrew
    echo "UAT_ARTIFACT_TYPE=cli" > .buildcrew/config
    run read_config_key "UAT_ARTIFACT_TYPE"
    [ "$status" -eq 0 ]
    [ "$output" = "cli" ]
}

@test "read_config_key: returns empty for missing key" {
    mkdir -p .buildcrew
    echo "OTHER_KEY=value" > .buildcrew/config
    run read_config_key "UAT_ARTIFACT_TYPE"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "read_config_key: strips double quotes from value" {
    mkdir -p .buildcrew
    echo 'UAT_RUN_COMMAND="./bin/app"' > .buildcrew/config
    run read_config_key "UAT_RUN_COMMAND"
    [ "$status" -eq 0 ]
    [ "$output" = "./bin/app" ]
}

@test "read_config_key: strips single quotes from value" {
    mkdir -p .buildcrew
    echo "UAT_RUN_COMMAND='./bin/app'" > .buildcrew/config
    run read_config_key "UAT_RUN_COMMAND"
    [ "$status" -eq 0 ]
    [ "$output" = "./bin/app" ]
}

@test "read_config_key: skips comment lines" {
    mkdir -p .buildcrew
    cat > .buildcrew/config << 'EOF'
# This is a comment
UAT_ARTIFACT_TYPE=api
EOF
    run read_config_key "UAT_ARTIFACT_TYPE"
    [ "$status" -eq 0 ]
    [ "$output" = "api" ]
}

@test "read_config_key: skips blank lines" {
    mkdir -p .buildcrew
    printf 'UAT_ARTIFACT_TYPE=api\n\nUAT_RUN_COMMAND=test\n' > .buildcrew/config
    run read_config_key "UAT_RUN_COMMAND"
    [ "$status" -eq 0 ]
    [ "$output" = "test" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# read_artifact_hints tests
# ─────────────────────────────────────────────────────────────────────────────

@test "read_artifact_hints: returns 0 when no hints file" {
    run read_artifact_hints
    [ "$status" -eq 0 ]
}

@test "read_artifact_hints: clears globals when no hints file" {
    __RUN_COMMAND="old"
    __INSTALL_COMMAND="old"
    __HEALTH_CHECK="old"
    __STOP_COMMAND="old"
    read_artifact_hints
    [ -z "$__RUN_COMMAND" ]
    [ -z "$__INSTALL_COMMAND" ]
    [ -z "$__HEALTH_CHECK" ]
    [ -z "$__STOP_COMMAND" ]
}

@test "read_artifact_hints: loads all four fields" {
    mkdir -p .buildcrew
    cat > .buildcrew/artifact-hints.json << 'EOF'
{
    "run_command": "./bin/myapp serve",
    "install_command": "pip install -e .",
    "health_check": "curl -sf http://localhost:8080/health",
    "stop_command": "kill $PID"
}
EOF
    read_artifact_hints
    [ "$__RUN_COMMAND" = "./bin/myapp serve" ]
    [ "$__INSTALL_COMMAND" = "pip install -e ." ]
    [ "$__HEALTH_CHECK" = "curl -sf http://localhost:8080/health" ]
    [ "$__STOP_COMMAND" = 'kill $PID' ]
}

@test "read_artifact_hints: treats empty string values as absent" {
    mkdir -p .buildcrew
    cat > .buildcrew/artifact-hints.json << 'EOF'
{
    "run_command": "",
    "install_command": "pip install -e ."
}
EOF
    read_artifact_hints
    [ -z "$__RUN_COMMAND" ]
    [ "$__INSTALL_COMMAND" = "pip install -e ." ]
}

@test "read_artifact_hints: warns and falls through on malformed JSON" {
    mkdir -p .buildcrew
    echo "not valid json {{{" > .buildcrew/artifact-hints.json
    run read_artifact_hints
    [ "$status" -eq 0 ]
    [[ "$output" == *"Malformed"* ]]
}

@test "read_artifact_hints: ignores unknown fields" {
    mkdir -p .buildcrew
    cat > .buildcrew/artifact-hints.json << 'EOF'
{
    "run_command": "test",
    "unknown_field": "ignored",
    "artifact_type": "should_not_be_read"
}
EOF
    read_artifact_hints
    [ "$__RUN_COMMAND" = "test" ]
}

@test "read_artifact_hints: handles partial hints (only some fields)" {
    mkdir -p .buildcrew
    cat > .buildcrew/artifact-hints.json << 'EOF'
{
    "run_command": "make run"
}
EOF
    read_artifact_hints
    [ "$__RUN_COMMAND" = "make run" ]
    [ -z "$__INSTALL_COMMAND" ]
    [ -z "$__HEALTH_CHECK" ]
    [ -z "$__STOP_COMMAND" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# detect_artifact_type tests
# ─────────────────────────────────────────────────────────────────────────────

@test "detect_artifact_type: uses config override first" {
    mkdir -p .buildcrew
    echo "UAT_ARTIFACT_TYPE=tui" > .buildcrew/config
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "tui" ]
}

@test "detect_artifact_type: detects Dockerfile as api" {
    touch Dockerfile
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "api" ]
}

@test "detect_artifact_type: detects docker-compose.yml as api" {
    touch docker-compose.yml
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "api" ]
}

@test "detect_artifact_type: detects docker-compose.yaml as api" {
    touch docker-compose.yaml
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "api" ]
}

@test "detect_artifact_type: detects Textual import as tui" {
    echo "from textual.app import App" > app.py
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "tui" ]
}

@test "detect_artifact_type: detects curses import as tui" {
    echo "import curses" > main.py
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "tui" ]
}

@test "detect_artifact_type: detects urwid import as tui" {
    echo "import urwid" > main.py
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "tui" ]
}

@test "detect_artifact_type: detects tui in subdirectory" {
    mkdir -p src
    echo "from textual import App" > src/app.py
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "tui" ]
}

@test "detect_artifact_type: detects Cargo.toml as cli" {
    echo '[package]' > Cargo.toml
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "cli" ]
}

@test "detect_artifact_type: detects go.mod with main.go as cli" {
    echo "module example.com/myapp" > go.mod
    echo "package main" > main.go
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "cli" ]
}

@test "detect_artifact_type: go.mod without main.go is not cli" {
    echo "module example.com/mylib" > go.mod
    # No main.go
    detect_artifact_type
    # Should fall through to 'other' since no other markers exist
    [ "$__ARTIFACT_TYPE" = "other" ]
}

@test "detect_artifact_type: detects Makefile as cli" {
    echo "all:" > Makefile
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "cli" ]
}

@test "detect_artifact_type: detects executable in bin/ as cli" {
    mkdir -p bin
    echo "#!/bin/bash" > bin/myapp
    chmod +x bin/myapp
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "cli" ]
}

@test "detect_artifact_type: non-executable file in bin/ is not cli" {
    mkdir -p bin
    echo "data" > bin/readme.txt
    # Not executable, should not be cli
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "other" ]
}

@test "detect_artifact_type: detects setup.py as library" {
    echo "from setuptools import setup" > setup.py
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "library" ]
}

@test "detect_artifact_type: detects pyproject.toml as library" {
    echo "[project]" > pyproject.toml
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "library" ]
}

@test "detect_artifact_type: detects package.json as library" {
    echo '{"name": "mylib"}' > package.json
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "library" ]
}

@test "detect_artifact_type: returns other when nothing matches" {
    # Empty directory
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "other" ]
}

@test "detect_artifact_type: priority — Dockerfile wins over setup.py" {
    touch Dockerfile
    echo "from setuptools import setup" > setup.py
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "api" ]
}

@test "detect_artifact_type: priority — config wins over Dockerfile" {
    mkdir -p .buildcrew
    echo "UAT_ARTIFACT_TYPE=library" > .buildcrew/config
    touch Dockerfile
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "library" ]
}

@test "detect_artifact_type: priority — tui wins over Makefile" {
    echo "import curses" > app.py
    echo "all:" > Makefile
    detect_artifact_type
    [ "$__ARTIFACT_TYPE" = "tui" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# detect_run_command tests
# ─────────────────────────────────────────────────────────────────────────────

@test "detect_run_command: uses config override first" {
    mkdir -p .buildcrew
    echo 'UAT_RUN_COMMAND=./custom-run' > .buildcrew/config
    __RUN_COMMAND=""
    detect_run_command "cli"
    [ "$__RUN_COMMAND" = "./custom-run" ]
}

@test "detect_run_command: uses hints when no config" {
    __RUN_COMMAND="./from-hints"
    detect_run_command "cli"
    [ "$__RUN_COMMAND" = "./from-hints" ]
}

@test "detect_run_command: auto-detects docker compose for api with Dockerfile" {
    touch Dockerfile
    __RUN_COMMAND=""
    detect_run_command "api"
    [ "$__RUN_COMMAND" = "docker compose up" ]
}

@test "detect_run_command: auto-detects app.py for api without Docker" {
    echo "from flask import Flask" > app.py
    __RUN_COMMAND=""
    detect_run_command "api"
    [ "$__RUN_COMMAND" = "python app.py" ]
}

@test "detect_run_command: auto-detects server.js for api without Docker" {
    echo "const express = require('express')" > server.js
    __RUN_COMMAND=""
    detect_run_command "api"
    [ "$__RUN_COMMAND" = "node server.js" ]
}

@test "detect_run_command: auto-detects single binary in bin/ for cli" {
    mkdir -p bin
    echo "#!/bin/bash" > bin/myapp
    chmod +x bin/myapp
    __RUN_COMMAND=""
    detect_run_command "cli"
    [ "$__RUN_COMMAND" = "./bin/myapp" ]
}

@test "detect_run_command: auto-detects make run for cli with Makefile" {
    cat > Makefile << 'EOF'
run:
	echo "running"
EOF
    __RUN_COMMAND=""
    detect_run_command "cli"
    [ "$__RUN_COMMAND" = "make run" ]
}

@test "detect_run_command: sets library message for library type" {
    __RUN_COMMAND=""
    detect_run_command "library"
    [[ "$__RUN_COMMAND" == *"Library artifact"* ]]
}

@test "detect_run_command: empty for other type" {
    __RUN_COMMAND=""
    detect_run_command "other"
    [ -z "$__RUN_COMMAND" ]
}

@test "detect_run_command: tui uses same detection as cli" {
    mkdir -p bin
    echo "#!/bin/bash" > bin/tui-app
    chmod +x bin/tui-app
    __RUN_COMMAND=""
    detect_run_command "tui"
    [ "$__RUN_COMMAND" = "./bin/tui-app" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# publish_artifact tests
# ─────────────────────────────────────────────────────────────────────────────

@test "publish_artifact: creates manifest.json" {
    echo "# My Project" > README.md
    publish_artifact "test-project"
    [ -f "$HOME/.buildcrew/artifacts/test-project/manifest.json" ]
}

@test "publish_artifact: manifest has correct project name" {
    echo "# My Project" > README.md
    publish_artifact "test-project"
    local project
    project=$(jq -r '.project' "$HOME/.buildcrew/artifacts/test-project/manifest.json")
    [ "$project" = "test-project" ]
}

@test "publish_artifact: manifest has artifact_path as pwd" {
    echo "# My Project" > README.md
    publish_artifact "test-project"
    local path
    path=$(jq -r '.artifact_path' "$HOME/.buildcrew/artifacts/test-project/manifest.json")
    [ "$path" = "$(pwd)" ]
}

@test "publish_artifact: manifest has readme_hash" {
    echo "# My Project" > README.md
    publish_artifact "test-project"
    local hash
    hash=$(jq -r '.readme_hash' "$HOME/.buildcrew/artifacts/test-project/manifest.json")
    [[ "${#hash}" -eq 64 ]]
}

@test "publish_artifact: build_iteration starts at 1" {
    echo "# My Project" > README.md
    publish_artifact "test-project"
    local iteration
    iteration=$(jq -r '.build_iteration' "$HOME/.buildcrew/artifacts/test-project/manifest.json")
    [ "$iteration" = "1" ]
}

@test "publish_artifact: build_iteration increments on second publish" {
    echo "# My Project" > README.md
    publish_artifact "test-project"
    publish_artifact "test-project"
    local iteration
    iteration=$(jq -r '.build_iteration' "$HOME/.buildcrew/artifacts/test-project/manifest.json")
    [ "$iteration" = "2" ]
}

@test "publish_artifact: build_iteration increments to 3 on third publish" {
    echo "# My Project" > README.md
    publish_artifact "test-project"
    publish_artifact "test-project"
    publish_artifact "test-project"
    local iteration
    iteration=$(jq -r '.build_iteration' "$HOME/.buildcrew/artifacts/test-project/manifest.json")
    [ "$iteration" = "3" ]
}

@test "publish_artifact: fails with empty project name" {
    run publish_artifact ""
    [ "$status" -eq 1 ]
}

@test "publish_artifact: detects artifact type" {
    echo "# My Project" > README.md
    touch Dockerfile
    publish_artifact "test-project"
    local type
    type=$(jq -r '.artifact_type' "$HOME/.buildcrew/artifacts/test-project/manifest.json")
    [ "$type" = "api" ]
}

@test "publish_artifact: reads hints into manifest" {
    echo "# My Project" > README.md
    mkdir -p .buildcrew
    cat > .buildcrew/artifact-hints.json << 'EOF'
{
    "run_command": "python app.py",
    "install_command": "pip install -e .",
    "health_check": "curl localhost:8080",
    "stop_command": "kill $PID"
}
EOF
    publish_artifact "test-project"
    local install
    install=$(jq -r '.install_command' "$HOME/.buildcrew/artifacts/test-project/manifest.json")
    [ "$install" = "pip install -e ." ]
}

@test "publish_artifact: manifest has build_timestamp" {
    echo "# My Project" > README.md
    publish_artifact "test-project"
    local ts
    ts=$(jq -r '.build_timestamp' "$HOME/.buildcrew/artifacts/test-project/manifest.json")
    # Should be an ISO 8601 timestamp
    [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "publish_artifact: handles missing README.md gracefully" {
    # No README.md
    publish_artifact "test-project"
    local hash
    hash=$(jq -r '.readme_hash' "$HOME/.buildcrew/artifacts/test-project/manifest.json")
    [ "$hash" = "" ]
}

@test "publish_artifact: no .tmp file left behind (atomic write)" {
    echo "# My Project" > README.md
    publish_artifact "test-project"
    [ ! -f "$HOME/.buildcrew/artifacts/test-project/manifest.json.tmp" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# read_manifest tests
# ─────────────────────────────────────────────────────────────────────────────

@test "read_manifest: returns 1 for missing file" {
    local rc=0
    read_manifest "/nonexistent/path/manifest.json" || rc=$?
    [ "$rc" -eq 1 ]
}

@test "read_manifest: returns 1 for invalid JSON" {
    echo "not json" > test-manifest.json
    local rc=0
    read_manifest "test-manifest.json" || rc=$?
    [ "$rc" -eq 1 ]
}

@test "read_manifest: returns 1 for missing required fields" {
    echo '{"run_command": "test"}' > test-manifest.json
    local rc=0
    read_manifest "test-manifest.json" || rc=$?
    [ "$rc" -eq 1 ]
}

@test "read_manifest: sets all globals on valid manifest" {
    cat > test-manifest.json << 'EOF'
{
    "project": "myproj",
    "artifact_type": "cli",
    "artifact_path": "/tmp/myproj",
    "run_command": "./bin/app",
    "install_command": "make install",
    "health_check": "",
    "stop_command": "",
    "build_timestamp": "2024-01-01T12:00:00Z",
    "build_iteration": 3,
    "readme_hash": "abc123"
}
EOF
    read_manifest "test-manifest.json"
    [ "$__MANIFEST_PROJECT" = "myproj" ]
    [ "$__MANIFEST_ARTIFACT_TYPE" = "cli" ]
    [ "$__MANIFEST_ARTIFACT_PATH" = "/tmp/myproj" ]
    [ "$__MANIFEST_RUN_COMMAND" = "./bin/app" ]
    [ "$__MANIFEST_INSTALL_COMMAND" = "make install" ]
    [ "$__MANIFEST_BUILD_ITERATION" = "3" ]
    [ "$__MANIFEST_README_HASH" = "abc123" ]
}

@test "read_manifest: resets globals before reading" {
    __MANIFEST_PROJECT="stale"
    __MANIFEST_ARTIFACT_TYPE="stale"
    local rc=0
    read_manifest "/nonexistent/manifest.json" || rc=$?
    [ "$__MANIFEST_PROJECT" = "" ]
    [ "$__MANIFEST_ARTIFACT_TYPE" = "" ]
}

@test "read_manifest: reads published manifest (round-trip)" {
    echo "# My Project" > README.md
    publish_artifact "roundtrip-project"
    read_manifest "$HOME/.buildcrew/artifacts/roundtrip-project/manifest.json"
    [ "$__MANIFEST_PROJECT" = "roundtrip-project" ]
    [ "$__MANIFEST_ARTIFACT_PATH" = "$(pwd)" ]
    [ "$__MANIFEST_BUILD_ITERATION" = "1" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# write_uat_context tests
# ─────────────────────────────────────────────────────────────────────────────

@test "write_uat_context: creates uat-context.md" {
    mkdir -p .buildcrew
    cat > verdict.json << 'EOF'
{
    "status": "fail",
    "build_iteration": 1,
    "total": 2,
    "passed": 1,
    "failed": 1,
    "errored": 0,
    "disputed": 0,
    "scenarios": [
        {
            "scenario": "User creates project",
            "status": "pass",
            "summary": "",
            "expected": "",
            "actual": ""
        },
        {
            "scenario": "User deletes project",
            "status": "fail",
            "summary": "Exit code 1 instead of 0",
            "expected": "Exit code 0",
            "actual": "Exit code 1, stderr: Permission denied"
        }
    ]
}
EOF
    write_uat_context "verdict.json" 2 5
    [ -f ".buildcrew/uat-context.md" ]
}

@test "write_uat_context: contains iteration info" {
    mkdir -p .buildcrew
    cat > verdict.json << 'EOF'
{
    "status": "fail",
    "scenarios": [
        {
            "scenario": "Test",
            "status": "fail",
            "summary": "Failed",
            "expected": "Pass",
            "actual": "Fail"
        }
    ]
}
EOF
    write_uat_context "verdict.json" 3 5
    run cat .buildcrew/uat-context.md
    [[ "$output" == *"UAT Iteration 3/5"* ]]
}

@test "write_uat_context: separates failures from errors" {
    mkdir -p .buildcrew
    cat > verdict.json << 'EOF'
{
    "status": "fail",
    "scenarios": [
        {
            "scenario": "Code bug scenario",
            "status": "fail",
            "summary": "Wrong exit code",
            "expected": "Exit 0",
            "actual": "Exit 1"
        },
        {
            "scenario": "Env problem scenario",
            "status": "error",
            "summary": "Module not found",
            "expected": "Import success",
            "actual": "ImportError"
        }
    ]
}
EOF
    write_uat_context "verdict.json" 1 5
    run cat .buildcrew/uat-context.md
    [[ "$output" == *"Failures (code bugs):"* ]]
    [[ "$output" == *"Errors (environmental"* ]]
    [[ "$output" == *"Code bug scenario"* ]]
    [[ "$output" == *"Env problem scenario"* ]]
}

@test "write_uat_context: includes expected and actual for failures" {
    mkdir -p .buildcrew
    cat > verdict.json << 'EOF'
{
    "status": "fail",
    "scenarios": [
        {
            "scenario": "Test scenario",
            "status": "fail",
            "summary": "Bad exit",
            "expected": "Exit code 0",
            "actual": "Exit code 1"
        }
    ]
}
EOF
    write_uat_context "verdict.json" 1 5
    run cat .buildcrew/uat-context.md
    [[ "$output" == *"Expected: Exit code 0"* ]]
    [[ "$output" == *"Actual: Exit code 1"* ]]
}

@test "write_uat_context: includes do-not-access warning" {
    mkdir -p .buildcrew
    cat > verdict.json << 'EOF'
{
    "status": "fail",
    "scenarios": [
        {
            "scenario": "Test",
            "status": "fail",
            "summary": "Fail",
            "expected": "P",
            "actual": "F"
        }
    ]
}
EOF
    write_uat_context "verdict.json" 1 5
    run cat .buildcrew/uat-context.md
    [[ "$output" == *"Do NOT access the UAT directory"* ]]
}

@test "write_uat_context: returns 1 for missing verdict file" {
    local rc=0
    write_uat_context "/nonexistent/verdict.json" 1 5 || rc=$?
    [ "$rc" -eq 1 ]
}

@test "write_uat_context: returns 1 for invalid verdict JSON" {
    echo "not json" > bad-verdict.json
    local rc=0
    write_uat_context "bad-verdict.json" 1 5 || rc=$?
    [ "$rc" -eq 1 ]
}

@test "write_uat_context: no .tmp file left behind (atomic write)" {
    mkdir -p .buildcrew
    cat > verdict.json << 'EOF'
{
    "status": "fail",
    "scenarios": [
        {
            "scenario": "Test",
            "status": "fail",
            "summary": "Fail",
            "expected": "P",
            "actual": "F"
        }
    ]
}
EOF
    write_uat_context "verdict.json" 1 5
    [ ! -f ".buildcrew/uat-context.md.tmp" ]
}

@test "write_uat_context: handles errors-only verdict (no failures)" {
    mkdir -p .buildcrew
    cat > verdict.json << 'EOF'
{
    "status": "error",
    "scenarios": [
        {
            "scenario": "Env issue",
            "status": "error",
            "summary": "Server timeout",
            "expected": "",
            "actual": ""
        }
    ]
}
EOF
    write_uat_context "verdict.json" 1 5
    run cat .buildcrew/uat-context.md
    [[ "$output" == *"1 error"* ]]
    # Should NOT contain "Failures" section
    [[ "$output" != *"Failures (code bugs):"* ]]
}

@test "write_uat_context: handles plural counts correctly" {
    mkdir -p .buildcrew
    cat > verdict.json << 'EOF'
{
    "status": "fail",
    "scenarios": [
        { "scenario": "A", "status": "fail", "summary": "F1", "expected": "P", "actual": "F" },
        { "scenario": "B", "status": "fail", "summary": "F2", "expected": "P", "actual": "F" },
        { "scenario": "C", "status": "error", "summary": "E1", "expected": "", "actual": "" },
        { "scenario": "D", "status": "error", "summary": "E2", "expected": "", "actual": "" }
    ]
}
EOF
    write_uat_context "verdict.json" 1 5
    run cat .buildcrew/uat-context.md
    [[ "$output" == *"2 scenarios failed"* ]]
    [[ "$output" == *"2 errors"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# cleanup_artifact tests
# ─────────────────────────────────────────────────────────────────────────────

@test "cleanup_artifact: removes manifest when no signal dir" {
    local artifact_dir="$HOME/.buildcrew/artifacts/test-project"
    mkdir -p "$artifact_dir"
    echo '{}' > "$artifact_dir/manifest.json"
    cleanup_artifact "test-project"
    [ ! -f "$artifact_dir/manifest.json" ]
}

@test "cleanup_artifact: preserves manifest when signal dir exists" {
    local artifact_dir="$HOME/.buildcrew/artifacts/test-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/test-project"
    mkdir -p "$artifact_dir"
    mkdir -p "$signal_dir"
    echo '{}' > "$artifact_dir/manifest.json"
    cleanup_artifact "test-project"
    [ -f "$artifact_dir/manifest.json" ]
}

@test "cleanup_artifact: handles missing manifest gracefully" {
    # No manifest exists, should not error
    run cleanup_artifact "nonexistent-project"
    [ "$status" -eq 0 ]
}

@test "cleanup_artifact: fails with empty project name" {
    run cleanup_artifact ""
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Source guard tests
# ─────────────────────────────────────────────────────────────────────────────

@test "artifact.sh: source guard prevents double-sourcing" {
    local first_load="$__BUILDCREW_ARTIFACT_LOADED"
    source_lib "artifact.sh"
    [ "$__BUILDCREW_ARTIFACT_LOADED" = "$first_load" ]
}
