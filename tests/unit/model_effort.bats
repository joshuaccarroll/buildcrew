#!/usr/bin/env bats
# Unit tests for --model and --effort flags

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# parse_args: --model tests
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --model sets CLAUDE_MODEL" {
    parse_args --model sonnet
    [ "$CLAUDE_MODEL" = "sonnet" ]
}

@test "parse_args: --model accepts full model ID" {
    parse_args --model claude-sonnet-4-6
    [ "$CLAUDE_MODEL" = "claude-sonnet-4-6" ]
}

@test "parse_args: --model without value exits with error" {
    run parse_args --model
    [ "$status" -eq 1 ]
    [[ "$output" == *"--model requires a value"* ]]
}

@test "parse_args: --model overrides default" {
    parse_args --model haiku
    [ "$CLAUDE_MODEL" = "haiku" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# parse_args: --effort tests
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --effort low sets CLAUDE_EFFORT=low" {
    parse_args --effort low
    [ "$CLAUDE_EFFORT" = "low" ]
}

@test "parse_args: --effort medium sets CLAUDE_EFFORT=medium" {
    parse_args --effort medium
    [ "$CLAUDE_EFFORT" = "medium" ]
}

@test "parse_args: --effort high sets CLAUDE_EFFORT=high" {
    parse_args --effort high
    [ "$CLAUDE_EFFORT" = "high" ]
}

@test "parse_args: --effort with invalid value exits with error" {
    run parse_args --effort bad
    [ "$status" -eq 1 ]
    [[ "$output" == *"--effort requires a value: low, medium, or high"* ]]
}

@test "parse_args: --effort without value exits with error" {
    run parse_args --effort
    [ "$status" -eq 1 ]
    [[ "$output" == *"--effort requires a value"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Defaults
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: CLAUDE_MODEL defaults to auto" {
    parse_args
    [ "$CLAUDE_MODEL" = "auto" ]
}

@test "parse_args: CLAUDE_EFFORT defaults to medium" {
    parse_args
    [ "$CLAUDE_EFFORT" = "medium" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Combined flags
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --model and --effort combined" {
    parse_args --model sonnet --effort low
    [ "$CLAUDE_MODEL" = "sonnet" ]
    [ "$CLAUDE_EFFORT" = "low" ]
}

@test "parse_args: --model and --effort with other flags" {
    parse_args --model sonnet --effort high --dry-run --single
    [ "$CLAUDE_MODEL" = "sonnet" ]
    [ "$CLAUDE_EFFORT" = "high" ]
    [ "$DRY_RUN" = "true" ]
    [ "$SINGLE_TASK" = "true" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Help text
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --help mentions --model" {
    run parse_args --help
    [[ "$output" == *"--model"* ]]
}

@test "parse_args: --help mentions --effort" {
    run parse_args --help
    [[ "$output" == *"--effort"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Config file loading
# ─────────────────────────────────────────────────────────────────────────────

@test "load_buildcrew_config: CLAUDE_MODEL from config file" {
    mkdir -p .buildcrew
    echo "CLAUDE_MODEL=sonnet" > .buildcrew/config
    unset CLAUDE_MODEL
    load_buildcrew_config
    [ "$CLAUDE_MODEL" = "sonnet" ]
}

@test "load_buildcrew_config: CLAUDE_EFFORT from config file" {
    mkdir -p .buildcrew
    echo "CLAUDE_EFFORT=high" > .buildcrew/config
    unset CLAUDE_EFFORT
    load_buildcrew_config
    [ "$CLAUDE_EFFORT" = "high" ]
}

@test "load_buildcrew_config: invalid CLAUDE_EFFORT in config is rejected" {
    mkdir -p .buildcrew
    echo "CLAUDE_EFFORT=turbo" > .buildcrew/config
    unset CLAUDE_EFFORT
    run load_buildcrew_config
    [[ "$output" == *"invalid CLAUDE_EFFORT"* ]]
}

@test "load_buildcrew_config: env var CLAUDE_MODEL wins over config" {
    mkdir -p .buildcrew
    echo "CLAUDE_MODEL=sonnet" > .buildcrew/config
    CLAUDE_MODEL=haiku
    load_buildcrew_config
    [ "$CLAUDE_MODEL" = "haiku" ]
}

@test "load_buildcrew_config: env var CLAUDE_EFFORT wins over config" {
    mkdir -p .buildcrew
    echo "CLAUDE_EFFORT=low" > .buildcrew/config
    CLAUDE_EFFORT=high
    load_buildcrew_config
    [ "$CLAUDE_EFFORT" = "high" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# resolve_phase_model
# ─────────────────────────────────────────────────────────────────────────────

@test "resolve_phase_model: review -> opus" {
    CLAUDE_MODEL=auto
    result=$(resolve_phase_model "review")
    [ "$result" = "opus" ]
}

@test "resolve_phase_model: build -> sonnet" {
    CLAUDE_MODEL=auto
    result=$(resolve_phase_model "build")
    [ "$result" = "sonnet" ]
}

@test "resolve_phase_model: simplify -> haiku" {
    CLAUDE_MODEL=auto
    result=$(resolve_phase_model "simplify")
    [ "$result" = "haiku" ]
}

@test "resolve_phase_model: unknown phase -> sonnet (fallback)" {
    CLAUDE_MODEL=auto
    result=$(resolve_phase_model "unknown-phase")
    [ "$result" = "sonnet" ]
}

@test "resolve_phase_model: review + simple -> sonnet (opus downgraded)" {
    CLAUDE_MODEL=auto
    result=$(resolve_phase_model "review" "simple")
    [ "$result" = "sonnet" ]
}

@test "resolve_phase_model: build + trivial -> haiku (sonnet downgraded)" {
    CLAUDE_MODEL=auto
    result=$(resolve_phase_model "build" "trivial")
    [ "$result" = "haiku" ]
}

@test "resolve_phase_model: simplify + trivial -> haiku (stays haiku)" {
    CLAUDE_MODEL=auto
    result=$(resolve_phase_model "simplify" "trivial")
    [ "$result" = "haiku" ]
}

@test "resolve_phase_model: explicit model overrides phase selection" {
    CLAUDE_MODEL=opus
    result=$(resolve_phase_model "build")
    [ "$result" = "opus" ]
}

@test "resolve_phase_model: explicit model ignores complexity downgrade" {
    CLAUDE_MODEL=opus
    result=$(resolve_phase_model "build" "trivial")
    [ "$result" = "opus" ]
}
