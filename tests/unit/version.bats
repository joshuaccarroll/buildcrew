#!/usr/bin/env bats
# Unit tests for lib/version.sh

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "version.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# get_version tests
# ─────────────────────────────────────────────────────────────────────────────

@test "get_version: returns version from VERSION file" {
    echo "1.2.3" > "$BUILDCREW_HOME/VERSION"
    run get_version
    [ "$output" = "1.2.3" ]
}

@test "get_version: returns 'unknown' when VERSION missing" {
    # Temporarily move VERSION file
    if [ -f "$BUILDCREW_HOME/VERSION" ]; then
        mv "$BUILDCREW_HOME/VERSION" "$BUILDCREW_HOME/VERSION.bak"
    fi

    run get_version
    [ "$output" = "unknown" ]

    # Restore VERSION file
    if [ -f "$BUILDCREW_HOME/VERSION.bak" ]; then
        mv "$BUILDCREW_HOME/VERSION.bak" "$BUILDCREW_HOME/VERSION"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# version_lt tests (version less than comparison)
# ─────────────────────────────────────────────────────────────────────────────

@test "version_lt: 1.0.0 < 1.0.1 returns 0" {
    run version_lt "1.0.0" "1.0.1"
    [ "$status" -eq 0 ]
}

@test "version_lt: 1.0.1 < 1.0.0 returns 1" {
    run version_lt "1.0.1" "1.0.0"
    [ "$status" -eq 1 ]
}

@test "version_lt: 1.0.0 < 1.0.0 returns 1 (equal)" {
    run version_lt "1.0.0" "1.0.0"
    [ "$status" -eq 1 ]
}

@test "version_lt: 1.0.0 < 2.0.0 returns 0" {
    run version_lt "1.0.0" "2.0.0"
    [ "$status" -eq 0 ]
}

@test "version_lt: 1.9.9 < 1.10.0 returns 0 (numeric comparison)" {
    run version_lt "1.9.9" "1.10.0"
    [ "$status" -eq 0 ]
}

@test "version_lt: 2.0.0 < 1.99.99 returns 1" {
    run version_lt "2.0.0" "1.99.99"
    [ "$status" -eq 1 ]
}

@test "version_lt: 0.1.0 < 0.2.0 returns 0" {
    run version_lt "0.1.0" "0.2.0"
    [ "$status" -eq 0 ]
}

@test "version_lt: handles minor version increment" {
    run version_lt "1.1.0" "1.2.0"
    [ "$status" -eq 0 ]
}

@test "version_lt: handles patch version increment" {
    run version_lt "1.1.1" "1.1.2"
    [ "$status" -eq 0 ]
}
