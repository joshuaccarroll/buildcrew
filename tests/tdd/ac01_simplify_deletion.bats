#!/usr/bin/env bats

# TDD Tests for AC-01: Delete skills/buildcrew-simplify/ directory
# TDD Tests for AC-02: Remove all references to buildcrew-simplify
# TDD Tests for AC-03: ./test.sh passes

setup() {
  cd "$BATS_TEST_DIRNAME/../.."
}

# AC-01: skills/buildcrew-simplify/ directory is deleted
@test "AC-01: skills/buildcrew-simplify directory does not exist" {
  [ ! -d "skills/buildcrew-simplify" ]
}

# AC-02: No references to buildcrew-simplify exist in the codebase
@test "AC-02: No buildcrew-simplify references in skills/" {
  ! grep -r "buildcrew-simplify" skills/ 2>/dev/null || false
}

@test "AC-02: No buildcrew-simplify references in bin/" {
  ! grep -r "buildcrew-simplify" bin/ 2>/dev/null || false
}

@test "AC-02: No buildcrew-simplify references in lib/" {
  ! grep -r "buildcrew-simplify" lib/ 2>/dev/null || false
}

@test "AC-02: No simplify phase references in workflows/" {
  ! grep -r "simplify phase\|simplify-report\|simplify-reuse\|simplify-quality\|simplify-efficiency" workflows/ 2>/dev/null || false
}

@test "AC-02: No run_optional_simplify references in source" {
  ! grep -r "run_optional_simplify" skills/ bin/ lib/ workflows/ tests/unit/ tests/integration/ tests/e2e/ 2>/dev/null || false
}

@test "AC-02: No simplify phase references in CLAUDE.md" {
  ! grep -i "simplify phase\|buildcrew-simplify" CLAUDE.md 2>/dev/null || false
}

@test "AC-02: No simplify phase references in README.md" {
  ! grep -i "simplify phase\|buildcrew-simplify" README.md 2>/dev/null || false
}

# AC-03: Test suite passes
@test "AC-03: ./test.sh passes" {
  # This test verifies the full test suite passes after cleanup
  # The build phase must ensure all modifications don't break tests
  run ./test.sh
  [ $status -eq 0 ]
}
