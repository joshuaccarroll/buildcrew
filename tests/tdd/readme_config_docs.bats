#!/usr/bin/env bats
# TDD tests for README.md configuration documentation updates
# Maps to acceptance criteria from the plan

setup() {
  README="$BATS_TEST_DIRNAME/../../README.md"
}

# --- AC-01: Per-persona overrides names all six persona slugs ---

@test "AC01 README mentions per-persona rules with product-manager slug" {
  grep -q 'product-manager' "$README"
  # Must appear in context of per-persona rules, not just the persona table
  grep -q 'product-manager-rules\|product-manager.*rules' "$README"
}

@test "AC01 README mentions per-persona rules with ux-designer slug" {
  grep -q 'ux-designer-rules\|ux-designer.*rules' "$README"
}

@test "AC01 README mentions per-persona rules with feature-engineer slug" {
  grep -q 'feature-engineer-rules\|feature-engineer.*rules' "$README"
}

@test "AC01 README mentions per-persona rules with principal-engineer slug" {
  grep -q 'principal-engineer-rules\|principal-engineer.*rules' "$README"
}

@test "AC01 README mentions per-persona rules with qa-engineer slug" {
  grep -q 'qa-engineer-rules\|qa-engineer.*rules' "$README"
}

@test "AC01 README mentions per-persona rules with security-engineer slug" {
  grep -q 'security-engineer-rules\|security-engineer.*rules' "$README"
}

# --- AC-02: Override/Disable syntax with code example ---

@test "AC02 README documents Override: syntax" {
  grep -q '## Override:' "$README"
}

@test "AC02 README documents Disable: syntax" {
  grep -q '## Disable:' "$README"
}

# --- AC-03: UAT config keys documented ---

@test "AC03 README documents UAT_INSTALL_COMMAND in configuration" {
  grep -q 'UAT_INSTALL_COMMAND' "$README"
}

@test "AC03 README documents UAT_HEALTH_CHECK in configuration" {
  grep -q 'UAT_HEALTH_CHECK' "$README"
}

@test "AC03 README documents UAT_HEALTH_CHECK_TIMEOUT in configuration" {
  grep -q 'UAT_HEALTH_CHECK_TIMEOUT' "$README"
}

# --- AC-04: Context truncation note explains 10KB limit ---

@test "AC04 README explains 10KB context truncation limit" {
  grep -q '10KB\|10 *KB' "$README"
}

@test "AC04 README mentions truncation behavior" {
  grep -qi 'truncat' "$README"
}

# --- AC-05: --resume mentions invocation count carryover ---

@test "AC05 README --resume description mentions invocation count preservation" {
  # The --resume row in the Run Options table should mention invocation counts
  # Extract the --resume line and check for invocation-related content
  grep -A5 '`--resume`' "$README" | grep -qi 'invocation'
}

# --- AC-06: buildcrew dash status in CLI commands ---

@test "AC06 README includes buildcrew dash status command" {
  grep -q 'buildcrew dash status' "$README"
}

# --- AC-07: Rules merge order includes per-persona layer ---

@test "AC07 How It Works rules merge mentions per-persona rules layer" {
  # The existing merge order must be extended to include per-persona project rules
  # Check that the README mentions slug-rules.md files specifically
  grep -q '<slug>-rules\.md\|slug.*-rules\.md' "$README"
}
