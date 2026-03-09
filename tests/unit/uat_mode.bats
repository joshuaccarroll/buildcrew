#!/usr/bin/env bats
# Unit tests for UAT_MODE config loading in lib/workflow.sh (Part B)

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# load_buildcrew_config — UAT_MODE key (AC: UAT_MODE=parallel/sequential in config)
# ─────────────────────────────────────────────────────────────────────────────

@test "load_buildcrew_config: UAT_MODE=parallel sets variable to parallel" {
    mkdir -p .buildcrew
    echo "UAT_MODE=parallel" > .buildcrew/config
    unset UAT_MODE
    load_buildcrew_config
    [ "${UAT_MODE}" = "parallel" ]
}

@test "load_buildcrew_config: UAT_MODE=sequential sets variable to sequential" {
    mkdir -p .buildcrew
    echo "UAT_MODE=sequential" > .buildcrew/config
    unset UAT_MODE
    load_buildcrew_config
    [ "${UAT_MODE}" = "sequential" ]
}

@test "load_buildcrew_config: invalid UAT_MODE value emits warning and leaves variable unset" {
    mkdir -p .buildcrew
    echo "UAT_MODE=turbo" > .buildcrew/config
    unset UAT_MODE
    run load_buildcrew_config
    [[ "$output" == *"invalid UAT_MODE"* ]]
    [ -z "${UAT_MODE:-}" ]
}

@test "load_buildcrew_config: env var UAT_MODE is not overridden by config" {
    mkdir -p .buildcrew
    echo "UAT_MODE=parallel" > .buildcrew/config
    export UAT_MODE="sequential"
    load_buildcrew_config
    [ "${UAT_MODE}" = "sequential" ]
}

@test "load_buildcrew_config: lowercase uat_mode key is ignored (uppercase required)" {
    mkdir -p .buildcrew
    printf 'uat_mode=parallel\n' > .buildcrew/config
    unset UAT_MODE
    load_buildcrew_config
    [ -z "${UAT_MODE:-}" ]
}
