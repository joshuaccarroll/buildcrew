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

    # Inject project context files if they exist
    local project_context=""
    for ctx_file in .buildcrew/context/users.md .buildcrew/context/principles.md .buildcrew/context/domain.md; do
        if [[ -f "$ctx_file" ]]; then
            project_context+="$(cat "$ctx_file")"$'\n\n'
        fi
    done
    if [[ -n "$project_context" ]]; then
        local ctx_size=${#project_context}
        if (( ctx_size > 10240 )); then
            project_context="${project_context:0:10240}"$'\n\n[truncated]'
        fi
    fi

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
   - Prompt: "You are a researcher. Read rules/core-principles.md for your standards. Research the task and create an implementation plan. Write findings to .claude/research.md and plan to .claude/current-plan.md. Apply the Rule of Five self-revision (5 full passes) to the plan. When done, report back with a summary."

2. **principal-engineer** — Handles Phase 3 (Plan Review) and Phase 5 (Code Review)
   - Prompt: "You are a Principal Engineer. Read rules/core-principles.md for your standards. For plan review: perform a 3-pass review (technical, user impact, convergence) of .claude/current-plan.md and write results to .claude/plan-review.md. For code review: review all changed code and write results to .claude/code-review.md. Report verdicts clearly."

3. **feature-engineer** — Handles Phase 4 (Build)
   - Prompt: "You are a Feature Engineer. Read rules/core-principles.md for your standards. Implement the approved plan in .claude/current-plan.md. Follow existing code patterns. Make small, focused changes. Do NOT proceed until the team lead confirms the plan is approved. Report when implementation is complete."

4. **qa-engineer** — Handles Phase 7 (Test)
   - Prompt: "You are a Senior QA Engineer. Read rules/core-principles.md for your standards. Create a test plan in .claude/current-test-plan.md (apply Rule of Five self-revision). Write and run tests. Write results to .claude/test-report.md. Report pass/fail status."

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

    # Start file watcher that sends SIGINT when workflow-status.json appears
    (
        while true; do
            if [[ -f "$STATUS_FILE" ]]; then
                sleep 2
                pkill -INT -f "claude.*BuildCrew Team Lead" 2>/dev/null || true
                break
            fi
            sleep 1
        done
    ) &
    local monitor_pid=$!

    claude "$prompt" --max-turns "$MAX_TURNS" || true

    # Clean up monitor
    kill $monitor_pid 2>/dev/null || true
    wait $monitor_pid 2>/dev/null || true

    # Check completion status (same logic as legacy mode)
    if [[ -f "$STATUS_FILE" ]]; then
        if ! jq -e . "$STATUS_FILE" >/dev/null 2>&1; then
            print_error "Status file contains invalid JSON"
            mark_task_blocked "$task" "Invalid status file JSON"
            return 1
        fi

        local status
        status=$(jq -r '.status // ""' "$STATUS_FILE")

        case "$status" in
            complete)
                local summary
                summary=$(jq -r '.summary // "No summary provided"' "$STATUS_FILE")
                mark_task_complete "$task"
                print_success "Completed: $task"
                print_info "Summary: $summary"
                ;;
            blocked)
                local reason
                reason=$(jq -r '.reason // "Unknown reason"' "$STATUS_FILE")
                mark_task_blocked "$task" "$reason"
                print_warning "Blocked: $task"
                print_warning "Reason: $reason"
                return 1
                ;;
            "")
                print_error "Status file missing 'status' field"
                mark_task_blocked "$task" "Missing status in response"
                return 1
                ;;
            *)
                print_error "Unexpected status value: $status"
                mark_task_blocked "$task" "Unknown status: $status"
                return 1
                ;;
        esac
    else
        print_warning "No status file found - assuming task needs attention"
        mark_task_blocked "$task" "No status file"
        return 1
    fi
}
