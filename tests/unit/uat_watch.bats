#!/usr/bin/env bats
# Unit tests for UAT watch mode (--uat flag on buildcrew run)
# Tests the enter_uat_watch_mode() function in lib/workflow.sh

load '../setup.bash'

setup() {
    setup_test_dir

    # Source libraries needed for watch mode
    source_lib "common.sh"
    source_lib "uat_signal.sh"
    source_lib "artifact.sh"

    # Create minimal .buildcrew directory
    mkdir -p .buildcrew

    # Create a minimal README.md for artifact publishing
    echo "# Test Project" > README.md

    # Create BACKLOG.md (required by workflow.sh sourcing)
    echo "- [ ] Test task" > BACKLOG.md

    # Set up required variables that workflow.sh expects
    export PHASE_RESULT_FILE=".claude/phase-result.json"
    export STATUS_FILE=".claude/workflow-status.json"
    export STOP_FILE=".buildcrew/.stop-workflow"
    export LOCKFILE=".buildcrew/.workflow-lock"
    export VERBOSE=false
    export AUTO_MODE=true
    export UAT_MODE=true
    export COMPLEXITY_AWARE=true
    export MAX_INVOCATIONS=15
    export MAX_PARALLEL=5
    export BATCH_MODE=false
    export DRY_RUN=false
    export SINGLE_TASK=false
    export HUMAN_REVIEW=false
    export GIT_BRANCH=false
    export RESUME_MODE=false
    export TARGET_TASK=""
    export SKIP_SPEC=false
    export STRICT_MODE=true
    export STRICT_EXPLICIT=false
    export FULL_PIPELINE=false
    export PLAN_MODE=false

    # Source workflow.sh (needs the variables above to be set)
    source_lib "workflow.sh"
}

teardown() {
    # Clean up artifact and signal dirs
    rm -rf "$HOME/.buildcrew/artifacts/test-project" 2>/dev/null || true
    rm -rf "$HOME/.buildcrew/uat-signals/test-project" 2>/dev/null || true
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# parse_args --uat flag tests
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --uat sets UAT_MODE=true" {
    UAT_MODE=false
    AUTO_MODE=false
    parse_args --uat
    [ "$UAT_MODE" = "true" ]
}

@test "parse_args: --uat implies AUTO_MODE=true" {
    UAT_MODE=false
    AUTO_MODE=false
    parse_args --uat
    [ "$AUTO_MODE" = "true" ]
}

@test "parse_args: --uat can combine with --single" {
    UAT_MODE=false
    SINGLE_TASK=false
    parse_args --uat --single
    [ "$UAT_MODE" = "true" ]
    [ "$SINGLE_TASK" = "true" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# enter_uat_watch_mode — verdict status=pass
# ─────────────────────────────────────────────────────────────────────────────

@test "enter_uat_watch_mode: exits 0 on pass verdict" {
    local project="test-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/$project"
    local artifact_dir="$HOME/.buildcrew/artifacts/$project"

    mkdir -p "$signal_dir" "$artifact_dir"

    # Pre-create a manifest so publish_artifact can increment
    cat > "$artifact_dir/manifest.json" << 'EOF'
{
  "project": "test-project",
  "artifact_type": "cli",
  "artifact_path": "/tmp/test",
  "run_command": "./bin/test",
  "install_command": "",
  "health_check": "",
  "stop_command": "",
  "build_timestamp": "2024-01-01T00:00:00Z",
  "build_iteration": 0,
  "readme_hash": "abc123"
}
EOF

    # Write a pass verdict that will match iteration 1 (after publish_artifact increments from 0)
    cat > "$signal_dir/verdict.json" << 'EOF'
{
  "timestamp": "2024-01-01T12:00:00Z",
  "status": "pass",
  "build_iteration": 1,
  "total": 3,
  "passed": 3,
  "failed": 0,
  "errored": 0,
  "disputed": 0,
  "scenarios": [
    {"scenario": "Test 1", "status": "pass", "summary": "Passed"},
    {"scenario": "Test 2", "status": "pass", "summary": "Passed"},
    {"scenario": "Test 3", "status": "pass", "summary": "Passed"}
  ]
}
EOF

    run enter_uat_watch_mode "$project" "Test task" "standard"
    [ "$status" -eq 0 ]
}

@test "enter_uat_watch_mode: prints success message on pass" {
    local project="test-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/$project"
    local artifact_dir="$HOME/.buildcrew/artifacts/$project"

    mkdir -p "$signal_dir" "$artifact_dir"

    cat > "$artifact_dir/manifest.json" << 'EOF'
{
  "project": "test-project",
  "artifact_type": "cli",
  "artifact_path": "/tmp/test",
  "run_command": "./bin/test",
  "install_command": "",
  "health_check": "",
  "stop_command": "",
  "build_timestamp": "2024-01-01T00:00:00Z",
  "build_iteration": 0,
  "readme_hash": "abc123"
}
EOF

    cat > "$signal_dir/verdict.json" << 'EOF'
{
  "timestamp": "2024-01-01T12:00:00Z",
  "status": "pass",
  "build_iteration": 1,
  "total": 2,
  "passed": 2,
  "failed": 0,
  "errored": 0,
  "disputed": 0,
  "scenarios": [
    {"scenario": "Test 1", "status": "pass", "summary": "Passed"},
    {"scenario": "Test 2", "status": "pass", "summary": "Passed"}
  ]
}
EOF

    run enter_uat_watch_mode "$project" "Test task" "standard"
    [[ "$output" == *"All 2 scenarios passed"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# enter_uat_watch_mode — verdict status=disputed
# ─────────────────────────────────────────────────────────────────────────────

@test "enter_uat_watch_mode: exits 2 on disputed in auto mode" {
    local project="test-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/$project"
    local artifact_dir="$HOME/.buildcrew/artifacts/$project"

    mkdir -p "$signal_dir" "$artifact_dir"

    cat > "$artifact_dir/manifest.json" << 'EOF'
{
  "project": "test-project",
  "artifact_type": "cli",
  "artifact_path": "/tmp/test",
  "run_command": "./bin/test",
  "install_command": "",
  "health_check": "",
  "stop_command": "",
  "build_timestamp": "2024-01-01T00:00:00Z",
  "build_iteration": 0,
  "readme_hash": "abc123"
}
EOF

    cat > "$signal_dir/verdict.json" << 'EOF'
{
  "timestamp": "2024-01-01T12:00:00Z",
  "status": "disputed",
  "build_iteration": 1,
  "total": 2,
  "passed": 1,
  "failed": 0,
  "errored": 0,
  "disputed": 1,
  "scenarios": [
    {"scenario": "Test 1", "status": "pass", "summary": "Passed"},
    {"scenario": "Test 2", "status": "disputed", "summary": "Ambiguous behavior"}
  ]
}
EOF

    AUTO_MODE=true
    run enter_uat_watch_mode "$project" "Test task" "standard"
    [ "$status" -eq 2 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# enter_uat_watch_mode — timeout
# ─────────────────────────────────────────────────────────────────────────────

@test "enter_uat_watch_mode: times out when no verdict appears" {
    local project="test-project"
    local artifact_dir="$HOME/.buildcrew/artifacts/$project"

    mkdir -p "$artifact_dir"

    cat > "$artifact_dir/manifest.json" << 'EOF'
{
  "project": "test-project",
  "artifact_type": "cli",
  "artifact_path": "/tmp/test",
  "run_command": "./bin/test",
  "install_command": "",
  "health_check": "",
  "stop_command": "",
  "build_timestamp": "2024-01-01T00:00:00Z",
  "build_iteration": 0,
  "readme_hash": "abc123"
}
EOF

    # Set very short timeout so test completes quickly
    BUILD_UAT_WATCH_TIMEOUT=2

    run enter_uat_watch_mode "$project" "Test task" "standard"
    [ "$status" -eq 1 ]
    [[ "$output" == *"timed out"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# enter_uat_watch_mode — iteration mismatch
# ─────────────────────────────────────────────────────────────────────────────

@test "enter_uat_watch_mode: skips verdict with mismatched iteration" {
    local project="test-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/$project"
    local artifact_dir="$HOME/.buildcrew/artifacts/$project"

    mkdir -p "$signal_dir" "$artifact_dir"

    cat > "$artifact_dir/manifest.json" << 'EOF'
{
  "project": "test-project",
  "artifact_type": "cli",
  "artifact_path": "/tmp/test",
  "run_command": "./bin/test",
  "install_command": "",
  "health_check": "",
  "stop_command": "",
  "build_timestamp": "2024-01-01T00:00:00Z",
  "build_iteration": 0,
  "readme_hash": "abc123"
}
EOF

    # Write a verdict for iteration 99 (mismatched — we'll publish iteration 1)
    cat > "$signal_dir/verdict.json" << 'EOF'
{
  "timestamp": "2024-01-01T12:00:00Z",
  "status": "pass",
  "build_iteration": 99,
  "total": 1,
  "passed": 1,
  "failed": 0,
  "errored": 0,
  "disputed": 0,
  "scenarios": [{"scenario": "Test 1", "status": "pass", "summary": "Passed"}]
}
EOF

    # Short timeout so it exits after skipping the mismatched verdict
    BUILD_UAT_WATCH_TIMEOUT=3

    run enter_uat_watch_mode "$project" "Test task" "standard"
    # Should time out because the verdict iteration doesn't match
    [ "$status" -eq 1 ]
    [[ "$output" == *"timed out"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# enter_uat_watch_mode — stop signal
# ─────────────────────────────────────────────────────────────────────────────

@test "enter_uat_watch_mode: exits on stop signal" {
    local project="test-project"
    local artifact_dir="$HOME/.buildcrew/artifacts/$project"

    mkdir -p "$artifact_dir" .buildcrew

    cat > "$artifact_dir/manifest.json" << 'EOF'
{
  "project": "test-project",
  "artifact_type": "cli",
  "artifact_path": "/tmp/test",
  "run_command": "./bin/test",
  "install_command": "",
  "health_check": "",
  "stop_command": "",
  "build_timestamp": "2024-01-01T00:00:00Z",
  "build_iteration": 0,
  "readme_hash": "abc123"
}
EOF

    # Create stop file
    touch "$STOP_FILE"

    BUILD_UAT_WATCH_TIMEOUT=10

    run enter_uat_watch_mode "$project" "Test task" "standard"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stop signal received"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# enter_uat_watch_mode — already processed iteration
# ─────────────────────────────────────────────────────────────────────────────

@test "enter_uat_watch_mode: skips already-processed iterations" {
    local project="test-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/$project"
    local artifact_dir="$HOME/.buildcrew/artifacts/$project"

    mkdir -p "$signal_dir" "$artifact_dir"

    cat > "$artifact_dir/manifest.json" << 'EOF'
{
  "project": "test-project",
  "artifact_type": "cli",
  "artifact_path": "/tmp/test",
  "run_command": "./bin/test",
  "install_command": "",
  "health_check": "",
  "stop_command": "",
  "build_timestamp": "2024-01-01T00:00:00Z",
  "build_iteration": 0,
  "readme_hash": "abc123"
}
EOF

    # Mark iteration 1 as already processed
    echo "1" > .buildcrew/last_processed_uat_iteration

    # Write a verdict for iteration 1 (already processed)
    cat > "$signal_dir/verdict.json" << 'EOF'
{
  "timestamp": "2024-01-01T12:00:00Z",
  "status": "pass",
  "build_iteration": 1,
  "total": 1,
  "passed": 1,
  "failed": 0,
  "errored": 0,
  "disputed": 0,
  "scenarios": [{"scenario": "Test 1", "status": "pass", "summary": "Passed"}]
}
EOF

    BUILD_UAT_WATCH_TIMEOUT=3

    run enter_uat_watch_mode "$project" "Test task" "standard"
    # Should time out because the verdict was already processed
    [ "$status" -eq 1 ]
    [[ "$output" == *"timed out"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# enter_uat_watch_mode — publish artifact
# ─────────────────────────────────────────────────────────────────────────────

@test "enter_uat_watch_mode: publishes artifact on entry" {
    local project="test-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/$project"
    local artifact_dir="$HOME/.buildcrew/artifacts/$project"

    mkdir -p "$signal_dir"

    # Write a pass verdict for iteration 1
    cat > "$signal_dir/verdict.json" << 'EOF'
{
  "timestamp": "2024-01-01T12:00:00Z",
  "status": "pass",
  "build_iteration": 1,
  "total": 1,
  "passed": 1,
  "failed": 0,
  "errored": 0,
  "disputed": 0,
  "scenarios": [{"scenario": "Test 1", "status": "pass", "summary": "Passed"}]
}
EOF

    run enter_uat_watch_mode "$project" "Test task" "standard"
    [ "$status" -eq 0 ]

    # Verify manifest was published
    [ -f "$artifact_dir/manifest.json" ]
    local pub_project
    pub_project=$(jq -r '.project' "$artifact_dir/manifest.json")
    [ "$pub_project" = "test-project" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# enter_uat_watch_mode — signal directory creation
# ─────────────────────────────────────────────────────────────────────────────

@test "enter_uat_watch_mode: creates signal directory" {
    local project="test-project"
    local signal_dir="$HOME/.buildcrew/uat-signals/$project"

    # Ensure signal dir does not exist beforehand
    rm -rf "$signal_dir" 2>/dev/null || true

    # Pre-create the pass verdict (will be written after signal dir is created)
    # We need to do this in a way that the verdict appears after the function creates the dir
    # So instead, use stop signal for a quick exit
    mkdir -p .buildcrew
    touch "$STOP_FILE"

    BUILD_UAT_WATCH_TIMEOUT=10

    run enter_uat_watch_mode "$project" "Test task" "standard"

    # Verify signal directory was created
    [ -d "$signal_dir" ]
}
