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

# ─────────────────────────────────────────────────────────────────────────────
# Task: Reframe circuit breaker re-plan prompts with "scrap and reimagine"
# ─────────────────────────────────────────────────────────────────────────────
WORKFLOW_SH="$BUILDCREW_ROOT/lib/workflow.sh"

# HP-01: All 7 circuit breaker assignments use the new directive ending.
@test "experience: exactly 7 circuit breaker prompts contain scrap-and-reimagine directive" {
    count=$(grep -c 'scrap this and implement the elegant solution' "$WORKFLOW_SH")
    [ "$count" -eq 7 ]
}

# HP-02: 5 non-outcome occurrences use standard phrasing without spec reference.
@test "experience: 5 circuit breaker prompts use standard directive (no spec ref)" {
    count=$(grep 'Knowing everything you know now, scrap this' "$WORKFLOW_SH" | grep -vc 'spec')
    [ "$count" -eq 5 ]
}

# HP-03: 2 outcome occurrences preserve the spec reference before the directive.
@test "experience: 2 outcome circuit breakers preserve spec reference before directive" {
    count=$(grep -c 'Re-read the spec in .claude/spec.md. Knowing everything you know now, scrap this' "$WORKFLOW_SH")
    [ "$count" -eq 2 ]
    # Both must be outcome-related
    non_outcome=$(grep 'Re-read the spec in .claude/spec.md. Knowing everything' "$WORKFLOW_SH" | grep -vc 'Outcome verification' || true)
    [ "$non_outcome" -eq 0 ]
}

# HP-04 through HP-09: Each circuit breaker's leading context is intact.
@test "experience: plan review circuit breaker has correct leading context" {
    grep -q 'Plan review failed twice.*Previous approach:.*failure_summary.*Knowing everything' "$WORKFLOW_SH"
}

@test "experience: code review circuit breaker has correct leading context" {
    grep -q 'Code review NEEDS_REBUILD twice.*Previous failure:.*failure_summary.*Knowing everything' "$WORKFLOW_SH"
}

@test "experience: build/test circuit breaker has correct leading context" {
    grep -q 'Build/test failed twice.*Previous failure:.*failure_summary.*Knowing everything' "$WORKFLOW_SH"
}

@test "experience: smoke test circuit breaker has correct leading context" {
    grep -q 'Smoke test NEEDS_REBUILD twice.*Failure:.*failure_summary.*Knowing everything' "$WORKFLOW_SH"
}

@test "experience: outcome circuit breakers have correct leading context with Unmet criteria" {
    count=$(grep -c 'Outcome verification failed twice.*Unmet criteria:.*failure_summary.*Re-read the spec' "$WORKFLOW_SH")
    [ "$count" -eq 2 ]
}

@test "experience: verify circuit breaker uses failure_details variable (not failure_summary)" {
    grep -q 'Verification failed twice on.*failing.*failure_details.*Knowing everything' "$WORKFLOW_SH"
}

# REG-01 through REG-05: Old directive sentences are completely removed.
@test "experience: no old directive 'Try a fundamentally different approach' remains" {
    ! grep -q 'Try a fundamentally different approach' "$WORKFLOW_SH"
}

@test "experience: no old directive 're-plan with a different strategy' remains" {
    ! grep -q 're-plan with a different strategy' "$WORKFLOW_SH"
}

@test "experience: no old directive 'Re-plan with a different implementation strategy' remains" {
    ! grep -q 'Re-plan with a different implementation strategy' "$WORKFLOW_SH"
}

@test "experience: no old directive 'and plan differently' remains" {
    ! grep -q 'and plan differently' "$WORKFLOW_SH"
}

@test "experience: no old directive 'Plan a different approach that avoids this issue' remains" {
    ! grep -q 'Plan a different approach that avoids this issue' "$WORKFLOW_SH"
}

# EDGE-01: No line has the directive phrase duplicated.
@test "experience: no line contains duplicate 'Knowing everything' phrase" {
    count=$(grep -c 'Knowing everything.*Knowing everything' "$WORKFLOW_SH" || true)
    [ "$count" -eq 0 ]
}

# EDGE-02: Spec reference appears only in outcome circuit breakers.
@test "experience: spec reference in replan context appears only in outcome lines" {
    # Lines containing both "spec" and "scrap" in __replan_context
    spec_scrap_lines=$(grep '__replan_context=.*spec.*scrap\|__replan_context=.*scrap.*spec' "$WORKFLOW_SH" | wc -l | tr -d ' ')
    [ "$spec_scrap_lines" -eq 2 ]
    # All such lines must mention "Outcome verification"
    non_outcome=$(grep '__replan_context=.*spec.*scrap\|__replan_context=.*scrap.*spec' "$WORKFLOW_SH" | grep -vc 'Outcome verification' || true)
    [ "$non_outcome" -eq 0 ]
}

# Adversarial: someone accidentally pastes the directive twice in a single assignment.
@test "experience: no circuit breaker line contains 'elegant solution' more than once" {
    dupes=$(grep 'CIRCUIT BREAKER:' "$WORKFLOW_SH" | grep -c 'elegant solution.*elegant solution' || true)
    [ "$dupes" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Task: Inject compressed skill catalog into every phase context
# ─────────────────────────────────────────────────────────────────────────────
COMMON_SH="$BUILDCREW_ROOT/lib/common.sh"

# Happy path: build_skill_catalog function exists and is callable after sourcing common.sh.
@test "experience: build_skill_catalog function exists in common.sh" {
    source_lib "common.sh"
    run type build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

# Happy path: workflow.sh calls build_skill_catalog between project context and stty save.
# SMOKE-01: integration wiring is correct — catalog injected into prompt with correct label.
@test "experience: workflow.sh injects skill catalog between project context and stty save" {
    # Verify the block exists in the right position (after project context fi, before stty save)
    run awk '/Inject skill catalog/,/Save terminal state/' "$WORKFLOW_SH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"build_skill_catalog"* ]]
    [[ "$output" == *'Skill Catalog:'* ]]
}

# Happy path: catalog outputs "Available Skills:" header when skills are found.
@test "experience: build_skill_catalog outputs Available Skills header with real skills" {
    source_lib "common.sh"
    # Use the actual BUILDCREW_HOME skills directory (which has real skills)
    export BUILDCREW_HOME="$BUILDCREW_ROOT"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == "Available Skills:"* ]]
}

# Happy path: catalog discovers real buildcrew skills from BUILDCREW_HOME.
@test "experience: build_skill_catalog discovers buildcrew-spec skill from source" {
    source_lib "common.sh"
    export BUILDCREW_HOME="$BUILDCREW_ROOT"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"- buildcrew-spec:"* ]]
}

# Error recovery: function returns 0 even when BUILDCREW_HOME is garbage path.
@test "experience: build_skill_catalog returns 0 with invalid BUILDCREW_HOME" {
    source_lib "common.sh"
    export BUILDCREW_HOME="/nonexistent/path/that/does/not/exist"
    run build_skill_catalog
    [ "$status" -eq 0 ]
}

# Adversarial: workflow.sh catalog injection does not add empty header when no skills found.
@test "experience: workflow.sh catalog injection guards against empty catalog" {
    # The if-block around the injection means an empty catalog adds nothing to prompt
    run grep -A2 'skill_catalog=$(build_skill_catalog)' "$WORKFLOW_SH"
    [ "$status" -eq 0 ]
    [[ "$output" == *'if [[ -n "$skill_catalog" ]]'* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Task: Change TDD_MODE default to true
# ─────────────────────────────────────────────────────────────────────────────

# SMOKE-01: workflow.sh help text shows both TDD flags
@test "experience: workflow.sh help shows deprecated --tdd and --no-tdd flags" {
    run bash "$WORKFLOW_SH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--tdd"* ]]
    [[ "$output" == *"(deprecated)"* ]]
    [[ "$output" == *"--no-tdd"* ]]
}

# SMOKE-02: bin/buildcrew help text shows both TDD flags
@test "experience: bin/buildcrew help shows deprecated --tdd and --no-tdd flags" {
    run bash "$BUILDCREW_ROOT/bin/buildcrew" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--tdd"* ]]
    [[ "$output" == *"(deprecated)"* ]]
    [[ "$output" == *"--no-tdd"* ]]
}

# SMOKE-04: --tdd deprecation warning emitted to stderr
@test "experience: --tdd flag emits deprecation warning to stderr" {
    # Run workflow.sh with --tdd; it will fail after the warning (no backlog) but
    # the deprecation warning in the main guard fires before main() is reached
    run bash "$WORKFLOW_SH" --tdd 2>&1
    [[ "$output" == *"WARNING: --tdd is deprecated"* ]]
    [[ "$output" == *"Use --no-tdd to disable"* ]]
}

# SMOKE-05: --skip-spec + --tdd errors out
@test "experience: --skip-spec with explicit --tdd errors with incompatibility message" {
    run bash "$WORKFLOW_SH" --skip-spec --tdd 2>&1
    [ "$status" -ne 0 ]
    [[ "$output" == *"Error: TDD mode requires spec phase"* ]]
    [[ "$output" == *"--no-tdd"* ]]
}

# SMOKE-06: --skip-spec auto-disables default TDD
@test "experience: --skip-spec alone auto-disables default TDD with note" {
    run bash "$WORKFLOW_SH" --skip-spec 2>&1
    [[ "$output" == *"Note: TDD mode auto-disabled"* ]]
}

# SMOKE-07: env var TDD_MODE=true + --skip-spec errors out
@test "experience: env var TDD_MODE=true with --skip-spec errors out" {
    run env TDD_MODE=true bash "$WORKFLOW_SH" --skip-spec 2>&1
    [ "$status" -ne 0 ]
    [[ "$output" == *"Error: TDD mode requires spec phase"* ]]
}

# SMOKE-08: config TDD_MODE=true + --skip-spec errors out
@test "experience: config TDD_MODE=true with --skip-spec errors out" {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.buildcrew"
    echo "TDD_MODE=true" > "$tmpdir/.buildcrew/config"
    run bash -c "cd '$tmpdir' && bash '$WORKFLOW_SH' --skip-spec 2>&1"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Error: TDD mode requires spec phase"* ]]
    rm -rf "$tmpdir"
}

# Happy path: README documents TDD as default-on with --no-tdd opt-out
@test "experience: README documents TDD as default-on with --no-tdd opt-out" {
    grep -q 'enabled by default' "$BUILDCREW_ROOT/README.md"
    grep -q '\-\-no-tdd' "$BUILDCREW_ROOT/README.md"
}

# Happy path: config.example heredoc includes TDD_MODE entry
@test "experience: config.example heredoc in bin/buildcrew includes TDD_MODE" {
    grep -q 'TDD_MODE' "$BUILDCREW_ROOT/bin/buildcrew"
}

# Adversarial: passing --no-tdd should NOT produce deprecation warning
@test "experience: --no-tdd does not emit deprecation warning" {
    run bash "$WORKFLOW_SH" --no-tdd 2>&1
    [[ "$output" != *"WARNING: --tdd is deprecated"* ]]
}
