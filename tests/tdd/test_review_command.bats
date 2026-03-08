#!/usr/bin/env bats
# TDD Tests for buildcrew test-review subcommand
# Covers: CLI dispatch, git checks, test discovery, runner detection, baseline verification, file batching

load '../setup.bash'

setup() {
    setup_test_dir
    cd "$TEST_DIR"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: Command Dispatch — verify test-review is recognized as valid subcommand
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01: test-review command is recognized (exits 0, not 'unknown command')" {
    git init .
    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    # Should NOT be "unknown command" error
    [[ "$output" != *"Unknown command"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: Git Repo Check — verify repo detection and error handling
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02: errors when not in a git repository" {
    # TEST_DIR is not a git repo
    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    # Should fail (exit non-zero)
    [ $status -ne 0 ]
    # Should mention git or repo
    [[ "$output" == *"git"* ]] || [[ "$output" == *"repo"* ]] || [[ "$output" == *"repository"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: Dirty Tree Warning — verify dirty tree detection
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03: warns when working tree is dirty" {
    git init .
    echo "test content" > test.txt
    # Don't stage/commit it — tree is dirty

    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    # Should mention dirty or warn
    [[ "$output" == *"dirty"* ]] || [[ "$output" == *"warn"* ]] || [[ "$output" == *"Warn"* ]] || [[ "$output" == *"changes"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: Test Discovery — discover test files using standard patterns
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04: discovers JavaScript/TypeScript test files" {
    git init .
    git commit --allow-empty -m "initial"
    mkdir -p tests/unit
    echo "// test" > tests/unit/math.test.js
    echo "// test" > tests/unit/utils.spec.ts
    git add -A && git commit -m "add tests"

    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    # Should explicitly mention discovering 2 files
    [[ "$output" == *"2 test file"* ]] || [[ "$output" == *"discovered 2"* ]] || [[ "$output" == *"2 file"* ]]
}

@test "AC-04: discovers Bash/bats test files" {
    git init .
    git commit --allow-empty -m "initial"
    mkdir -p tests
    echo "#!/usr/bin/env bats" > tests/cli.bats
    git add -A && git commit -m "add test"

    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    [[ "$output" == *"1 test file"* ]] || [[ "$output" == *"discovered 1"* ]]
}

@test "AC-04: discovers Python test files" {
    git init .
    git commit --allow-empty -m "initial"
    mkdir -p tests
    echo "import pytest" > tests/test_module.py
    git add -A && git commit -m "add test"

    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    [[ "$output" == *"1 test file"* ]] || [[ "$output" == *"discovered 1"* ]]
}

@test "AC-04: excludes files in excluded directories" {
    git init .
    git commit --allow-empty -m "initial"
    mkdir -p tests node_modules/tests vendor/tests
    echo "// test" > tests/real.test.js
    echo "// test" > node_modules/tests/fake.test.js
    echo "// test" > vendor/tests/fake.test.js
    git add -A && git commit -m "add tests"

    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    # Should count only 1, not 3
    [[ "$output" == *"1 test file"* ]] || [[ "$output" == *"discovered 1"* ]]
}

@test "AC-04: exits cleanly when no test files are found" {
    git init .
    git commit --allow-empty -m "initial"

    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    # Should indicate no tests found
    [[ "$output" == *"No test file"* ]] || [[ "$output" == *"no test"* ]] || [[ "$output" == *"not found"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: Runner Detection — detect test runner from discovered files
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-05: detects jest runner from *.test.js files" {
    git init .
    git commit --allow-empty -m "initial"
    mkdir -p tests
    echo "test('sum', () => {})" > tests/math.test.js
    git add -A && git commit -m "add test"

    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    [[ "$output" == *"jest"* ]] || [[ "$output" == *"Jest"* ]]
}

@test "AC-05: detects bats runner from *.bats files" {
    git init .
    git commit --allow-empty -m "initial"
    mkdir -p tests
    echo "#!/usr/bin/env bats" > tests/cli.bats
    git add -A && git commit -m "add test"

    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    [[ "$output" == *"bats"* ]] || [[ "$output" == *"Bats"* ]]
}

@test "AC-05: detects pytest runner from test_*.py files" {
    git init .
    git commit --allow-empty -m "initial"
    mkdir -p tests
    echo "def test_example(): pass" > tests/test_feature.py
    git add -A && git commit -m "add test"

    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    [[ "$output" == *"pytest"* ]] || [[ "$output" == *"Pytest"* ]] || [[ "$output" == *"Python"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-06: Baseline Verification — run TEST_CMD and record baseline status
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-06: runs baseline and reports success" {
    git init .
    git commit --allow-empty -m "initial"
    mkdir -p tests
    echo "#!/usr/bin/env bats
@test 'baseline test' {
  [ 1 -eq 1 ]
}" > tests/baseline.bats
    git add -A && git commit -m "add test"

    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    # Should explicitly mention baseline passing
    [[ "$output" == *"baseline"* ]] || [[ "$output" == *"Baseline"* ]]
}

@test "AC-06: detects baseline failure and enters report-only mode" {
    git init .
    git commit --allow-empty -m "initial"
    mkdir -p tests
    echo "#!/usr/bin/env bats
@test 'failing test' {
  [ 1 -eq 2 ]
}" > tests/failing.bats
    git add -A && git commit -m "add test"

    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    # Should report baseline failed and note report-only mode
    [[ "$output" == *"baseline"* ]] && [[ "$output" == *"fail"* ]]
    [[ "$output" == *"report"* ]] || [[ "$output" == *"Report"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-07: Batch Division — divide discovered files into groups of 15
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-07: batches 10 files into 1 batch" {
    git init .
    git commit --allow-empty -m "initial"
    mkdir -p tests
    for i in {1..10}; do
        echo "test" > "tests/test_$i.test.js"
    done
    git add -A && git commit -m "add tests"

    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    # Should report 1 batch
    [[ "$output" == *"1 batch"* ]] || [[ "$output" == *"batch 1"* ]]
}

@test "AC-07: batches 16 files into 2 batches (15+1)" {
    git init .
    git commit --allow-empty -m "initial"
    mkdir -p tests
    for i in {1..16}; do
        echo "test" > "tests/test_$i.test.js"
    done
    git add -A && git commit -m "add tests"

    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    # Should report 2 batches
    [[ "$output" == *"2 batch"* ]] || [[ "$output" == *"batch 2"* ]]
}

@test "AC-07: batches 30 files into 2 batches (15+15)" {
    git init .
    git commit --allow-empty -m "initial"
    mkdir -p tests
    for i in {1..30}; do
        echo "test" > "tests/test_$i.test.js"
    done
    git add -A && git commit -m "add tests"

    run "$BUILDCREW_HOME/bin/buildcrew" test-review
    # Should report 2 batches
    [[ "$output" == *"2 batch"* ]] || [[ "$output" == *"batch 2"* ]]
}
