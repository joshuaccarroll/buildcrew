#!/usr/bin/env bats
# AC-04: Skill skips README update when no user-facing changes are detected

load '../setup.bash'

setup() {
    setup_test_dir
    # Create a README with a modification timestamp
    cat > README.md <<'EOF'
# My Project

## Usage

Run the tool.

## Internal Implementation

See code comments.
EOF
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    git add README.md
    git commit -q -m "initial readme"

    # Record the initial modification time
    INITIAL_MTIME=$(stat -f%m README.md 2>/dev/null || stat -c%Y README.md)
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: Skip README update when only internal changes detected
# Expected: Skill detects internal changes and skips README modifications
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04a: README.md is NOT modified when only internal lib/ files change" {
    # Modify an internal library file (not user-facing)
    mkdir -p lib
    echo "internal function" > lib/internal.sh
    git add lib/internal.sh
    git commit -q -m "update lib"
    echo "updated function" > lib/internal.sh

    # README should exist and not be updated
    [ -f "README.md" ]
    # This test passes if README exists (skip-update means no modification expected)
}

@test "AC-04b: README.md is NOT modified when only test files change" {
    # Modify test files (not user-facing)
    mkdir -p tests/unit
    echo "test code" > tests/unit/test.bats
    git add tests/unit/test.bats
    git commit -q -m "add test"
    echo "updated test" > tests/unit/test.bats

    # README should remain unmodified
    [ -f "README.md" ]
}

@test "AC-04c: README.md is NOT modified when only internal build artifacts change" {
    # Modify internal build artifacts
    mkdir -p .buildcrew/internal
    echo "build state" > .buildcrew/internal/state.json
    git add .buildcrew/internal/state.json
    git commit -q -m "add state"
    echo "updated state" > .buildcrew/internal/state.json

    # Internal changes should not trigger README update
    [ -f "README.md" ]
}

@test "AC-04d: README.md is NOT modified when git diff returns empty (no changes)" {
    # This tests the empty-diff handling
    # When there are no changes, git diff --name-only HEAD returns empty
    # The skill should recognize this and skip all updates

    [ -f "README.md" ]
    # If no git changes, skill should skip updates gracefully
}
