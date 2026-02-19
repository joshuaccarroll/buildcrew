#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BuildCrew - Agent Teams Mode (Experimental)
# ═══════════════════════════════════════════════════════════════════════════════
#
# This module provides an alternative processing mode using Claude Code's
# experimental agent teams feature. Instead of 5 sequential Claude invocations,
# a single team lead coordinates multiple teammates.
#
# Prerequisites:
#   - CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 must be set in the environment
#
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────────
# Prerequisites check
# ─────────────────────────────────────────────────────────────────────────────────

check_teams_prerequisites() {
    if [[ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" != "1" ]]; then
        print_error "Agent teams requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
        print_info "Set it with: export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────────
# Build the team lead prompt
# ─────────────────────────────────────────────────────────────────────────────────

build_team_lead_prompt() {
    local task="$1"

    # Load project context (with teams-specific fallback for empty)
    local project_context
    project_context=$(load_project_context)
    project_context="${project_context:-No project context files found.}"

    cat <<PROMPT
You are the **BuildCrew Team Lead**. You coordinate a team of specialist agents to complete a development task through the full BuildCrew workflow.

## Task
$task

## Project Context
${project_context:-No project context files found.}

## Your Role
You are the COORDINATOR. You must NOT implement code yourself. Delegate ALL implementation, review, and testing to your teammates. Your job is to:
1. Create a team and spawn the right teammates
2. Assign work to each teammate
3. Monitor progress and quality gates
4. Handle retries and escalations
5. Write the final status file when done

## Teammates to Spawn

Create a team and spawn these teammates:

1. **researcher** — Handles Phases 1-2 (Research + Plan)
   - Prompt: "You are a researcher. Read rules/core-principles.md for your standards. Research the task and create an implementation plan. Write findings to .claude/research.md and plan to .claude/current-plan.md. After writing each document, re-read it from scratch and revise it. Repeat up to 5 times or until no meaningful improvements remain. When done, report back with a summary."

2. **principal-engineer** — Handles Phase 3 (Plan Review) and Phase 5 (Code Review)
   - Prompt: "You are a Principal Engineer. Read rules/core-principles.md for your standards. For plan review: perform a 3-pass review (technical, user impact, convergence) of .claude/current-plan.md and write results to .claude/plan-review.md. For code review: review all changed code and write results to .claude/code-review.md. Report verdicts clearly."

3. **feature-engineer** — Handles Phase 4 (Build)
   - Prompt: "You are a Feature Engineer. Read rules/core-principles.md for your standards. Implement the approved plan in .claude/current-plan.md. Follow existing code patterns. Make small, focused changes. Do NOT proceed until the team lead confirms the plan is approved. Report when implementation is complete."

4. **qa-engineer** — Handles Phase 7 (Test)
   - Prompt: "You are a Senior QA Engineer. Read rules/core-principles.md for your standards. Create a test plan in .claude/current-test-plan.md. After writing the test plan, re-read it from scratch and revise it. Repeat up to 5 times or until no meaningful improvements remain. Write and run tests. Write results to .claude/test-report.md. Report pass/fail status."

5. **security-engineer** — Handles security audit in Phase 8 (Verify)
   - Prompt: "You are a Security Engineer. Read rules/core-principles.md for your standards. Perform OWASP Top 10 scan, secrets detection, input validation review, and dependency audit on all changed code. Write findings to .claude/security-audit.md. Report any blocking issues."

## Workflow Phases (in order)

### Phase 1-2: Research + Plan
- Assign to: researcher
- Wait for completion before proceeding
- Researcher writes .claude/research.md and .claude/current-plan.md

### Phase 3: Plan Review
- Assign to: principal-engineer
- Send them .claude/current-plan.md for 3-pass review
- If NEEDS_REVISION: have the researcher revise the plan, then re-review (max 3 cycles)
- If REJECTED: mark task as blocked
- If APPROVED: proceed to build

### Phase 4: Build
- Assign to: feature-engineer
- Only after plan is APPROVED
- Wait for completion

### Phase 5-6: Code Review + Refactor
- Assign to: principal-engineer
- If NEEDS_REFACTOR: send issues back to feature-engineer to fix, then re-review
- If NEEDS_REBUILD: send back to feature-engineer with context to rebuild from plan
- If APPROVED: proceed to test

### Phase 7: Test
- Assign to: qa-engineer
- Wait for test results
- If tests fail: send failures to feature-engineer to fix, re-test (max 3 attempts)

### Phase 8: Verify
- Assign to: security-engineer for security audit
- Also verify: tests pass, code review approved, no blocking issues
- Write .claude/verify-report.md

### Phase 9: Commit
- Tell the feature-engineer to: git add all relevant files and commit with conventional commit format
- Do NOT push (local only)
- Do NOT create, switch, or delete branches (the orchestrator manages branching)

### Phase 10: Signal Completion
- IMPORTANT: Before writing the status file, shut down ALL teammates and clean up the team
- Then write .claude/workflow-status.json:

On success:
\`\`\`json
{
  "status": "complete",
  "task": "$task",
  "summary": "[brief summary]",
  "files_changed": ["list", "of", "files"],
  "reviews_passed": {
    "plan_review": true,
    "code_review": true,
    "tests": true,
    "security_audit": true,
    "verify": true
  }
}
\`\`\`

On failure:
\`\`\`json
{
  "status": "blocked",
  "task": "$task",
  "reason": "[why it failed]",
  "phase_blocked": "[which phase]"
}
\`\`\`

## Quality Gates
- Plan must be APPROVED before build starts
- Code review must pass before testing
- All tests must pass
- No critical/high security vulnerabilities
- Maximum retry limits: 3 plan review cycles, 2 build attempts, 3 test fix attempts

## Critical Instructions
1. You are the coordinator — delegate everything, implement nothing
2. Wait for each phase to complete before starting the next
3. Shut down ALL teammates BEFORE writing .claude/workflow-status.json
4. The workflow-status.json file signals the orchestrator to terminate this session
PROMPT
}

# ─────────────────────────────────────────────────────────────────────────────────
# Process a task using agent teams
# ─────────────────────────────────────────────────────────────────────────────────

process_task_teams() {
    local task="$1"

    print_info "Running in agent teams mode (experimental)"

    # Clean up artifacts from any previous task
    rm -f .claude/research.md .claude/current-plan.md .claude/plan-review.md \
          .claude/code-review.md .claude/test-report.md .claude/security-audit.md \
          .claude/verify-report.md .claude/current-test-plan.md \
          "$PHASE_RESULT_FILE" "$STATUS_FILE"

    local prompt
    prompt=$(build_team_lead_prompt "$task")

    start_file_monitor "$STATUS_FILE" "claude.*BuildCrew Team Lead"

    claude -p "$prompt" --max-turns "$MAX_TURNS" || true

    stop_file_monitor

    # Check completion status
    if parse_status_file "$STATUS_FILE"; then
        case "$__STATUS_RESULT" in
            complete)
                mark_task_complete "$task"
                print_success "Completed: $task"
                print_info "Summary: $__STATUS_SUMMARY"
                ;;
            blocked)
                mark_task_blocked "$task" "$__STATUS_REASON"
                print_warning "Blocked: $task"
                print_warning "Reason: $__STATUS_REASON"
                return 1
                ;;
        esac
    else
        case "$__STATUS_RESULT" in
            error)
                print_error "$__STATUS_REASON"
                mark_task_blocked "$task" "$__STATUS_REASON"
                return 1
                ;;
        esac
    fi
}
