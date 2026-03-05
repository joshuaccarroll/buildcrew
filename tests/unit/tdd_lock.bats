#!/usr/bin/env bats
# Unit tests for TDD file locking (__lock_tdd_files, __unlock_tdd_files, __with_tdd_lock)

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# __lock_tdd_files
# ─────────────────────────────────────────────────────────────────────────────

@test "__lock_tdd_files: no-op when manifest missing" {
    __lock_tdd_files
    # Should not error
}

@test "__lock_tdd_files: makes test files read-only" {
    mkdir -p .claude tests/tdd
    echo "test" > tests/tdd/test_ac01.test.ts
    echo "test2" > tests/tdd/test_ac02.test.ts
    cat > .claude/tdd-manifest.json << 'EOF'
{"test_files": ["tests/tdd/test_ac01.test.ts", "tests/tdd/test_ac02.test.ts"]}
EOF
    __lock_tdd_files
    [ ! -w "tests/tdd/test_ac01.test.ts" ]
    [ ! -w "tests/tdd/test_ac02.test.ts" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# __unlock_tdd_files
# ─────────────────────────────────────────────────────────────────────────────

@test "__unlock_tdd_files: restores write permission" {
    mkdir -p .claude tests/tdd
    echo "test" > tests/tdd/test_ac01.test.ts
    echo '{"test_files": ["tests/tdd/test_ac01.test.ts"]}' > .claude/tdd-manifest.json
    chmod a-w tests/tdd/test_ac01.test.ts
    [ ! -w "tests/tdd/test_ac01.test.ts" ]
    __unlock_tdd_files
    [ -w "tests/tdd/test_ac01.test.ts" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# __with_tdd_lock
# ─────────────────────────────────────────────────────────────────────────────

@test "__with_tdd_lock: locks before command and unlocks after" {
    mkdir -p .claude tests/tdd
    echo "test" > tests/tdd/test_ac01.test.ts
    echo '{"test_files": ["tests/tdd/test_ac01.test.ts"]}' > .claude/tdd-manifest.json

    # Command that checks the file is locked during execution
    check_locked() {
        [ ! -w "tests/tdd/test_ac01.test.ts" ]
    }

    __with_tdd_lock check_locked
    # After: file should be writable again
    [ -w "tests/tdd/test_ac01.test.ts" ]
}

@test "__with_tdd_lock: unlocks even when command fails" {
    mkdir -p .claude tests/tdd
    echo "test" > tests/tdd/test_ac01.test.ts
    echo '{"test_files": ["tests/tdd/test_ac01.test.ts"]}' > .claude/tdd-manifest.json

    failing_cmd() { return 1; }

    run __with_tdd_lock failing_cmd
    [ "$status" -eq 1 ]
    # File should be unlocked despite failure
    [ -w "tests/tdd/test_ac01.test.ts" ]
}

@test "__with_tdd_lock: propagates exit code" {
    mkdir -p .claude tests/tdd
    echo "test" > tests/tdd/test_ac01.test.ts
    echo '{"test_files": ["tests/tdd/test_ac01.test.ts"]}' > .claude/tdd-manifest.json

    exit_42() { return 42; }

    run __with_tdd_lock exit_42
    [ "$status" -eq 42 ]
}

@test "__lock_tdd_files: handles missing test files gracefully" {
    mkdir -p .claude
    echo '{"test_files": ["nonexistent/file.ts"]}' > .claude/tdd-manifest.json
    # Should not error
    __lock_tdd_files
}
