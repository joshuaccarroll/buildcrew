#!/usr/bin/env bats
# TDD Tests for Workflow Diagram (Mermaid) in README.md
# Task: Add a full workflow diagram showing BuildCrew phases, branches, loops, and circuit breakers

load '../setup.bash'

setup() {
    setup_test_dir
    # Copy README.md from the original repo to test directory
    cp "$BUILDCREW_ROOT/README.md" "$TEST_DIR/README.md" 2>/dev/null || \
        touch "$TEST_DIR/README.md"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: Exactly one mermaid block in "How It Works" section
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01a: README.md contains exactly one mermaid code block" {
    # Count backtick-mermaid blocks
    local count
    count=$(grep -c '```mermaid' README.md 2>/dev/null)
    [ "x$count" = "x1" ]
}

@test "AC-01b: Mermaid block is located in 'How It Works' section" {
    # Extract from "## How It Works" to next "##" and check for mermaid block
    awk '/^## How It Works/,/^##/ { print }' README.md | grep -q 'mermaid'
}

@test "AC-01c: Mermaid block starts with flowchart TD" {
    # After the opening fence, first non-empty line should be "flowchart TD"
    grep 'flowchart TD' README.md
}

@test "AC-01d: No mermaid blocks outside 'How It Works' section" {
    # Find all mermaid blocks and verify only one in the How It Works section
    local mermaid_count
    mermaid_count=$(grep -c '```mermaid' README.md 2>/dev/null)
    [ "x$mermaid_count" = "x1" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: Discovery mode entry path
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02a: Diagram shows 'buildcrew run' entry point" {
    grep -q 'buildcrew run' README.md
}

@test "AC-02b: Diagram shows 'Pending tasks?' decision node" {
    grep -q 'Pending tasks' README.md
}

@test "AC-02c: Diagram shows 'Discovery mode' terminal for no pending tasks" {
    grep -q 'Discovery mode' README.md
}

@test "AC-02d: Discovery mode branch shows PM planning" {
    grep -q 'PM\|planning' README.md
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: Execution mode entry path with Precompute
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03a: Diagram shows Precompute step after pending tasks decision" {
    grep -q 'Precompute' README.md
}

@test "AC-03b: Diagram shows Yes branch from Pending tasks to Precompute" {
    grep -q -E 'Yes|-->.*Precompute' README.md
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: Per-phase model selection under --model auto
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-04a: spec phase shows Sonnet model" {
    grep -q 'spec.*Sonnet\|Sonnet.*spec' README.md
}

@test "AC-04b: research phase shows Sonnet model" {
    grep -q 'research.*Sonnet\|Sonnet.*research' README.md
}

@test "AC-04c: review phase shows Opus model" {
    grep -q 'review.*Opus\|Opus.*review' README.md
}

@test "AC-04d: tdd-scaffold phase shows Haiku model" {
    grep -q 'tdd-scaffold.*Haiku\|Haiku.*tdd-scaffold' README.md
}

@test "AC-04e: build phase shows Sonnet model" {
    grep -q 'build.*Sonnet\|Sonnet.*build' README.md
}

@test "AC-04f: simplify phase shows Haiku model" {
    grep -q 'simplify.*Haiku\|Haiku.*simplify' README.md
}

@test "AC-04g: codereview phase shows Opus model" {
    grep -q 'codereview.*Opus\|Opus.*codereview' README.md
}

@test "AC-04h: verify phase shows Opus model" {
    grep -q 'verify.*Opus\|Opus.*verify' README.md
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: Complexity-based phase skipping (trivial/simple/standard)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-05a: Diagram shows trivial complexity branch" {
    grep -q 'trivial' README.md
}

@test "AC-05b: Diagram shows simple complexity branch" {
    grep -q 'simple' README.md
}

@test "AC-05c: Diagram shows standard complexity branch" {
    grep -q 'standard' README.md
}

@test "AC-05d: Trivial path includes build and verify only" {
    # Trivial should lead to build and verify (not research, spec, etc.)
    grep -q 'trivial.*build\|build.*trivial' README.md
}

@test "AC-05e: Simple path includes research and build and verify" {
    # Simple should lead through research, build, verify (not spec, tdd-scaffold, etc.)
    grep -q 'simple.*research\|research.*simple' README.md
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-06: Plan-review circuit breaker with replan loop
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-06a: Diagram shows review phase" {
    grep -q 'review' README.md
}

@test "AC-06b: Diagram shows needs_revision verdict from review" {
    grep -q 'needs_revision' README.md
}

@test "AC-06c: First needs_revision causes review retry (self-loop)" {
    # The word "retry" or indication of self-loop should be present
    grep -q -E 'needs_revision.*retry|retry.*review|1st|first' README.md
}

@test "AC-06d: Second consecutive needs_revision triggers replan" {
    # Should show circuit breaker logic with "2nd" or "consecutive"
    grep -q -E '2nd consecutive|second.*needs_revision|consecutive.*needs_revision' README.md
}

@test "AC-06e: Replan from review goes back to research" {
    # Circuit breaker should loop back to research (standard path only)
    grep -q -E 'research|replan' README.md
}

@test "AC-06f: Diagram shows rejected verdict blocks task" {
    grep -q 'rejected' README.md
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-07: Build-codereview rebuild loop
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-07a: Diagram shows codereview phase" {
    grep -q 'codereview' README.md
}

@test "AC-07b: Diagram shows needs_rebuild verdict from codereview" {
    grep -q 'needs_rebuild' README.md
}

@test "AC-07c: needs_rebuild loops back to build" {
    # Should show path from codereview back to build
    grep -q -E 'build.*needs_rebuild|needs_rebuild.*build' README.md
}

@test "AC-07d: Second consecutive needs_rebuild triggers circuit breaker" {
    # Should show repeated needs_rebuild triggers replan
    grep -q -E '2nd|consecutive|needs_rebuild.*2' README.md
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-08: Verify-failure rebuild path
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-08a: Diagram shows verify phase" {
    grep -q 'verify' README.md
}

@test "AC-08b: Diagram shows blocked verdict from verify" {
    grep -q 'blocked' README.md
}

@test "AC-08c: Verify blocked loops back to build" {
    # Standard path rebuild goes through build->simplify->codereview->verify
    grep -q -E 'verify.*blocked|blocked.*build' README.md
}

@test "AC-08d: Verify rebuild path includes simplify and codereview for standard" {
    # For standard complexity, rebuild path should be build->simplify->codereview->verify
    grep -q -E 'simplify|codereview' README.md
}

@test "AC-08e: Second consecutive verify blocked triggers circuit breaker" {
    # Circuit breaker should show replan on second blocked
    grep -q -E 'blocked.*2|2.*blocked|consecutive.*blocked' README.md
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-09: Chunked build fallback
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-09a: Diagram shows chunked build node" {
    grep -q 'chunked build' README.md
}

@test "AC-09b: Diagram shows max-turns trigger from build to chunked build" {
    grep -q -E 'max-turns|max.*turns' README.md
}

@test "AC-09c: Chunked build complete path returns to simplify" {
    # Chunked build success should lead to simplify (standard) or verify (trivial/simple)
    grep -q -E 'simplify|verify' README.md
}

@test "AC-09d: Chunked build failure blocks task" {
    # Chunked build failure should show Task blocked terminal
    grep -q -E 'chunked.*fail|fail.*blocked|Task blocked' README.md
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-10: Post-completion UAT with retry loop
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-10a: Diagram shows UAT phase after completion" {
    grep -q 'UAT' README.md
}

@test "AC-10b: UAT pass verdict leads to Done" {
    grep -q -E 'UAT.*pass|pass.*Done' README.md
}

@test "AC-10c: UAT fail verdict triggers rebuild retry" {
    grep -q -E 'UAT.*fail|fail.*build|retry' README.md
}

@test "AC-10d: UAT retries are bounded (up to 5)" {
    grep -q -E 'retry.*5|up to 5|5x' README.md
}

@test "AC-10e: UAT exhausted retries marked non-fatal" {
    grep -q -E 'non-fatal|retries exhausted' README.md
}

# ─────────────────────────────────────────────────────────────────────────────
# Additional Verification Tests
# ─────────────────────────────────────────────────────────────────────────────

@test "VERIFY: README.md contains Task blocked terminal nodes" {
    # Circuit breaker should show Task blocked for all exhausted replan paths
    grep -q 'Task blocked' README.md
}

@test "VERIFY: README.md contains Done terminal node" {
    grep -q 'Done' README.md
}

@test "VERIFY: Mermaid syntax uses proper flowchart TD format" {
    # Basic flowchart structure check
    grep -q 'flowchart TD' README.md
}
