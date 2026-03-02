#!/usr/bin/env bats
# Unit tests for TDD mode (--tdd flag, tdd-scaffold phase)

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
# parse_args: --tdd flag
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --tdd sets TDD_MODE=true" {
    TDD_MODE=false
    parse_args --tdd
    [ "$TDD_MODE" = "true" ]
}

@test "parse_args: TDD_MODE defaults to false" {
    [ "$TDD_MODE" = "false" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# load_buildcrew_config: TDD_MODE
# ─────────────────────────────────────────────────────────────────────────────

@test "load_buildcrew_config: loads TDD_MODE=true from config" {
    mkdir -p .buildcrew
    echo "TDD_MODE=true" > .buildcrew/config
    unset TDD_MODE
    load_buildcrew_config
    [ "$TDD_MODE" = "true" ]
}

@test "load_buildcrew_config: loads TDD_MODE=false from config" {
    mkdir -p .buildcrew
    echo "TDD_MODE=false" > .buildcrew/config
    unset TDD_MODE
    load_buildcrew_config
    [ "$TDD_MODE" = "false" ]
}

@test "load_buildcrew_config: rejects invalid TDD_MODE value" {
    mkdir -p .buildcrew
    echo "TDD_MODE=maybe" > .buildcrew/config
    unset TDD_MODE
    run load_buildcrew_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"invalid TDD_MODE"* ]]
}

@test "load_buildcrew_config: env var TDD_MODE takes precedence over config" {
    mkdir -p .buildcrew
    echo "TDD_MODE=false" > .buildcrew/config
    TDD_MODE=true
    load_buildcrew_config
    [ "$TDD_MODE" = "true" ]
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

@test "__inject_tdd_prompt: returns prompt unchanged when TDD_MODE=false" {
    TDD_MODE=false
    local result
    result=$(__inject_tdd_prompt "build" "original prompt")
    [ "$result" = "original prompt" ]
}

@test "__inject_tdd_prompt: returns prompt unchanged when manifest missing" {
    TDD_MODE=true
    # No .claude/tdd-manifest.json exists
    local result
    result=$(__inject_tdd_prompt "build" "original prompt")
    [ "$result" = "original prompt" ]
}

@test "__inject_tdd_prompt: returns prompt unchanged for non-build/test/codereview phases" {
    TDD_MODE=true
    mkdir -p .claude
    echo '{"test_count": 5}' > .claude/tdd-manifest.json
    local result
    result=$(__inject_tdd_prompt "spec" "original prompt")
    [ "$result" = "original prompt" ]
}

@test "__inject_tdd_prompt: appends TDD context for build phase" {
    TDD_MODE=true
    mkdir -p .claude
    echo '{"test_count": 5}' > .claude/tdd-manifest.json
    local result
    result=$(__inject_tdd_prompt "build" "original prompt")
    [[ "$result" == "original prompt"* ]]
    [[ "$result" == *"TDD MODE: 5 failing tests exist"* ]]
    [[ "$result" == *"Do NOT modify TDD test files"* ]]
}

@test "__inject_tdd_prompt: appends TDD context for test phase" {
    TDD_MODE=true
    mkdir -p .claude
    echo '{"test_count": 3}' > .claude/tdd-manifest.json
    local result
    result=$(__inject_tdd_prompt "test" "original prompt")
    [[ "$result" == "original prompt"* ]]
    [[ "$result" == *"TDD VALIDATION MODE"* ]]
    [[ "$result" == *"openssl dgst -sha256"* ]]
}

@test "__inject_tdd_prompt: appends TDD context for codereview phase" {
    TDD_MODE=true
    mkdir -p .claude
    echo '{"test_count": 4}' > .claude/tdd-manifest.json
    local result
    result=$(__inject_tdd_prompt "codereview" "original prompt")
    [[ "$result" == "original prompt"* ]]
    [[ "$result" == *"TDD MODE ACTIVE"* ]]
    [[ "$result" == *"tdd-scaffold phase"* ]]
}

@test "__inject_tdd_prompt: returns prompt unchanged when test_count is 0" {
    TDD_MODE=true
    mkdir -p .claude
    echo '{"test_count": 0}' > .claude/tdd-manifest.json
    local result
    result=$(__inject_tdd_prompt "build" "original prompt")
    [ "$result" = "original prompt" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# __cleanup_tdd_artifacts tests
# ─────────────────────────────────────────────────────────────────────────────

@test "__cleanup_tdd_artifacts: no-op when TDD_MODE=false" {
    TDD_MODE=false
    mkdir -p .claude
    echo '{"test_dir": "tests/tdd"}' > .claude/tdd-manifest.json
    mkdir -p tests/tdd
    echo "test content" > tests/tdd/test_ac01.test.ts
    __cleanup_tdd_artifacts
    # Manifest and test files should still exist
    [ -f ".claude/tdd-manifest.json" ]
    [ -f "tests/tdd/test_ac01.test.ts" ]
}

@test "__cleanup_tdd_artifacts: no-op when manifest missing" {
    TDD_MODE=true
    # No manifest file
    __cleanup_tdd_artifacts
    # Should exit cleanly with no error
}

@test "__cleanup_tdd_artifacts: removes test dir and manifest" {
    TDD_MODE=true
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
    TDD_MODE=true
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
    TDD_MODE=true
    mkdir -p .claude
    cat > .claude/tdd-manifest.json << 'EOF'
{"test_dir": "tests/tdd", "test_files": [], "stub_files": []}
EOF
    # tests/tdd doesn't exist — should not error
    __cleanup_tdd_artifacts
    [ ! -f ".claude/tdd-manifest.json" ]
}
