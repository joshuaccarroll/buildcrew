#!/usr/bin/env bats
# Unit tests for lib/uat.sh — UAT orchestrator functions

load '../setup.bash'

setup() {
    setup_test_dir
    # Source uat.sh (which sources common.sh and uat_signal.sh internally)
    source_lib "uat.sh"
}

teardown() {
    # Stop any lingering server/monitor processes
    uat_stop_server 2>/dev/null || true
    stop_file_monitor 2>/dev/null || true
    __LOG_FILE=""
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper to create a mock README
# ─────────────────────────────────────────────────────────────────────────────

create_test_readme() {
    local dir="${1:-.}"
    cat > "${dir}/README.md" << 'EOF'
# Test Project

A CLI tool for testing.

## Usage

```
testapp init my-project
testapp run
```

## Features

- Initialize a project directory
- Run the main workflow
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# Source guard tests
# ─────────────────────────────────────────────────────────────────────────────

@test "uat.sh: source guard prevents double-sourcing" {
    local first_load="$__BUILDCREW_UAT_LOADED"
    source_lib "uat.sh"
    [ "$__BUILDCREW_UAT_LOADED" = "$first_load" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# load_uat_config tests
# ─────────────────────────────────────────────────────────────────────────────

@test "load_uat_config: loads config values from .buildcrew/config" {
    mkdir -p .buildcrew
    cat > .buildcrew/config << 'EOF'
UAT_POLL_INTERVAL=10
UAT_ARTIFACT_TIMEOUT=3600
UAT_EXECUTE_TIMEOUT=300
UAT_HEALTH_CHECK_TIMEOUT=60
UAT_MAX_RETRIES=3
EOF
    load_uat_config
    [ "$UAT_POLL_INTERVAL" = "10" ]
    [ "$UAT_ARTIFACT_TIMEOUT" = "3600" ]
    [ "$UAT_EXECUTE_TIMEOUT" = "300" ]
    [ "$UAT_HEALTH_CHECK_TIMEOUT" = "60" ]
    [ "$UAT_MAX_RETRIES" = "3" ]
}

@test "load_uat_config: uses defaults when no config file" {
    # Ensure defaults are set
    UAT_POLL_INTERVAL=5
    UAT_ARTIFACT_TIMEOUT=7200
    load_uat_config
    [ "$UAT_POLL_INTERVAL" = "5" ]
    [ "$UAT_ARTIFACT_TIMEOUT" = "7200" ]
}

@test "load_uat_config: ignores invalid values" {
    mkdir -p .buildcrew
    cat > .buildcrew/config << 'EOF'
UAT_POLL_INTERVAL=abc
UAT_ARTIFACT_TIMEOUT=-5
UAT_MAX_RETRIES=0
EOF
    UAT_POLL_INTERVAL=5
    UAT_ARTIFACT_TIMEOUT=7200
    UAT_MAX_RETRIES=5
    load_uat_config
    [ "$UAT_POLL_INTERVAL" = "5" ]
    [ "$UAT_ARTIFACT_TIMEOUT" = "7200" ]
    [ "$UAT_MAX_RETRIES" = "5" ]
}

@test "load_uat_config: skips comments and blank lines" {
    mkdir -p .buildcrew
    cat > .buildcrew/config << 'EOF'
# This is a comment
UAT_POLL_INTERVAL=15

# Another comment
UAT_MAX_RETRIES=7
EOF
    load_uat_config
    [ "$UAT_POLL_INTERVAL" = "15" ]
    [ "$UAT_MAX_RETRIES" = "7" ]
}

@test "load_uat_config: strips surrounding quotes from values" {
    mkdir -p .buildcrew
    cat > .buildcrew/config << 'EOF'
UAT_POLL_INTERVAL="10"
UAT_MAX_RETRIES='3'
EOF
    load_uat_config
    [ "$UAT_POLL_INTERVAL" = "10" ]
    [ "$UAT_MAX_RETRIES" = "3" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# _uat_sha256_hash tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_uat_sha256_hash: computes hash for a file" {
    echo "hello world" > test.txt
    run _uat_sha256_hash test.txt
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    # SHA-256 hash is 64 hex characters
    [[ ${#output} -eq 64 ]]
}

@test "_uat_sha256_hash: same content produces same hash" {
    echo "test content" > file1.txt
    echo "test content" > file2.txt
    local hash1 hash2
    hash1=$(_uat_sha256_hash file1.txt)
    hash2=$(_uat_sha256_hash file2.txt)
    [ "$hash1" = "$hash2" ]
}

@test "_uat_sha256_hash: different content produces different hash" {
    echo "content A" > file1.txt
    echo "content B" > file2.txt
    local hash1 hash2
    hash1=$(_uat_sha256_hash file1.txt)
    hash2=$(_uat_sha256_hash file2.txt)
    [ "$hash1" != "$hash2" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# _uat_read_manifest tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_uat_read_manifest: reads valid manifest" {
    mkdir -p artifacts
    cat > artifacts/manifest.json << 'EOF'
{
    "project": "test-project",
    "artifact_type": "cli",
    "artifact_path": "/tmp/test",
    "run_command": "./bin/test",
    "install_command": "",
    "health_check": "",
    "stop_command": "",
    "build_timestamp": "2024-01-01T00:00:00Z",
    "build_iteration": 1,
    "readme_hash": "abc123"
}
EOF
    _uat_read_manifest artifacts/manifest.json
    [ "$__UAT_ARTIFACT_TYPE" = "cli" ]
    [ "$__UAT_ARTIFACT_PATH" = "/tmp/test" ]
    [ "$__UAT_RUN_COMMAND" = "./bin/test" ]
    [ "$__UAT_BUILD_ITERATION" = "1" ]
    [ "$__UAT_README_HASH" = "abc123" ]
}

@test "_uat_read_manifest: returns 1 for missing file" {
    run _uat_read_manifest nonexistent.json
    [ "$status" -eq 1 ]
}

@test "_uat_read_manifest: returns 1 for invalid JSON" {
    echo "not json" > bad.json
    run _uat_read_manifest bad.json
    [ "$status" -eq 1 ]
}

@test "_uat_read_manifest: returns 1 for missing required fields" {
    echo '{"project": "test"}' > incomplete.json
    run _uat_read_manifest incomplete.json
    [ "$status" -eq 1 ]
}

@test "_uat_read_manifest: resets globals on call" {
    __UAT_ARTIFACT_TYPE="old_value"
    __UAT_BUILD_ITERATION="old_value"
    # Call directly (not via run) so globals are set in the current shell
    _uat_read_manifest nonexistent.json || true
    [ "$__UAT_ARTIFACT_TYPE" = "" ]
    [ "$__UAT_BUILD_ITERATION" = "" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# _uat_regress_set_artifact tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_uat_regress_set_artifact: sets path and defaults (type=cli, run_command empty, iteration=1)" {
    mkdir -p .buildcrew
    local artifact_dir
    artifact_dir=$(mktemp -d)
    _uat_regress_set_artifact "$artifact_dir" ""
    [ "$__UAT_ARTIFACT_PATH" = "$artifact_dir" ]
    [ "$__UAT_ARTIFACT_TYPE" = "cli" ]
    [ "$__UAT_RUN_COMMAND" = "" ]
    [ "$__UAT_BUILD_ITERATION" = "1" ]
    rm -rf "$artifact_dir"
}

@test "_uat_regress_set_artifact: reads type from config" {
    mkdir -p .buildcrew
    echo 'UAT_ARTIFACT_TYPE=api' > .buildcrew/config
    local artifact_dir
    artifact_dir=$(mktemp -d)
    _uat_regress_set_artifact "$artifact_dir" ""
    [ "$__UAT_ARTIFACT_TYPE" = "api" ]
    rm -rf "$artifact_dir"
}

@test "_uat_regress_set_artifact: reads run_command from config" {
    mkdir -p .buildcrew
    echo 'UAT_RUN_COMMAND=npm start' > .buildcrew/config
    local artifact_dir
    artifact_dir=$(mktemp -d)
    _uat_regress_set_artifact "$artifact_dir" ""
    [ "$__UAT_RUN_COMMAND" = "npm start" ]
    rm -rf "$artifact_dir"
}

@test "_uat_regress_set_artifact: reads all 5 config overrides together" {
    mkdir -p .buildcrew
    cat > .buildcrew/config << 'EOF'
UAT_ARTIFACT_TYPE=api
UAT_RUN_COMMAND=node server.js
UAT_INSTALL_COMMAND=npm install
UAT_HEALTH_CHECK=curl http://localhost:3000
UAT_STOP_COMMAND=kill $PID
EOF
    local artifact_dir
    artifact_dir=$(mktemp -d)
    _uat_regress_set_artifact "$artifact_dir" ""
    [ "$__UAT_ARTIFACT_TYPE" = "api" ]
    [ "$__UAT_RUN_COMMAND" = "node server.js" ]
    [ "$__UAT_INSTALL_COMMAND" = "npm install" ]
    [ "$__UAT_HEALTH_CHECK" = "curl http://localhost:3000" ]
    [ "$__UAT_STOP_COMMAND" = 'kill $PID' ]
    rm -rf "$artifact_dir"
}

@test "_uat_regress_set_artifact: iteration = last_tested + 1" {
    mkdir -p .buildcrew
    echo "5" > .buildcrew/last_tested_iteration
    local artifact_dir
    artifact_dir=$(mktemp -d)
    _uat_regress_set_artifact "$artifact_dir" ""
    [ "$__UAT_BUILD_ITERATION" = "6" ]
    rm -rf "$artifact_dir"
}

@test "_uat_regress_set_artifact: iteration defaults to 1 when no last_tested file" {
    mkdir -p .buildcrew
    rm -f .buildcrew/last_tested_iteration
    local artifact_dir
    artifact_dir=$(mktemp -d)
    _uat_regress_set_artifact "$artifact_dir" ""
    [ "$__UAT_BUILD_ITERATION" = "1" ]
    rm -rf "$artifact_dir"
}

@test "_uat_regress_set_artifact: requires regress_path argument" {
    run _uat_regress_set_artifact "" ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"required"* ]]
}

@test "_uat_regress_set_artifact: computes README hash (64-char hex)" {
    mkdir -p .buildcrew
    create_test_readme .
    local artifact_dir
    artifact_dir=$(mktemp -d)
    _uat_regress_set_artifact "$artifact_dir" "README.md"
    [ -n "$__UAT_README_HASH" ]
    [[ ${#__UAT_README_HASH} -eq 64 ]]
    rm -rf "$artifact_dir"
}

@test "_uat_regress_set_artifact: handles missing readme gracefully (empty hash)" {
    mkdir -p .buildcrew
    local artifact_dir
    artifact_dir=$(mktemp -d)
    _uat_regress_set_artifact "$artifact_dir" "/nonexistent/README.md"
    [ "$__UAT_README_HASH" = "" ]
    rm -rf "$artifact_dir"
}

# ─────────────────────────────────────────────────────────────────────────────
# uat_init tests
# ─────────────────────────────────────────────────────────────────────────────

@test "uat_init: requires readme_path and project_name" {
    run uat_init "" ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"required"* ]]
}

@test "uat_init: fails for nonexistent README" {
    run uat_init "/nonexistent/README.md" "test-project"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "uat_init: creates .buildcrew directory" {
    local src_dir
    src_dir=$(mktemp -d)
    create_test_readme "$src_dir"
    uat_init "$src_dir/README.md" "test-project"
    [ -d ".buildcrew" ]
    rm -rf "$src_dir" "$HOME/.buildcrew/uat-signals/test-project"
}

@test "uat_init: writes isolation CLAUDE.md" {
    local src_dir
    src_dir=$(mktemp -d)
    create_test_readme "$src_dir"
    uat_init "$src_dir/README.md" "test-project"
    [ -f ".buildcrew/CLAUDE.md" ]
    local content
    content=$(cat .buildcrew/CLAUDE.md)
    [[ "$content" == *"Do NOT read, list, or access"* ]]
    [[ "$content" == *"harness/.artifact-bin/"* ]]
    rm -rf "$src_dir" "$HOME/.buildcrew/uat-signals/test-project"
}

@test "uat_init: creates subdirectories" {
    local src_dir
    src_dir=$(mktemp -d)
    create_test_readme "$src_dir"
    uat_init "$src_dir/README.md" "test-project"
    [ -d "scenarios" ]
    [ -d "harness" ]
    [ -d "results" ]
    rm -rf "$src_dir" "$HOME/.buildcrew/uat-signals/test-project"
}

@test "uat_init: copies README into working dir" {
    local src_dir
    src_dir=$(mktemp -d)
    create_test_readme "$src_dir"
    uat_init "$src_dir/README.md" "test-project"
    [ -f "README.md" ]
    [[ "$(cat README.md)" == *"Test Project"* ]]
    rm -rf "$src_dir" "$HOME/.buildcrew/uat-signals/test-project"
}

@test "uat_init: stores README hash" {
    local src_dir
    src_dir=$(mktemp -d)
    create_test_readme "$src_dir"
    uat_init "$src_dir/README.md" "test-project"
    [ -f ".buildcrew/last_readme_hash" ]
    local hash
    hash=$(cat .buildcrew/last_readme_hash)
    [ -n "$hash" ]
    [[ ${#hash} -eq 64 ]]
    rm -rf "$src_dir" "$HOME/.buildcrew/uat-signals/test-project"
}

@test "uat_init: creates signal directory" {
    local src_dir
    src_dir=$(mktemp -d)
    create_test_readme "$src_dir"
    uat_init "$src_dir/README.md" "test-project"
    [ -d "$HOME/.buildcrew/uat-signals/test-project" ]
    # Cleanup
    rm -rf "$src_dir" "$HOME/.buildcrew/uat-signals/test-project"
}

@test "uat_init: does not delete existing verdict.json" {
    local src_dir
    src_dir=$(mktemp -d)
    create_test_readme "$src_dir"
    mkdir -p "$HOME/.buildcrew/uat-signals/test-project"
    echo '{"status":"pass"}' > "$HOME/.buildcrew/uat-signals/test-project/verdict.json"
    uat_init "$src_dir/README.md" "test-project"
    [ -f "$HOME/.buildcrew/uat-signals/test-project/verdict.json" ]
    # Cleanup
    rm -rf "$src_dir" "$HOME/.buildcrew/uat-signals/test-project"
}

# ─────────────────────────────────────────────────────────────────────────────
# uat_phase_setup_env tests (CLI type)
# ─────────────────────────────────────────────────────────────────────────────

@test "uat_phase_setup_env: requires artifact_type and artifact_path" {
    run uat_phase_setup_env "" ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"required"* ]]
}

@test "uat_phase_setup_env: CLI creates artifact-bin directory" {
    mkdir -p harness
    uat_phase_setup_env "cli" "/tmp" "./bin/myapp" "" ""
    [ -d "harness/.artifact-bin" ]
}

@test "uat_phase_setup_env: CLI creates wrapper script for binary path" {
    mkdir -p harness
    uat_phase_setup_env "cli" "/tmp/project" "./bin/myapp" "" ""
    [ -f "harness/.artifact-bin/myapp" ]
    [ -x "harness/.artifact-bin/myapp" ]
    local content
    content=$(cat harness/.artifact-bin/myapp)
    [[ "$content" == *"/tmp/project/bin/myapp"* ]]
    [[ "$content" == *"exec"* ]]
}

@test "uat_phase_setup_env: CLI creates wrapper for invocation pattern" {
    mkdir -p harness
    uat_phase_setup_env "cli" "/tmp/project" "cargo run" "" ""
    [ -f "harness/.artifact-bin/cargo" ]
    [ -x "harness/.artifact-bin/cargo" ]
    local content
    content=$(cat harness/.artifact-bin/cargo)
    [[ "$content" == *"cd \"/tmp/project\""* ]]
    [[ "$content" == *"cargo run"* ]]
}

@test "uat_phase_setup_env: CLI sets artifact context" {
    mkdir -p harness
    uat_phase_setup_env "cli" "/tmp/project" "./bin/myapp" "" ""
    [[ "$__UAT_ARTIFACT_CONTEXT" == *"harness/.artifact-bin/"* ]]
    [[ "$__UAT_ARTIFACT_CONTEXT" == *"CLI commands"* ]]
}

@test "uat_phase_setup_env: TUI treated same as CLI" {
    mkdir -p harness
    uat_phase_setup_env "tui" "/tmp/project" "./bin/myapp" "" ""
    [ -f "harness/.artifact-bin/myapp" ]
    [[ "$__UAT_ARTIFACT_CONTEXT" == *"CLI commands"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# uat_phase_setup_env tests (Library type)
# ─────────────────────────────────────────────────────────────────────────────

@test "uat_phase_setup_env: library creates .artifact-env for Python" {
    mkdir -p harness
    local proj_dir
    proj_dir=$(mktemp -d)
    touch "$proj_dir/setup.py"
    mkdir -p "$proj_dir/src"
    uat_phase_setup_env "library" "$proj_dir" "" "" ""
    [ -f "harness/.artifact-env" ]
    local content
    content=$(cat harness/.artifact-env)
    [[ "$content" == *"PYTHONPATH"* ]]
    [[ "$content" == *"$proj_dir/src"* ]]
    rm -rf "$proj_dir"
}

@test "uat_phase_setup_env: library creates .artifact-env for Node" {
    mkdir -p harness
    local proj_dir
    proj_dir=$(mktemp -d)
    echo '{}' > "$proj_dir/package.json"
    uat_phase_setup_env "library" "$proj_dir" "" "" ""
    [ -f "harness/.artifact-env" ]
    local content
    content=$(cat harness/.artifact-env)
    [[ "$content" == *"NODE_PATH"* ]]
    [[ "$content" == *"$proj_dir/node_modules"* ]]
    rm -rf "$proj_dir"
}

@test "uat_phase_setup_env: library sets context about sourcing .artifact-env" {
    mkdir -p harness
    local proj_dir
    proj_dir=$(mktemp -d)
    touch "$proj_dir/setup.py"
    uat_phase_setup_env "library" "$proj_dir" "" "" ""
    [[ "$__UAT_ARTIFACT_CONTEXT" == *"source harness/.artifact-env"* ]]
    rm -rf "$proj_dir"
}

# ─────────────────────────────────────────────────────────────────────────────
# uat_phase_setup_env tests (Other type)
# ─────────────────────────────────────────────────────────────────────────────

@test "uat_phase_setup_env: other type sets error context" {
    mkdir -p harness
    uat_phase_setup_env "other" "/tmp" "" "" ""
    [[ "$__UAT_ARTIFACT_CONTEXT" == *"No artifact environment"* ]]
    [[ "$__UAT_ARTIFACT_CONTEXT" == *"UAT_ARTIFACT_TYPE"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# uat_phase_setup_env tests (install_command failure)
# ─────────────────────────────────────────────────────────────────────────────

@test "uat_phase_setup_env: CLI returns 2 on install_command failure" {
    mkdir -p harness
    local proj_dir
    proj_dir=$(mktemp -d)
    local rc=0
    uat_phase_setup_env "cli" "$proj_dir" "./bin/test" "false" "" || rc=$?
    [ "$rc" -eq 2 ]
    rm -rf "$proj_dir"
}

# ─────────────────────────────────────────────────────────────────────────────
# uat_phase_verdict tests
# ─────────────────────────────────────────────────────────────────────────────

@test "uat_phase_verdict: requires signal_dir and build_iteration" {
    run uat_phase_verdict "" ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"required"* ]]
}

@test "uat_phase_verdict: writes error verdict when results file missing" {
    local signal_dir
    signal_dir=$(mktemp -d)
    mkdir -p .buildcrew results/iteration-1
    # Do NOT create scenario-results.json
    # uat_phase_verdict returns 1 on error but still writes the verdict
    uat_phase_verdict "$signal_dir" "1" || true
    [ -f "$signal_dir/verdict.json" ]
    local status_val
    status_val=$(jq -r '.status' "$signal_dir/verdict.json")
    [ "$status_val" = "error" ]
    rm -rf "$signal_dir"
}

@test "uat_phase_verdict: writes error verdict for invalid scenario results" {
    local signal_dir
    signal_dir=$(mktemp -d)
    mkdir -p .buildcrew results/iteration-1
    echo "not json" > results/iteration-1/scenario-results.json
    # uat_phase_verdict returns 1 on error but still writes the verdict
    uat_phase_verdict "$signal_dir" "1" || true
    [ -f "$signal_dir/verdict.json" ]
    local status_val
    status_val=$(jq -r '.status' "$signal_dir/verdict.json")
    [ "$status_val" = "error" ]
    rm -rf "$signal_dir"
}

@test "uat_phase_verdict: writes correct verdict for passing scenarios" {
    local signal_dir
    signal_dir=$(mktemp -d)
    mkdir -p .buildcrew results/iteration-1
    cat > results/iteration-1/scenario-results.json << 'EOF'
[
    {"scenario": "Test 1", "status": "pass", "summary": "Passed"},
    {"scenario": "Test 2", "status": "pass", "summary": "Passed"}
]
EOF
    uat_phase_verdict "$signal_dir" "1"
    [ -f "$signal_dir/verdict.json" ]
    local status_val total passed
    status_val=$(jq -r '.status' "$signal_dir/verdict.json")
    total=$(jq -r '.total' "$signal_dir/verdict.json")
    passed=$(jq -r '.passed' "$signal_dir/verdict.json")
    [ "$status_val" = "pass" ]
    [ "$total" = "2" ]
    [ "$passed" = "2" ]
    rm -rf "$signal_dir"
}

@test "uat_phase_verdict: writes correct verdict for mixed results" {
    local signal_dir
    signal_dir=$(mktemp -d)
    mkdir -p .buildcrew results/iteration-2
    cat > results/iteration-2/scenario-results.json << 'EOF'
[
    {"scenario": "Test 1", "status": "pass", "summary": "OK"},
    {"scenario": "Test 2", "status": "fail", "summary": "Failed"},
    {"scenario": "Test 3", "status": "error", "summary": "Crashed"},
    {"scenario": "Test 4", "status": "disputed", "summary": "Ambiguous", "expected": "X", "actual": "Y"}
]
EOF
    uat_phase_verdict "$signal_dir" "2"
    [ -f "$signal_dir/verdict.json" ]
    local status_val total passed failed errored disputed build_iter
    status_val=$(jq -r '.status' "$signal_dir/verdict.json")
    total=$(jq -r '.total' "$signal_dir/verdict.json")
    passed=$(jq -r '.passed' "$signal_dir/verdict.json")
    failed=$(jq -r '.failed' "$signal_dir/verdict.json")
    errored=$(jq -r '.errored' "$signal_dir/verdict.json")
    disputed=$(jq -r '.disputed' "$signal_dir/verdict.json")
    build_iter=$(jq -r '.build_iteration' "$signal_dir/verdict.json")
    [ "$status_val" = "fail" ]  # fail outranks error/disputed
    [ "$total" = "4" ]
    [ "$passed" = "1" ]
    [ "$failed" = "1" ]
    [ "$errored" = "1" ]
    [ "$disputed" = "1" ]
    [ "$build_iter" = "2" ]
    rm -rf "$signal_dir"
}

@test "uat_phase_verdict: updates last_tested_iteration" {
    local signal_dir
    signal_dir=$(mktemp -d)
    mkdir -p .buildcrew results/iteration-3
    cat > results/iteration-3/scenario-results.json << 'EOF'
[{"scenario": "Test 1", "status": "pass", "summary": "OK"}]
EOF
    uat_phase_verdict "$signal_dir" "3"
    local last_iter
    last_iter=$(cat .buildcrew/last_tested_iteration)
    [ "$last_iter" = "3" ]
    rm -rf "$signal_dir"
}

@test "uat_phase_verdict: logs disputes to disputes.md" {
    local signal_dir
    signal_dir=$(mktemp -d)
    mkdir -p .buildcrew results/iteration-1
    cat > results/iteration-1/scenario-results.json << 'EOF'
[
    {"scenario": "Ambiguous test", "status": "disputed", "summary": "Unclear behavior", "expected": "Plain text", "actual": "JSON output"}
]
EOF
    uat_phase_verdict "$signal_dir" "1"
    [ -f "disputes.md" ]
    local content
    content=$(cat disputes.md)
    [[ "$content" == *"Ambiguous test"* ]]
    [[ "$content" == *"Plain text"* ]]
    [[ "$content" == *"JSON output"* ]]
    rm -rf "$signal_dir"
}

# ─────────────────────────────────────────────────────────────────────────────
# uat_stop_server tests
# ─────────────────────────────────────────────────────────────────────────────

@test "uat_stop_server: handles no pid file gracefully" {
    run uat_stop_server
    [ "$status" -eq 0 ]
}

@test "uat_stop_server: handles empty pid file" {
    mkdir -p harness
    echo "" > harness/.artifact-pid
    run uat_stop_server
    [ "$status" -eq 0 ]
    [ ! -f "harness/.artifact-pid" ]
}

@test "uat_stop_server: handles stale PID (process not running)" {
    mkdir -p harness
    echo "999999" > harness/.artifact-pid
    run uat_stop_server
    [ "$status" -eq 0 ]
    [ ! -f "harness/.artifact-pid" ]
}

@test "uat_stop_server: stops a running process" {
    mkdir -p harness
    # Start a background sleep
    /bin/sleep 300 &
    local pid=$!
    echo "$pid" > harness/.artifact-pid
    # Verify it's running
    kill -0 "$pid" 2>/dev/null
    # Temporarily clear stop command so it uses direct kill (not process group)
    local saved_stop="${__UAT_STOP_COMMAND:-}"
    __UAT_STOP_COMMAND='kill $PID'
    uat_stop_server
    __UAT_STOP_COMMAND="$saved_stop"
    # Verify pid file is cleaned up
    [ ! -f "harness/.artifact-pid" ]
    # Cleanup in case still running
    kill "$pid" 2>/dev/null || true
}

@test "uat_stop_server: clears __UAT_SERVER_PID" {
    mkdir -p harness
    __UAT_SERVER_PID="12345"
    echo "" > harness/.artifact-pid
    uat_stop_server
    [ -z "$__UAT_SERVER_PID" ]
}

@test "uat_stop_server: uses stop_command with PID substitution" {
    mkdir -p harness
    # Start a background process
    /bin/sleep 300 &
    local pid=$!
    echo "$pid" > harness/.artifact-pid
    __UAT_STOP_COMMAND='kill $PID'
    uat_stop_server
    [ ! -f "harness/.artifact-pid" ]
    # Cleanup in case still running
    kill "$pid" 2>/dev/null || true
    __UAT_STOP_COMMAND=""
}

# ─────────────────────────────────────────────────────────────────────────────
# uat_cleanup tests
# ─────────────────────────────────────────────────────────────────────────────

@test "uat_cleanup: runs without error when nothing to clean" {
    run uat_cleanup
    [ "$status" -eq 0 ]
}

@test "uat_cleanup: stops file monitor" {
    start_file_monitor "/nonexistent/file" "nonexistent-pattern"
    [ -n "$__MONITOR_PID" ]
    uat_cleanup
    [ -z "$__MONITOR_PID" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# uat_phase_wait_artifact tests (with controlled timeout)
# ─────────────────────────────────────────────────────────────────────────────

@test "uat_phase_wait_artifact: requires project_name" {
    run uat_phase_wait_artifact ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"required"* ]]
}

@test "uat_phase_wait_artifact: finds existing manifest immediately" {
    local project="test-wait-$$"
    local artifact_dir="$HOME/.buildcrew/artifacts/$project"
    mkdir -p "$artifact_dir" .buildcrew
    # Set last_tested_iteration to 0
    echo "0" > .buildcrew/last_tested_iteration
    cat > "$artifact_dir/manifest.json" << EOF
{
    "project": "$project",
    "artifact_type": "cli",
    "artifact_path": "/tmp/test",
    "run_command": "./bin/test",
    "install_command": "",
    "health_check": "",
    "stop_command": "",
    "build_timestamp": "2024-01-01T00:00:00Z",
    "build_iteration": 1,
    "readme_hash": "abc123"
}
EOF
    UAT_POLL_INTERVAL=1
    UAT_ARTIFACT_TIMEOUT=3
    uat_phase_wait_artifact "$project"
    [ "$__UAT_ARTIFACT_TYPE" = "cli" ]
    [ "$__UAT_BUILD_ITERATION" = "1" ]
    # Cleanup
    rm -rf "$artifact_dir"
}

@test "uat_phase_wait_artifact: skips already-tested iteration" {
    local project="test-skip-$$"
    local artifact_dir="$HOME/.buildcrew/artifacts/$project"
    mkdir -p "$artifact_dir" .buildcrew
    # Set last_tested_iteration to 1 (already tested)
    echo "1" > .buildcrew/last_tested_iteration
    cat > "$artifact_dir/manifest.json" << EOF
{
    "project": "$project",
    "artifact_type": "cli",
    "artifact_path": "/tmp/test",
    "run_command": "./bin/test",
    "install_command": "",
    "health_check": "",
    "stop_command": "",
    "build_timestamp": "2024-01-01T00:00:00Z",
    "build_iteration": 1,
    "readme_hash": "abc123"
}
EOF
    UAT_POLL_INTERVAL=1
    UAT_ARTIFACT_TIMEOUT=3
    run uat_phase_wait_artifact "$project"
    [ "$status" -eq 1 ]
    [[ "$output" == *"timeout"* ]] || [[ "$output" == *"Artifact not published"* ]]
    # Cleanup
    rm -rf "$artifact_dir"
}

@test "uat_phase_wait_artifact: times out when no manifest" {
    local project="test-timeout-$$"
    UAT_POLL_INTERVAL=1
    UAT_ARTIFACT_TIMEOUT=2
    mkdir -p .buildcrew
    run uat_phase_wait_artifact "$project"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Artifact not published"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# uat_phase_setup_env: CLI fallback to scanning bin/
# ─────────────────────────────────────────────────────────────────────────────

@test "uat_phase_setup_env: CLI scans bin/ when no run_command" {
    mkdir -p harness
    local proj_dir
    proj_dir=$(mktemp -d)
    mkdir -p "$proj_dir/bin"
    echo '#!/bin/bash' > "$proj_dir/bin/mytool"
    chmod +x "$proj_dir/bin/mytool"
    uat_phase_setup_env "cli" "$proj_dir" "" "" ""
    [ -f "harness/.artifact-bin/mytool" ]
    [ -x "harness/.artifact-bin/mytool" ]
    rm -rf "$proj_dir"
}

# ─────────────────────────────────────────────────────────────────────────────
# uat_phase_setup_env: absolute path wrapper
# ─────────────────────────────────────────────────────────────────────────────

@test "uat_phase_setup_env: CLI creates wrapper for absolute binary path" {
    mkdir -p harness
    uat_phase_setup_env "cli" "/tmp/project" "/usr/local/bin/myapp" "" ""
    [ -f "harness/.artifact-bin/myapp" ]
    local content
    content=$(cat harness/.artifact-bin/myapp)
    [[ "$content" == *"/usr/local/bin/myapp"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Integration-style: uat_init followed by checking state
# ─────────────────────────────────────────────────────────────────────────────

@test "uat_init: full initialization creates complete structure" {
    local src_dir
    src_dir=$(mktemp -d)
    create_test_readme "$src_dir"

    uat_init "$src_dir/README.md" "full-test-$$"

    # Check all expected artifacts
    [ -d ".buildcrew" ]
    [ -f ".buildcrew/CLAUDE.md" ]
    [ -f ".buildcrew/last_readme_hash" ]
    [ -d "scenarios" ]
    [ -d "harness" ]
    [ -d "results" ]
    [ -f "README.md" ]
    [ -d "$HOME/.buildcrew/uat-signals/full-test-$$" ]

    # Verify README content was copied
    [[ "$(cat README.md)" == *"Test Project"* ]]

    # Verify hash is valid
    local hash
    hash=$(cat .buildcrew/last_readme_hash)
    [[ ${#hash} -eq 64 ]]

    # Cleanup
    rm -rf "$src_dir" "$HOME/.buildcrew/uat-signals/full-test-$$"
}

# ─────────────────────────────────────────────────────────────────────────────
# _uat_run_agent_phase tests (mocked Claude)
# ─────────────────────────────────────────────────────────────────────────────

@test "_uat_run_agent_phase: handles missing skill file gracefully" {
    # Create a mock claude that writes phase-result.json
    mkdir -p "$TEST_DIR/bin" .claude
    cat > "$TEST_DIR/bin/claude" << 'MOCK_EOF'
#!/bin/bash
mkdir -p .claude
echo '{"phase":"uat-stories","verdict":"pass","details":"Test"}' > .claude/phase-result.json
MOCK_EOF
    chmod +x "$TEST_DIR/bin/claude"
    export PATH="$TEST_DIR/bin:$PATH"

    run _uat_run_agent_phase "uat-stories" "test task" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"pass"* ]]
}

@test "_uat_run_agent_phase: returns 1 on fail verdict" {
    mkdir -p "$TEST_DIR/bin" .claude
    cat > "$TEST_DIR/bin/claude" << 'MOCK_EOF'
#!/bin/bash
mkdir -p .claude
echo '{"phase":"uat-stories","verdict":"fail","details":"README too vague"}' > .claude/phase-result.json
MOCK_EOF
    chmod +x "$TEST_DIR/bin/claude"
    export PATH="$TEST_DIR/bin:$PATH"

    run _uat_run_agent_phase "uat-stories" "test task" ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"fail"* ]]
}

@test "_uat_run_agent_phase: retries when first attempt produces no result" {
    mkdir -p "$TEST_DIR/bin" .claude
    local flag_file="/tmp/uat-retry-flag-${BATS_TEST_NUMBER}-$$"
    rm -f "$flag_file"
    # First call: no result file. Second call: writes result.
    cat > "$TEST_DIR/bin/claude" << MOCK_EOF
#!/bin/bash
if [ -f "$flag_file" ]; then
    mkdir -p .claude
    echo '{"phase":"uat-stories","verdict":"pass","details":"OK"}' > .claude/phase-result.json
else
    touch "$flag_file"
fi
MOCK_EOF
    chmod +x "$TEST_DIR/bin/claude"
    export PATH="$TEST_DIR/bin:$PATH"

    run _uat_run_agent_phase "uat-stories" "test task" ""
    [ "$status" -eq 0 ]
    rm -f "$flag_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# Configuration defaults
# ─────────────────────────────────────────────────────────────────────────────

@test "UAT config defaults are set correctly" {
    # Reset to defaults by re-sourcing (source guard prevents, so check current)
    [ -n "$UAT_POLL_INTERVAL" ]
    [ "$UAT_ARTIFACT_TIMEOUT" = "7200" ]
    [ -n "$UAT_EXECUTE_TIMEOUT" ]
    [ -n "$UAT_HEALTH_CHECK_TIMEOUT" ]
    [ -n "$UAT_MAX_RETRIES" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# _uat_format_duration tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_uat_format_duration: formats seconds-only for < 60s" {
    run _uat_format_duration 45
    [ "$status" -eq 0 ]
    [ "$output" = "45s" ]
}

@test "_uat_format_duration: formats Xm YYs for 60-3599s" {
    run _uat_format_duration 83
    [ "$status" -eq 0 ]
    [ "$output" = "1m 23s" ]
}

@test "_uat_format_duration: formats Xh YYm ZZs for >= 3600s" {
    run _uat_format_duration 3661
    [ "$status" -eq 0 ]
    [ "$output" = "1h 01m 01s" ]
}

@test "_uat_format_duration: handles zero -> 0s" {
    run _uat_format_duration 0
    [ "$status" -eq 0 ]
    [ "$output" = "0s" ]
}

@test "_uat_format_duration: handles non-numeric input -> ?" {
    run _uat_format_duration "abc"
    [ "$status" -eq 0 ]
    [ "$output" = "?" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# _uat_list_scenarios tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_uat_list_scenarios: lists scenarios from files" {
    mkdir -p scenarios
    cat > scenarios/login.md << 'EOF'
## Scenario: User logs in successfully
Steps here...

## Scenario: User fails login with bad password
Steps here...
EOF
    cat > scenarios/signup.md << 'EOF'
## Scenario: User creates account
Steps here...
EOF
    run _uat_list_scenarios
    [ "$status" -eq 0 ]
    [[ "$output" == *"1. User logs in successfully"* ]]
    [[ "$output" == *"2. User fails login with bad password"* ]]
    [[ "$output" == *"3. User creates account"* ]]
    [[ "$output" == *"Total: 3 scenarios"* ]]
}

@test "_uat_list_scenarios: skips user-stories.md" {
    mkdir -p scenarios
    cat > scenarios/user-stories.md << 'EOF'
## Scenario: This should be skipped
EOF
    cat > scenarios/login.md << 'EOF'
## Scenario: User logs in
EOF
    run _uat_list_scenarios
    [ "$status" -eq 0 ]
    [[ "$output" == *"User logs in"* ]]
    [[ "$output" != *"This should be skipped"* ]]
    [[ "$output" == *"Total: 1 scenarios"* ]]
}

@test "_uat_list_scenarios: handles no scenario files" {
    mkdir -p scenarios
    # Only user-stories.md, no actual scenario files
    cat > scenarios/user-stories.md << 'EOF'
## Scenario: Ignored
EOF
    run _uat_list_scenarios
    [ "$status" -eq 0 ]
    [[ "$output" == *"No scenarios found"* ]]
}

@test "_uat_list_scenarios: handles files with no Scenario headers" {
    mkdir -p scenarios
    cat > scenarios/notes.md << 'EOF'
# Some notes
No scenario headers here.
EOF
    run _uat_list_scenarios
    [ "$status" -eq 0 ]
    [[ "$output" == *"No scenarios found"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# _uat_print_scenario_table tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_uat_print_scenario_table: prints pass/fail/error/disputed with correct labels" {
    local json='[
        {"scenario":"Test A","status":"pass","summary":"OK"},
        {"scenario":"Test B","status":"fail","summary":"Wrong output"},
        {"scenario":"Test C","status":"error","summary":"Crashed"},
        {"scenario":"Test D","status":"disputed","summary":"Ambiguous"}
    ]'
    run _uat_print_scenario_table "$json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"ERR"* ]]
    [[ "$output" == *"DISP"* ]]
    [[ "$output" == *"Test A"* ]]
    [[ "$output" == *"Test B"* ]]
    [[ "$output" == *"Wrong output"* ]]
    [[ "$output" == *"Crashed"* ]]
    [[ "$output" == *"Ambiguous"* ]]
}

@test "_uat_print_scenario_table: handles empty JSON array" {
    run _uat_print_scenario_table "[]"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No scenario results"* ]]
}

@test "_uat_print_scenario_table: handles null/missing summary field" {
    local json='[{"scenario":"Test X","status":"fail","summary":null}]'
    run _uat_print_scenario_table "$json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test X"* ]]
    [[ "$output" == *"FAIL"* ]]
}

@test "_uat_print_scenario_table: truncates long summaries at 80 chars" {
    local long_summary
    long_summary=$(printf 'A%.0s' {1..100})
    local json="[{\"scenario\":\"Test Long\",\"status\":\"fail\",\"summary\":\"${long_summary}\"}]"
    run _uat_print_scenario_table "$json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"..."* ]]
    # The summary line should not contain all 100 A's
    [[ "$output" != *"${long_summary}"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# _uat_print_retry_context tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_uat_print_retry_context: shows failing scenarios from JSON arg" {
    local json='[
        {"scenario":"Test A","status":"pass","summary":"OK"},
        {"scenario":"Test B","status":"fail","summary":"Wrong output"},
        {"scenario":"Test C","status":"error","summary":"Timeout"}
    ]'
    run _uat_print_retry_context "$json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Scenarios to retry"* ]]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"Test B"* ]]
    [[ "$output" == *"Wrong output"* ]]
    [[ "$output" == *"ERR"* ]]
    [[ "$output" == *"Test C"* ]]
    [[ "$output" == *"Timeout"* ]]
    # Should NOT include passing scenarios
    [[ "$output" != *"Test A"* ]]
}

@test "_uat_print_retry_context: skips disputed-only" {
    local json='[
        {"scenario":"Test A","status":"pass","summary":"OK"},
        {"scenario":"Test B","status":"disputed","summary":"Ambiguous"}
    ]'
    run _uat_print_retry_context "$json"
    [ "$status" -eq 0 ]
    # No fail/error entries, so no output
    [[ "$output" != *"Scenarios to retry"* ]]
}

@test "_uat_print_retry_context: handles empty input" {
    run _uat_print_retry_context "[]"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# _uat_print_report tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_uat_print_report: prints structured report from verdict on disk" {
    local signal_dir
    signal_dir=$(mktemp -d)
    # Write a verdict file directly
    cat > "$signal_dir/verdict.json" << 'EOF'
{
    "status": "fail",
    "total": 3,
    "passed": 1,
    "failed": 1,
    "errored": 0,
    "disputed": 1,
    "build_iteration": 2,
    "scenarios": [
        {"scenario":"Test A","status":"pass","summary":"OK"},
        {"scenario":"Test B","status":"fail","summary":"Bad output"},
        {"scenario":"Test C","status":"disputed","summary":"Ambiguous"}
    ]
}
EOF
    local start_time
    start_time=$(date +%s)
    run _uat_print_report "$signal_dir" "$start_time"
    [ "$status" -eq 0 ]
    [[ "$output" == *"UAT Report"* ]]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"Iteration:  2"* ]]
    [[ "$output" == *"Passed:   1"* ]]
    [[ "$output" == *"Failed:   1"* ]]
    [[ "$output" == *"Disputed: 1"* ]]
    [[ "$output" == *"Total:    3"* ]]
    [[ "$output" == *"Test A"* ]]
    [[ "$output" == *"Test B"* ]]
    [[ "$output" == *"disputes.md"* ]]
    rm -rf "$signal_dir"
}

@test "_uat_print_report: handles missing signal dir gracefully" {
    run _uat_print_report "/nonexistent/dir" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not read verdict"* ]]
}

@test "_uat_print_report: omits duration when run_start_time is empty" {
    local signal_dir
    signal_dir=$(mktemp -d)
    cat > "$signal_dir/verdict.json" << 'EOF'
{
    "status": "pass",
    "total": 1,
    "passed": 1,
    "failed": 0,
    "errored": 0,
    "disputed": 0,
    "build_iteration": 1,
    "scenarios": [{"scenario":"Test A","status":"pass","summary":"OK"}]
}
EOF
    run _uat_print_report "$signal_dir" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"UAT Report"* ]]
    [[ "$output" != *"Duration:"* ]]
    rm -rf "$signal_dir"
}
