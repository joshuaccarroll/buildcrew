#!/usr/bin/env bats
# Unit tests for TDD mode (tdd-scaffold phase)

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# get_phase_max_turns: tdd-scaffold
# ─────────────────────────────────────────────────────────────────────────────

@test "get_phase_max_turns: tdd-scaffold returns 40" {
    run get_phase_max_turns "tdd-scaffold"
    [ "$output" = "40" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# parse_args: --tdd and --no-tdd are unknown options
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --tdd is rejected as unknown option" {
    run parse_args --tdd
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option: --tdd"* ]]
}

@test "parse_args: --no-tdd is rejected as unknown option" {
    run parse_args --no-tdd
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option: --no-tdd"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# ARTIFACT_FILES includes tdd-manifest.json
# ─────────────────────────────────────────────────────────────────────────────

@test "ARTIFACT_FILES includes tdd-manifest.json" {
    local found=false
    local f
    for f in "${ARTIFACT_FILES[@]}"; do
        if [[ "$f" == *"tdd-manifest.json"* ]]; then
            found=true
            break
        fi
    done
    [ "$found" = "true" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# __inject_tdd_prompt tests
# ─────────────────────────────────────────────────────────────────────────────

@test "__inject_tdd_prompt: returns prompt unchanged when manifest missing" {
    # No .claude/tdd-manifest.json exists
    local result
    result=$(__inject_tdd_prompt "build" "original prompt")
    [ "$result" = "original prompt" ]
}

@test "__inject_tdd_prompt: returns prompt unchanged for non-build/test/codereview phases" {
    mkdir -p .claude
    echo '{"test_count": 5}' > .claude/tdd-manifest.json
    local result
    result=$(__inject_tdd_prompt "spec" "original prompt")
    [ "$result" = "original prompt" ]
}

@test "__inject_tdd_prompt: appends TDD context for build phase" {
    mkdir -p .claude
    echo '{"test_count": 5}' > .claude/tdd-manifest.json
    local result
    result=$(__inject_tdd_prompt "build" "original prompt")
    [[ "$result" == "original prompt"* ]]
    [[ "$result" == *"TDD MODE: 5 failing tests exist"* ]]
    [[ "$result" == *"Do NOT modify TDD test files"* ]]
}

@test "__inject_tdd_prompt: appends TDD context for test phase" {
    mkdir -p .claude
    echo '{"test_count": 3}' > .claude/tdd-manifest.json
    local result
    result=$(__inject_tdd_prompt "test" "original prompt")
    [[ "$result" == "original prompt"* ]]
    [[ "$result" == *"TDD VALIDATION MODE"* ]]
    [[ "$result" == *"openssl dgst -sha256"* ]]
}

@test "__inject_tdd_prompt: appends TDD context for codereview phase" {
    mkdir -p .claude
    echo '{"test_count": 4}' > .claude/tdd-manifest.json
    local result
    result=$(__inject_tdd_prompt "codereview" "original prompt")
    [[ "$result" == "original prompt"* ]]
    [[ "$result" == *"TDD MODE ACTIVE"* ]]
    [[ "$result" == *"tdd-scaffold phase"* ]]
}

@test "__inject_tdd_prompt: returns prompt unchanged when test_count is 0" {
    mkdir -p .claude
    echo '{"test_count": 0}' > .claude/tdd-manifest.json
    local result
    result=$(__inject_tdd_prompt "build" "original prompt")
    [ "$result" = "original prompt" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# __cleanup_tdd_artifacts tests
# ─────────────────────────────────────────────────────────────────────────────

@test "__cleanup_tdd_artifacts: no-op when manifest missing" {
    # No manifest file
    __cleanup_tdd_artifacts
    # Should exit cleanly with no error
}

@test "__cleanup_tdd_artifacts: removes test dir and manifest" {
    mkdir -p .claude tests/tdd
    echo "test content" > tests/tdd/test_ac01.test.ts
    echo "test content 2" > tests/tdd/test_ac02.test.ts
    cat > .claude/tdd-manifest.json << 'EOF'
{"test_dir": "tests/tdd", "test_files": ["tests/tdd/test_ac01.test.ts", "tests/tdd/test_ac02.test.ts"], "stub_files": []}
EOF
    __cleanup_tdd_artifacts
    [ ! -d "tests/tdd" ]
    [ ! -f ".claude/tdd-manifest.json" ]
}

@test "__cleanup_tdd_artifacts: removes stub files" {
    mkdir -p .claude src
    echo "stub" > src/feature.ts
    cat > .claude/tdd-manifest.json << 'EOF'
{"test_dir": "tests/tdd", "test_files": [], "stub_files": ["src/feature.ts"]}
EOF
    __cleanup_tdd_artifacts
    [ ! -f "src/feature.ts" ]
    [ ! -f ".claude/tdd-manifest.json" ]
}

@test "__cleanup_tdd_artifacts: handles missing test_dir gracefully" {
    mkdir -p .claude
    cat > .claude/tdd-manifest.json << 'EOF'
{"test_dir": "tests/tdd", "test_files": [], "stub_files": []}
EOF
    # tests/tdd doesn't exist — should not error
    __cleanup_tdd_artifacts
    [ ! -f ".claude/tdd-manifest.json" ]
}
