#!/usr/bin/env bats
# Experience harness for BuildCrew
# Simulates end-user interaction with the system as a real user would experience it.
# This harness is cumulative — new tasks extend it, existing scenarios are never removed
# unless a task intentionally changes tested behavior.

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# Task: Emit awaiting_input state from workflow.sh review functions
# ─────────────────────────────────────────────────────────────────────────────

# Happy path: a user runs buildcrew in AUTO_MODE (CI / non-interactive).
# The dashboard should NOT see awaiting_input — the workflow auto-approves and moves on.
@test "experience: AUTO_MODE plan review never blocks and emits no awaiting_input state" {
    export AUTO_MODE="true"
    export HUMAN_REVIEW="true"
    run handle_plan_review "add dark mode" "Add dark mode toggle"
    [ "$status" -eq 0 ]
    run grep -q "PHASE_STATUS=awaiting_input" .buildcrew/.workflow-state
    [ "$status" -ne 0 ]
}

# Happy path: dashboard reads state file and sees awaiting_input written correctly.
# Simulates buildcrew-dash polling the state file while user is prompted.
@test "experience: state file contains awaiting_input after update_workflow_state call" {
    run update_workflow_state "review" "awaiting_input"
    [ "$status" -eq 0 ]
    run grep -q "PHASE_STATUS=awaiting_input" .buildcrew/.workflow-state
    [ "$status" -eq 0 ]
    # Dashboard can also read the PHASE key to know which review is pending
    run grep -q "PHASE=review" .buildcrew/.workflow-state
    [ "$status" -eq 0 ]
}

# Happy path: spec review state is distinct and readable by dashboard.
@test "experience: spec review state file written with correct phase key" {
    run update_workflow_state "spec" "awaiting_input"
    [ "$status" -eq 0 ]
    run grep -q "PHASE_STATUS=awaiting_input" .buildcrew/.workflow-state
    [ "$status" -eq 0 ]
    run grep -q "PHASE=spec" .buildcrew/.workflow-state
    [ "$status" -eq 0 ]
}

# Error recovery path: a subsequent run_phase_group call naturally overwrites state.
# Verifies the "no restore call needed" design — state transitions forward, not backward.
@test "experience: subsequent state update overwrites awaiting_input naturally" {
    run update_workflow_state "review" "awaiting_input"
    [ "$status" -eq 0 ]
    run update_workflow_state "build" "running"
    [ "$status" -eq 0 ]
    run grep -q "PHASE_STATUS=running" .buildcrew/.workflow-state
    [ "$status" -eq 0 ]
    run grep -q "PHASE_STATUS=awaiting_input" .buildcrew/.workflow-state
    [ "$status" -ne 0 ]
}

# Adversarial: user calls handle_spec_review with AUTO_MODE=true and an empty ac_count.
# Should not crash or emit awaiting_input.
@test "experience: handle_spec_review with AUTO_MODE and empty ac_count does not crash" {
    export AUTO_MODE="true"
    run handle_spec_review "some-task" ""
    [ "$status" -eq 0 ]
    run grep -q "PHASE_STATUS=awaiting_input" .buildcrew/.workflow-state
    [ "$status" -ne 0 ]
}

# Adversarial: .buildcrew directory is absent when update_workflow_state is called.
# Simulates a fresh or partially-initialized project — function must create the dir.
@test "experience: update_workflow_state creates .buildcrew dir if absent" {
    rm -rf .buildcrew
    run update_workflow_state "review" "awaiting_input"
    [ "$status" -eq 0 ]
    [ -f ".buildcrew/.workflow-state" ]
    run grep -q "PHASE_STATUS=awaiting_input" .buildcrew/.workflow-state
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Task: Unified /release-github slash command
# ─────────────────────────────────────────────────────────────────────────────
RELEASE_CMD="/Users/joshcarroll/code/buildcrew-dev/.claude/commands/release-github.md"

# Happy path: user runs /release-github — the command file is present and loadable.
@test "experience: release-github command file exists and is non-empty" {
    [ -f "$RELEASE_CMD" ]
    [ -s "$RELEASE_CMD" ]
}

# Happy path: command file has well-formed YAML frontmatter with all required keys.
@test "experience: release-github frontmatter has allowed-tools, description, argument-hint" {
    grep -q '^allowed-tools:' "$RELEASE_CMD"
    grep -q '^description:' "$RELEASE_CMD"
    grep -q '^argument-hint:' "$RELEASE_CMD"
}

# Happy path: user types /release-github buildcrew patch — command instructs correct paths.
@test "experience: release-github refers to correct absolute paths for both projects" {
    grep -q '/Users/joshcarroll/code/buildcrew-dev/buildcrew' "$RELEASE_CMD"
    grep -q '/Users/joshcarroll/code/buildcrew-dev/buildcrew-dash' "$RELEASE_CMD"
}

# Happy path: user runs /release-github buildcrew-dash patch — uv lock instruction present.
@test "experience: release-github instructs uv --project lock for buildcrew-dash" {
    grep -q 'uv --project /Users/joshcarroll/code/buildcrew-dev/buildcrew-dash lock' "$RELEASE_CMD"
}

# Error recovery path: user typos the project name — command instructs clear rejection.
@test "experience: release-github has unknown-project guard with correct message format" {
    grep -q 'Unknown project' "$RELEASE_CMD"
    grep -q 'Valid projects: buildcrew, buildcrew-dash' "$RELEASE_CMD"
}

# Error recovery path: dirty working tree — command stops and asks user, never auto-commits.
@test "experience: release-github stops on dirty tree and asks user" {
    grep -q 'status --porcelain' "$RELEASE_CMD"
    grep -q 'uncommitted changes' "$RELEASE_CMD"
    grep -q 'Do NOT silently' "$RELEASE_CMD"
}

# Happy path: deprecated /release command is gone so users only find the unified command.
@test "experience: old buildcrew /release command has been removed" {
    [ ! -f "/Users/joshcarroll/code/buildcrew-dev/buildcrew/.claude/commands/release.md" ]
}

# Adversarial: command file uses git -C <dir> everywhere — no cd that could break cwd.
@test "experience: release-github contains no cd command (uses git -C throughout)" {
    # grep -c returns 0 when no matches — we want zero matches
    count=$(grep -c '\bcd\b' "$RELEASE_CMD" || true)
    [ "$count" -eq 0 ]
}

# Adversarial: buildcrew-dash pyproject.toml and uv.lock are both at correct version
# after the one-time pre-work fix — a mismatch here would produce a broken first release.
@test "experience: buildcrew-dash pyproject.toml and uv.lock both carry version 0.2.0" {
    grep -q 'version = "0.2.0"' /Users/joshcarroll/code/buildcrew-dev/buildcrew-dash/pyproject.toml
    grep -q 'version = "0.2.0"' /Users/joshcarroll/code/buildcrew-dev/buildcrew-dash/uv.lock
}
