#!/usr/bin/env bats
# TDD tests for config.example completeness
# Maps to: AC-01 (all keys with correct defaults), AC-02 (grouping), AC-03 (test.sh passes)

setup() {
  BIN_FILE="$BATS_TEST_DIRNAME/../../bin/buildcrew"
}

# Helper: Extract config.example heredoc from bin/buildcrew
get_config_from_source() {
  # Extract the heredoc content between 'cat > .buildcrew/config.example << EOF' and 'EOF'
  sed -n "/cat > .buildcrew\/config.example << 'EOF'/,/^EOF$/p" "$BIN_FILE" | \
    sed '1d;$d' || echo ""
}

# --- AC-01: All config keys present with correct defaults ---

@test "AC01 config.example contains MAX_INVOCATIONS=15" {
  get_config_from_source | grep -q "MAX_INVOCATIONS=15"
}

@test "AC01 config.example contains COMPLEXITY_AWARE=true" {
  get_config_from_source | grep -q "COMPLEXITY_AWARE=true"
}

@test "AC01 config.example contains AUTO_MODE=true" {
  get_config_from_source | grep -q "AUTO_MODE=true"
}

@test "AC01 config.example contains CLAUDE_MODEL=auto" {
  get_config_from_source | grep -q "CLAUDE_MODEL=auto"
}

@test "AC01 config.example contains CLAUDE_EFFORT=medium" {
  get_config_from_source | grep -q "CLAUDE_EFFORT=medium"
}

@test "AC01 config.example contains MAX_PARALLEL=5" {
  get_config_from_source | grep -q "MAX_PARALLEL=5"
}

@test "AC01 config.example contains TARGET_DIR key" {
  get_config_from_source | grep -q "TARGET_DIR="
}

@test "AC01 config.example contains UAT_MAX_RETRIES=5" {
  get_config_from_source | grep -q "UAT_MAX_RETRIES=5"
}

@test "AC01 config.example contains UAT_ARTIFACT_TIMEOUT=7200" {
  get_config_from_source | grep -q "UAT_ARTIFACT_TIMEOUT=7200"
}

@test "AC01 config.example contains UAT_ARTIFACT_TYPE=cli" {
  get_config_from_source | grep -q "UAT_ARTIFACT_TYPE=cli"
}

@test "AC01 config.example contains UAT_RUN_COMMAND key" {
  get_config_from_source | grep -q "UAT_RUN_COMMAND="
}

@test "AC01 config.example contains UAT_STOP_COMMAND key" {
  get_config_from_source | grep -q "UAT_STOP_COMMAND="
}

@test "AC01 config.example contains UAT_INSTALL_COMMAND key" {
  get_config_from_source | grep -q "UAT_INSTALL_COMMAND="
}

@test "AC01 config.example contains UAT_HEALTH_CHECK key" {
  get_config_from_source | grep -q "UAT_HEALTH_CHECK="
}

@test "AC01 config.example contains UAT_HEALTH_CHECK_TIMEOUT=30" {
  get_config_from_source | grep -q "UAT_HEALTH_CHECK_TIMEOUT=30"
}

# --- AC-02: Keys grouped by feature area with section comments ---

@test "AC02 config.example has General section header" {
  get_config_from_source | grep -q "── General"
}

@test "AC02 config.example has Batch section header" {
  get_config_from_source | grep -q "── Batch"
}

@test "AC02 config.example has UAT section header" {
  get_config_from_source | grep -q "── UAT"
}

@test "AC02 config.example has UAT watch mode section" {
  get_config_from_source | grep -q "watch mode"
}

@test "AC02 config.example has UAT regress mode section" {
  get_config_from_source | grep -q "regress"
}
