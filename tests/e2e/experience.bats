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

# ─────────────────────────────────────────────────────────────────────────────
# Task: Persona dispatch for /buildcrew command and buildcrew skill
# ─────────────────────────────────────────────────────────────────────────────
BUILDCREW_CMD="/Users/joshcarroll/code/buildcrew-dev/buildcrew/commands/buildcrew.md"
BUILDCREW_SKILL="/Users/joshcarroll/code/buildcrew-dev/buildcrew/skills/buildcrew/SKILL.md"

# HP-06 / EDGE-07: command file slug table contains all 6 valid persona slugs.
@test "experience: buildcrew command file contains all 6 persona slugs in slug table" {
    grep -q 'product-manager' "$BUILDCREW_CMD"
    grep -q 'principal-engineer' "$BUILDCREW_CMD"
    grep -q 'feature-engineer' "$BUILDCREW_CMD"
    grep -q 'qa-engineer' "$BUILDCREW_CMD"
    grep -q 'security-engineer' "$BUILDCREW_CMD"
    grep -q 'ux-designer' "$BUILDCREW_CMD"
}

# HP-06 / EDGE-07: SKILL.md slug table contains the same 6 persona slugs — tables must stay in sync (AC-10).
@test "experience: buildcrew SKILL.md contains all 6 persona slugs matching command file" {
    grep -q 'product-manager' "$BUILDCREW_SKILL"
    grep -q 'principal-engineer' "$BUILDCREW_SKILL"
    grep -q 'feature-engineer' "$BUILDCREW_SKILL"
    grep -q 'qa-engineer' "$BUILDCREW_SKILL"
    grep -q 'security-engineer' "$BUILDCREW_SKILL"
    grep -q 'ux-designer' "$BUILDCREW_SKILL"
}

# ERR-01: command file persona mode error instructs user to run install.sh — ensures
# users with missing rules files see an actionable message, not a silent failure.
@test "experience: buildcrew command file error message references install.sh" {
    grep -q 'install.sh' "$BUILDCREW_CMD"
}

# ERR-03: SKILL.md persona mode error also references install.sh — both dispatch
# paths must carry the same recovery instruction (AC-07a/b).
@test "experience: buildcrew SKILL.md error message references install.sh" {
    grep -q 'install.sh' "$BUILDCREW_SKILL"
}

# Adversarial: command file must NOT contain phase-isolation or allowed-tools keys —
# command files have a different frontmatter schema than skill files (AC-12).
@test "experience: buildcrew command file frontmatter has no phase-isolation or allowed-tools keys" {
    # Extract frontmatter block (between first two --- lines) and check it contains neither key
    frontmatter=$(awk '/^---/{c++; if(c==2) exit} c==1' "$BUILDCREW_CMD")
    ! echo "$frontmatter" | grep -q 'phase-isolation'
    ! echo "$frontmatter" | grep -q 'allowed-tools'
}

# Adversarial: SKILL.md must NOT contain ## Current Task section — confirms the old
# entry-point section was removed and replaced with ## Prompt Dispatch.
@test "experience: buildcrew SKILL.md does not contain old ## Current Task section" {
    ! grep -q '## Current Task' "$BUILDCREW_SKILL"
}

# Happy path: SKILL.md contains ## Prompt Dispatch section — confirms new dispatch
# logic is present and the pipeline entry-point wording is updated.
@test "experience: buildcrew SKILL.md contains ## Prompt Dispatch section" {
    grep -q '## Prompt Dispatch' "$BUILDCREW_SKILL"
}
