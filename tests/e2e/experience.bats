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
# Task: Increase default UAT_ARTIFACT_TIMEOUT from 1800s to 7200s
# ─────────────────────────────────────────────────────────────────────────────
UAT_SH="$BUILDCREW_ROOT/lib/uat.sh"

# Happy path: user sources uat.sh — the default UAT_ARTIFACT_TIMEOUT is 7200 (2 hours).
@test "experience: UAT_ARTIFACT_TIMEOUT default is 7200 in uat.sh source" {
    grep -q 'UAT_ARTIFACT_TIMEOUT="${UAT_ARTIFACT_TIMEOUT:-7200}"' "$UAT_SH"
}

# Happy path: user overrides UAT_ARTIFACT_TIMEOUT via .buildcrew/config — the override takes effect.
@test "experience: UAT_ARTIFACT_TIMEOUT config override is respected by load_uat_config" {
    source_lib "uat.sh"
    mkdir -p .buildcrew
    echo 'UAT_ARTIFACT_TIMEOUT=3600' > .buildcrew/config
    load_uat_config
    [ "$UAT_ARTIFACT_TIMEOUT" = "3600" ]
}

# Regression guard: old 1800 default is completely gone from uat.sh source.
@test "experience: no residual 1800 default remains in uat.sh" {
    ! grep -q ':-1800' "$UAT_SH"
}

# Adversarial: user puts a non-numeric UAT_ARTIFACT_TIMEOUT in config — it is silently ignored.
@test "experience: non-numeric UAT_ARTIFACT_TIMEOUT in config is rejected" {
    source_lib "uat.sh"
    mkdir -p .buildcrew
    echo 'UAT_ARTIFACT_TIMEOUT=forever' > .buildcrew/config
    UAT_ARTIFACT_TIMEOUT=7200
    load_uat_config
    [ "$UAT_ARTIFACT_TIMEOUT" = "7200" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Task: Wire buildcrew stop signal into batch dispatch loop
# ─────────────────────────────────────────────────────────────────────────────

# Happy path: user runs `buildcrew stop` during batch — the dispatch loop has stop-check code.
# Verifies check_stop_signal is called within _batch_dispatch_loop, not just anywhere in the file.
@test "experience: _batch_dispatch_loop contains check_stop_signal call" {
    grep -q 'check_stop_signal' "$WORKFLOW_SH"
    # Extract function body using sed (from function header to next function at column 0)
    local body
    body=$(sed -n '/^_batch_dispatch_loop()/,/^[a-zA-Z_].*() *{/p' "$WORKFLOW_SH")
    [[ "$body" == *"check_stop_signal"* ]]
}

# Happy path: stop signal detection sets _batch_stopping flag and clears the file.
@test "experience: batch dispatch clears stop signal after detection" {
    local body
    body=$(sed -n '/^_batch_dispatch_loop()/,/^[a-zA-Z_].*() *{/p' "$WORKFLOW_SH")
    [[ "$body" == *"clear_stop_signal"* ]]
    [[ "$body" == *"_batch_stopping=true"* ]]
}

# Happy path: drain mode breaks when running count hits zero.
@test "experience: batch dispatch drain breaks when _batch_running is 0" {
    local body
    body=$(sed -n '/^_batch_dispatch_loop()/,/^[a-zA-Z_].*() *{/p' "$WORKFLOW_SH")
    [[ "$body" == *'_batch_running == 0'* ]]
    [[ "$body" == *'break'* ]]
}

# Happy path: stale stop files cleared before dispatch in both entry points.
@test "experience: enter_batch_mode and _batch_resume both clear stop signal before dispatch" {
    # enter_batch_mode
    local enter_body
    enter_body=$(sed -n '/^enter_batch_mode()/,/^[a-zA-Z_].*() *{/p' "$WORKFLOW_SH")
    [[ "$enter_body" == *"clear_stop_signal"* ]]
    # _batch_resume
    local resume_body
    resume_body=$(sed -n '/^_batch_resume()/,/^[a-zA-Z_].*() *{/p' "$WORKFLOW_SH")
    [[ "$resume_body" == *"clear_stop_signal"* ]]
}

# Happy path: resume hint tells user how to continue after stop.
@test "experience: batch dispatch prints resume hint after stop with skipped tasks" {
    local body
    body=$(sed -n '/^_batch_dispatch_loop()/,/^[a-zA-Z_].*() *{/p' "$WORKFLOW_SH")
    [[ "$body" == *"buildcrew run --batch --resume"* ]]
    [[ "$body" == *"task(s) were not started"* ]]
}

# Error recovery: _batch_stopping flag prevents re-reading stop file every cycle.
@test "experience: _batch_stopping guard prevents repeated stop file checks" {
    local body
    body=$(sed -n '/^_batch_dispatch_loop()/,/^[a-zA-Z_].*() *{/p' "$WORKFLOW_SH")
    [[ "$body" == *'_batch_stopping" != "true"'* ]]
}

# Adversarial: _batch_stopping is local — does not leak state between invocations.
@test "experience: _batch_stopping is declared local in _batch_dispatch_loop" {
    run grep 'local _batch_stopping' "$WORKFLOW_SH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"local _batch_stopping"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Task: Remove --keep-logs flag and KEEP_LOGS variable — always keep logs
# ─────────────────────────────────────────────────────────────────────────────

# Happy path: user runs buildcrew with --keep-logs (deprecated flag) — gets warning, not error.
@test "experience: --keep-logs flag emits deprecation warning without error" {
    run parse_args --keep-logs
    [ "$status" -eq 0 ]
    [[ "$output" == *"deprecated"* ]]
    [[ "$output" == *"always retained"* ]]
}

# Happy path: cleanup_log always keeps the log and tells the user where it is.
@test "experience: cleanup_log always preserves log and reports its path" {
    mkdir -p .buildcrew/logs
    __LOG_FILE=".buildcrew/logs/experience-test.log"
    echo "test log content" > "$__LOG_FILE"
    run cleanup_log 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Activity log saved"* ]]
    [[ "$output" == *"$__LOG_FILE"* ]]
    [ -f "$__LOG_FILE" ]
}

# Happy path: help text does not advertise the removed flag.
@test "experience: --help output has no mention of --keep-logs" {
    run parse_args --help
    [[ "$output" != *"keep-logs"* ]]
}

# Error recovery: user has old .buildcrew/config with KEEP_LOGS=true — gets helpful warning.
@test "experience: old config with KEEP_LOGS=true emits actionable deprecation message" {
    mkdir -p .buildcrew
    echo "KEEP_LOGS=true" > .buildcrew/config
    run load_buildcrew_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"deprecated"* ]]
    [[ "$output" == *"Remove it from your config"* ]]
}

# Adversarial: user passes --keep-logs alongside valid flags — other flags still take effect.
@test "experience: --keep-logs does not interfere with other flags" {
    local stderr_file="$TEST_DIR/experience-stderr.txt"
    parse_args --keep-logs --auto --single 2>"$stderr_file"
    [[ "$(cat "$stderr_file")" == *"deprecated"* ]]
    [ "$AUTO_MODE" = "true" ]
    [ "$SINGLE_TASK" = "true" ]
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

# ─────────────────────────────────────────────────────────────────────────────
# Task: Change AUTO_MODE default to true
# ─────────────────────────────────────────────────────────────────────────────

# Happy path: user runs buildcrew with no flags — AUTO_MODE defaults to true,
# skipping all interactive pauses. This is the new default experience.
@test "experience: default AUTO_MODE is true after sourcing workflow.sh" {
    # AUTO_MODE is set at source time via ${AUTO_MODE:-true}
    [ "$AUTO_MODE" = "true" ]
}

# Happy path: user passes --interactive to restore the old interactive behavior.
# The dashboard sees AUTO_MODE=false, meaning prompts will fire.
@test "experience: --interactive flag sets AUTO_MODE=false for interactive review pauses" {
    parse_args --interactive
    [ "$AUTO_MODE" = "false" ]
    [ "$INTERACTIVE_FLAG" = "true" ]
}

# Happy path: user passes deprecated --auto flag and sees a deprecation warning.
# AUTO_MODE still ends up true (same as default) but with a clear signal to update scripts.
@test "experience: --auto flag emits deprecation warning telling user to use --interactive" {
    run parse_args --auto
    [ "$status" -eq 0 ]
    [[ "$output" == *"--auto is deprecated"* ]]
    [[ "$output" == *"--interactive"* ]]
}

# Happy path: help text documents --interactive and marks --auto as deprecated.
# Users running --help should see the new flag and know --auto is obsolete.
@test "experience: help text shows --interactive and deprecation note for --auto" {
    run parse_args --help
    [[ "$output" == *"--interactive"* ]]
    [[ "$output" == *"deprecated"* ]]
}

# Happy path: --plan --dry-run exits cleanly without launching Claude.
# This was a latent bug (real Claude session launched in dry-run) — now fixed.
@test "experience: --plan --dry-run prints dry-run message and exits 0" {
    run "$BUILDCREW_HOME/lib/workflow.sh" --plan --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN]"* ]]
    [[ "$output" == *"discovery mode"* ]]
}

# Error recovery: user accidentally passes both --auto and --interactive.
# BuildCrew resolves the conflict — --interactive wins because --auto is deprecated.
@test "experience: --auto --interactive conflict warns and resolves to interactive" {
    run parse_args --auto --interactive
    [[ "$output" == *"Both --auto and --interactive"* ]]
    [[ "$output" == *"Using --interactive"* ]]
}

# Adversarial: batch worker exec line no longer passes --auto flag.
# This prevents deprecation spam in CI logs from batch mode workers.
@test "experience: batch worker exec line does not pass --auto flag" {
    # The exec line in _batch_launch_task should have no --auto argument
    run grep 'exec.*workflow\.sh' "$WORKFLOW_SH"
    [[ "$output" != *"--auto"* ]]
}

# Adversarial: batch worker exports AUTO_MODE=true before exec.
# Since --auto is removed from the exec line, AUTO_MODE must be exported directly.
@test "experience: batch worker exports AUTO_MODE=true in environment" {
    grep -q 'export AUTO_MODE=true.*Batch workers' "$WORKFLOW_SH"
}

# Adversarial: no stale AUTO_MODE:-false default remains anywhere in workflow.sh.
# The only default should be AUTO_MODE:-true on line 146.
@test "experience: no stale AUTO_MODE:-false fallback in workflow.sh" {
    count=$(grep -c 'AUTO_MODE:-false' "$WORKFLOW_SH" || true)
    [ "$count" -eq 0 ]
}

# Adversarial: README does not recommend buildcrew run --auto anywhere.
# Since --auto is deprecated, no usage example should suggest it as a primary flag.
@test "experience: README does not have buildcrew run --auto as recommended usage" {
    # Check there's no 'buildcrew run --auto' usage line (uat --auto is separate and OK)
    count=$(grep 'buildcrew run.*--auto' "$BUILDCREW_ROOT/README.md" || true)
    [ -z "$count" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Task: Make enter_batch_mode() the default execution path
# ─────────────────────────────────────────────────────────────────────────────

# Happy path: user runs `buildcrew run` with no flags — batch mode is now default.
# SEQUENTIAL_MODE defaults to false, so the dispatch condition `SEQUENTIAL_MODE != true`
# routes to the batch path.
@test "experience: SEQUENTIAL_MODE defaults to false (batch mode is default)" {
    [ "$SEQUENTIAL_MODE" = "false" ]
}

# Happy path: --sequential flag sets SEQUENTIAL_MODE=true, opting out of batch.
@test "experience: --sequential sets SEQUENTIAL_MODE to true" {
    parse_args --sequential
    [ "$SEQUENTIAL_MODE" = "true" ]
}

# Happy path: --single implicitly sets SEQUENTIAL_MODE=true (single task can't be parallel).
@test "experience: --single implies sequential mode" {
    parse_args --single
    [ "$SINGLE_TASK" = "true" ]
    [ "$SEQUENTIAL_MODE" = "true" ]
}

# Happy path: --task implicitly sets SEQUENTIAL_MODE=true (targeting a specific task is sequential).
@test "experience: --task implies sequential mode" {
    parse_args --task "Fix the bug"
    [ "$TARGET_TASK" = "Fix the bug" ]
    [ "$SEQUENTIAL_MODE" = "true" ]
}

# Happy path: --review implicitly sets SEQUENTIAL_MODE=true (human review requires sequential).
@test "experience: --review implies sequential mode" {
    parse_args --review
    [ "$HUMAN_REVIEW" = "true" ]
    [ "$SEQUENTIAL_MODE" = "true" ]
}

# Happy path: --uat implicitly sets SEQUENTIAL_MODE=true (UAT requires sequential).
@test "experience: --uat implies sequential mode" {
    parse_args --uat
    [ "$UAT_MODE" = "true" ]
    [ "$SEQUENTIAL_MODE" = "true" ]
}

# Happy path: --batch prints deprecation warning (no longer needed, batch is default).
@test "experience: --batch prints deprecation warning about being default now" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --batch"
    [[ "$output" == *"deprecated"* ]]
    [[ "$output" == *"batch mode is now the default"* ]]
}

# Happy path: workflow.sh help text documents --sequential and deprecated --batch.
@test "experience: workflow.sh --help documents --sequential flag" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --help"
    [[ "$output" == *"--sequential"* ]]
    [[ "$output" == *"opt out of parallel batch mode"* ]]
}

@test "experience: workflow.sh --help marks --batch as deprecated" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --help"
    [[ "$output" == *"--batch"* ]]
    [[ "$output" == *"deprecated"* ]]
}

# Happy path: bin/buildcrew help text documents --sequential and deprecated --batch.
@test "experience: bin/buildcrew help documents --sequential flag" {
    run "$BUILDCREW_ROOT/bin/buildcrew" help
    [[ "$output" == *"--sequential"* ]]
}

@test "experience: bin/buildcrew help marks --batch as deprecated" {
    run "$BUILDCREW_ROOT/bin/buildcrew" help
    [[ "$output" == *"--batch"* ]]
    [[ "$output" == *"deprecated"* ]]
}

# Happy path: README documents --sequential and deprecated --batch in run options.
@test "experience: README.md documents --sequential flag" {
    grep -q '\-\-sequential' "$BUILDCREW_ROOT/README.md"
}

@test "experience: README.md marks --batch as deprecated" {
    grep -q '\-\-batch.*deprecated\|deprecated.*\-\-batch' "$BUILDCREW_ROOT/README.md"
}

# Happy path: main() dispatch uses SEQUENTIAL_MODE != true (not BATCH_MODE == true).
# This is the core behavioral change — batch is the default path.
@test "experience: main() dispatch condition checks SEQUENTIAL_MODE not BATCH_MODE" {
    # The dispatch gate should be SEQUENTIAL_MODE != true, not BATCH_MODE == true
    grep -q 'if \[\[ "\$SEQUENTIAL_MODE" != "true" \]\]' "$WORKFLOW_SH"
    # Old BATCH_MODE dispatch gate should be gone
    ! grep -q 'if \[\[ "\$BATCH_MODE" == "true" \]\]' "$WORKFLOW_SH"
}

# Happy path: batch mode prints info line about parallel mode.
@test "experience: batch mode prints parallel mode info line" {
    grep -q 'Running in parallel mode (unattended). Use --sequential for interactive mode.' "$WORKFLOW_SH"
}

# Happy path: flag forwarding in _batch_launch_task uses == true comparison (not :+).
# The old ${VAR:+--flag} pattern fires for any non-empty value including "false".
@test "experience: flag forwarding uses == true comparison not colon-plus expansion" {
    # Verify the corrected pattern
    grep -q '\[\[ "\$SKIP_SPEC" == "true" \]\] && echo "--skip-spec"' "$WORKFLOW_SH"
    grep -q '\[\[ "\$FULL_PIPELINE" == "true" \]\] && echo "--full-pipeline"' "$WORKFLOW_SH"
    grep -q '\[\[ "\$VERBOSE" == "true" \]\] && echo "--verbose"' "$WORKFLOW_SH"
    # Verify the old broken pattern is gone
    ! grep -q '${SKIP_SPEC:+--skip-spec}' "$WORKFLOW_SH"
    ! grep -q '${FULL_PIPELINE:+--full-pipeline}' "$WORKFLOW_SH"
    ! grep -q '${VERBOSE:+--verbose}' "$WORKFLOW_SH"
}

# Error recovery: dirty worktree error message mentions --sequential as the opt-out.
@test "experience: dirty worktree error suggests --sequential as opt-out" {
    grep -q 'Commit or stash changes first, or use --sequential' "$WORKFLOW_SH"
}

# Adversarial: user passes --batch --sequential — both flags process without conflict.
# --batch prints deprecation, --sequential sets SEQUENTIAL_MODE=true, sequential wins.
@test "experience: --batch --sequential combo processes without error" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --batch --sequential 2>&1"
    [[ "$output" == *"deprecated"* ]]
    # Can't check SEQUENTIAL_MODE in subshell, but no crash is the assertion
    [ "$status" -eq 0 ] || [ "$status" -eq 143 ] # 143 = SIGTERM from help exit
}

# Adversarial: user passes --batch --single — both flags process, --single forces sequential.
@test "experience: --batch --single combo processes without error" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --batch --single 2>&1"
    [[ "$output" == *"deprecated"* ]]
}

# Adversarial: user passes --single --review (multiple sequential-forcing flags).
# Both should set their respective flags AND SEQUENTIAL_MODE=true.
@test "experience: multiple sequential-forcing flags all set SEQUENTIAL_MODE" {
    parse_args --single --review
    [ "$SINGLE_TASK" = "true" ]
    [ "$HUMAN_REVIEW" = "true" ]
    [ "$SEQUENTIAL_MODE" = "true" ]
}

# Adversarial: --task-exact also forces sequential mode.
@test "experience: --task-exact implies sequential mode" {
    parse_args --task-exact "Fix the bug"
    [ "$TARGET_TASK_EXACT" = "Fix the bug" ]
    [ "$SINGLE_TASK" = "true" ]
    [ "$SEQUENTIAL_MODE" = "true" ]}
}

# ─────────────────────────────────────────────────────────────────────────────
# Task: Orchestrator-driven interview for spec phase
# ─────────────────────────────────────────────────────────────────────────────
SPEC_SKILL="$BUILDCREW_ROOT/skills/buildcrew-spec/SKILL.md"

# Happy path: user runs buildcrew with a task that has ambiguities — spec skill
# defines the three-path assessment (Clear / Needs probing / Insufficient clarity).
@test "experience: spec SKILL.md defines three clarity assessment paths" {
    grep -q '^\*\*Clear\*\*' "$SPEC_SKILL"
    grep -q '^\*\*Needs probing\*\*' "$SPEC_SKILL"
    grep -q '^\*\*Insufficient clarity\*\*' "$SPEC_SKILL"
}

# Happy path: spec skill defines the second-pass detection marker so the orchestrator
# can inject answers and the spec agent knows to incorporate them.
@test "experience: spec SKILL.md has BUILDCREW_INTERVIEW_ANSWERS marker detection" {
    grep -q '\[BUILDCREW_INTERVIEW_ANSWERS\]' "$SPEC_SKILL"
    grep -q 'Interview Answers (Second Pass)' "$SPEC_SKILL"
}

# Happy path: CLAUDE.md phase result contract shows needs_probing for spec phase.
@test "experience: CLAUDE.md spec verdicts include needs_probing" {
    run grep 'spec' "$BUILDCREW_ROOT/CLAUDE.md"
    [[ "$output" == *'needs_probing'* ]]
}

# Happy path: workflow.sh has the elif branch wiring needs_probing to the interview handler.
@test "experience: workflow.sh handles needs_probing verdict via handle_spec_interview" {
    grep -q 'elif \[\[.*spec_verdict.*needs_probing' "$WORKFLOW_SH"
    grep -q 'handle_spec_interview "\$task"' "$WORKFLOW_SH"
}

# Happy path: handle_spec_interview function exists and is callable after sourcing.
@test "experience: handle_spec_interview function exists in workflow.sh" {
    run type handle_spec_interview
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

# Happy path: __is_interactive helper is defined (extracted for testability).
@test "experience: __is_interactive testability helper exists" {
    run type __is_interactive
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

# Happy path: AUTO_MODE guard in handle_spec_interview skips interview gracefully.
# Simulates CI / non-interactive batch mode where no user is present.
@test "experience: handle_spec_interview in AUTO_MODE skips without error" {
    export AUTO_MODE="true"
    mkdir -p .claude
    PHASE_RESULT_FILE="$TEST_DIR/.claude/phase-result.json"
    cat > "$PHASE_RESULT_FILE" << 'EOF'
{"phase":"spec","verdict":"needs_probing","details":"test","questions":["Q1?","Q2?"]}
EOF
    run handle_spec_interview "test task"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Auto mode: skipping spec interview"* ]]
}

# Error recovery: spec skill defines the needs_probing phase-result.json format
# including the questions array — so agents write machine-parseable output.
@test "experience: spec SKILL.md has needs_probing JSON example with questions array" {
    grep -q '"needs_probing"' "$SPEC_SKILL"
    grep -q '"questions"' "$SPEC_SKILL"
    grep -q 'Should expired sessions' "$SPEC_SKILL"
}

# Adversarial: spec SKILL.md second-pass instructions explicitly forbid emitting
# needs_probing again — prevents infinite interview loops.
@test "experience: spec SKILL.md forbids needs_probing on second pass" {
    grep -q 'do NOT emit.*needs_probing.*on.*second pass' "$SPEC_SKILL" || \
    grep -q 'do NOT emit `needs_probing` on a second pass' "$SPEC_SKILL"
}

# Adversarial: User Decisions section in spec template is conditional on second pass.
# First-pass specs must not contain an empty User Decisions section.
@test "experience: spec SKILL.md User Decisions section is conditional" {
    grep -q '## User Decisions' "$SPEC_SKILL"
    grep -q 'Omit this section entirely on first pass' "$SPEC_SKILL" || \
    grep -q 'Only include this section on second pass' "$SPEC_SKILL"
}

# Adversarial: handle_spec_interview with empty questions array does NOT prompt user
# or call run_phase_group — verifies the empty-questions guard fires early.
@test "experience: handle_spec_interview with empty questions does not re-invoke spec" {
    mkdir -p .claude
    PHASE_RESULT_FILE="$TEST_DIR/.claude/phase-result.json"
    export VERBOSE=true
    cat > "$PHASE_RESULT_FILE" << 'EOF'
{"phase":"spec","verdict":"needs_probing","details":"unclear","questions":[]}
EOF
    run handle_spec_interview "test task"
    [ "$status" -eq 0 ]
    [[ "$output" == *"needs_probing verdict but no questions"* ]]
}

# Adversarial: workflow.sh spec handling block properly sequences: vague check first,
# then needs_probing, then fallthrough — incorrect ordering would skip interviews.
@test "experience: workflow.sh spec verdict checks are in correct order (vague before needs_probing)" {
    # The vague check must come BEFORE needs_probing in the if/elif chain
    local vague_line needs_probing_line
    vague_line=$(grep -n 'spec_verdict.*==.*"vague"' "$WORKFLOW_SH" | head -1 | cut -d: -f1)
    needs_probing_line=$(grep -n 'spec_verdict.*==.*"needs_probing"' "$WORKFLOW_SH" | head -1 | cut -d: -f1)
    [ -n "$vague_line" ]
    [ -n "$needs_probing_line" ]
    [ "$vague_line" -lt "$needs_probing_line" ]
}