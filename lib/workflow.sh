#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BuildCrew - Autonomous Claude Code Development Pipeline
# https://github.com/joshuaccarroll/buildcrew
# ═══════════════════════════════════════════════════════════════════════════════
#
# This script orchestrates an autonomous development workflow using Claude Code.
# It reads tasks from BACKLOG.md and processes each one through phase groups:
#
# Phase-isolated mode (5 separate Claude invocations):
#   1. Research + Plan
#   2. Plan Review (3-pass)
#   3. Build
#   4. Code Review + Refactor + Test
#   5. Verify + Security Audit + Commit + Signal
#
# Legacy mode (single Claude invocation with all phases):
#   Plan → Plan Review → Build → Code Review → Test → Commit
#
# Usage:
#   buildcrew run              # Run in foreground (visible terminal)
#   buildcrew run --dry-run    # Show what would be done without executing
#   buildcrew run --single     # Process only one task then exit
#
# Prerequisites:
#   - Claude Code CLI installed and authenticated
#   - jq installed for JSON parsing
#   - BACKLOG.md file in the project root
#
# Assumption: The working tree is clean at the start of each task.
# BuildCrew commits after each task, so this holds for multi-task runs.
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────────

BACKLOG_FILE="BACKLOG.md"
STATUS_FILE=".claude/workflow-status.json"
PHASE_RESULT_FILE=".claude/phase-result.json"
STOP_FILE=".buildcrew/.stop-workflow"
MAX_TURNS=100
PAUSE_BETWEEN_TASKS=5

# Max turns per phase group (used in isolated mode)
# Uses a function instead of declare -A for bash 3.2 (macOS) compatibility
get_phase_max_turns() {
    case "$1" in
        research) echo 40 ;;
        review)   echo 40 ;;
        build)    echo 50 ;;
        test)     echo 60 ;;
        verify)   echo 30 ;;
        *)        echo 30 ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────────
# Colors for terminal output
# ─────────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─────────────────────────────────────────────────────────────────────────────────
# Argument parsing (only when executed directly)
# ─────────────────────────────────────────────────────────────────────────────────

DRY_RUN=false
SINGLE_TASK=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --single)
                SINGLE_TASK=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --dry-run    Show what would be done without executing"
                echo "  --single     Process only one task then exit"
                echo "  --help, -h   Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────────────────────────────────────────

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}   ${BOLD}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_task_start() {
    echo -e "\n${YELLOW}───────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}${BOLD}Task:${NC} $1"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

print_human_review() {
    echo -e "\n${YELLOW}${BOLD}⚠═══════════════════════════════════════════════════════════════⚠${NC}"
    echo -e "${YELLOW}${BOLD}   HUMAN REVIEW REQUIRED${NC}"
    echo -e "${YELLOW}   \"The hard work of thinking can't be outsourced to AI,${NC}"
    echo -e "${YELLOW}    only amplified by it.\" —Jake Nations${NC}"
    echo -e "${YELLOW}${BOLD}⚠═══════════════════════════════════════════════════════════════⚠${NC}\n"
}

# Check if stop signal exists
check_stop_signal() {
    [[ -f "$STOP_FILE" ]]
}

# Clear stop signal (called at start of workflow)
clear_stop_signal() {
    rm -f "$STOP_FILE"
}

# Handle stop signal
handle_stop() {
    print_warning "Stop signal received. Stopping workflow after current task."
    rm -f "$STOP_FILE"
    return 0
}

# Check if an established project exists
has_project_file() {
    compgen -G "PROJECT_*.md" > /dev/null 2>&1
}

# Check if backlog is fresh/unconfigured (template or missing)
is_fresh_backlog() {
    # No backlog file
    [[ ! -f "$BACKLOG_FILE" ]] && return 0

    # Contains template placeholder tasks
    grep -q "Your first task here" "$BACKLOG_FILE" && return 0

    # No pending tasks at all
    local pending_tasks
    pending_tasks=$(grep -c '^\- \[ \]' "$BACKLOG_FILE" 2>/dev/null)
    if [[ -z "$pending_tasks" || "$pending_tasks" -eq 0 ]]; then
        # Only fresh if no PROJECT file exists
        has_project_file && return 1
        return 0
    fi

    return 1
}

# Check if project is in "completed phase" state (established but no pending work)
is_completed_phase() {
    has_project_file || return 1

    local pending_tasks
    pending_tasks=$(grep -c '^\- \[ \]' "$BACKLOG_FILE" 2>/dev/null)
    [[ -z "$pending_tasks" || "$pending_tasks" -eq 0 ]]
}

# Check prerequisites
check_prerequisites() {
    if ! command -v claude &> /dev/null; then
        print_error "Claude Code CLI not found. Please install it first."
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        print_error "jq not found. Please install it (brew install jq)"
        exit 1
    fi

    # Fresh backlog - launch build mode to define the project
    if is_fresh_backlog; then
        print_info "Empty backlog. Launching build mode..."
        echo ""
        exec claude "Run /build to help define this project and create a backlog."
    fi

    # Completed phase - existing project, no pending tasks
    if is_completed_phase; then
        print_info "All tasks complete! Launching build mode to add scope..."
        echo ""
        exec claude "Run /build to add new tasks to this project."
    fi
}

# Get the next uncompleted task from the backlog
get_next_task() {
    grep -m1 '^\- \[ \]' "$BACKLOG_FILE" 2>/dev/null | sed 's/^- \[ \] //' || echo ""
}

# Mark a task as completed in the backlog
mark_task_complete() {
    local task="$1"
    TASK="$task" perl -i -pe 's/^- \[ \] \Q$ENV{TASK}\E$/- [x] $ENV{TASK}/' "$BACKLOG_FILE"
}

# Mark a task as blocked in the backlog
mark_task_blocked() {
    local task="$1"
    local reason="$2"
    TASK="$task" REASON="$reason" perl -i -pe 's/^- \[ \] \Q$ENV{TASK}\E.*/- [!] $ENV{TASK} (blocked: $ENV{REASON})/' "$BACKLOG_FILE"
}

# Count tasks by status
count_tasks() {
    local status="$1"
    local count
    case "$status" in
        "pending")
            count=$(grep -c '^\- \[ \]' "$BACKLOG_FILE" 2>/dev/null)
            ;;
        "completed")
            count=$(grep -c '^\- \[x\]' "$BACKLOG_FILE" 2>/dev/null)
            ;;
        "blocked")
            count=$(grep -c '^\- \[!\]' "$BACKLOG_FILE" 2>/dev/null)
            ;;
    esac
    echo "${count:-0}"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Detect whether phase-isolated mode is available
# ─────────────────────────────────────────────────────────────────────────────────

# Detection checks TWO things:
# 1. The legacy SKILL.md has the phase-isolation marker (confirming buildcrew is updated)
# 2. The phase-specific skill directories exist (confirming the split files are available)
is_phase_isolation_available() {
    local skill_file
    skill_file=$(find .claude/skills/buildcrew -name "SKILL.md" 2>/dev/null | head -1)

    if [[ -n "$skill_file" ]] && grep -q 'phase-isolation' "$skill_file" \
        && [[ -d .claude/skills/buildcrew-research ]] \
        && [[ -d .claude/skills/buildcrew-review ]] \
        && [[ -d .claude/skills/buildcrew-build ]] \
        && [[ -d .claude/skills/buildcrew-test ]] \
        && [[ -d .claude/skills/buildcrew-verify ]]; then
        return 0
    fi
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────────
# Phase-Isolated Mode: run_phase_group
# ─────────────────────────────────────────────────────────────────────────────────

run_phase_group() {
    local phase="$1"
    local task="$2"
    local extra_context="${3:-}"
    local max_turns
    max_turns=$(get_phase_max_turns "$phase")

    rm -f "$PHASE_RESULT_FILE"

    print_info "Phase: $phase (max $max_turns turns)"

    local prompt="Execute the buildcrew-$phase skill for this task: $task"
    if [[ -n "$extra_context" ]]; then
        prompt="$prompt. Context: $extra_context"
    fi

    # Start file watcher that sends SIGINT when phase-result.json appears
    (
        while true; do
            if [[ -f "$PHASE_RESULT_FILE" ]]; then
                sleep 2
                pkill -INT -f "claude.*buildcrew-$phase" 2>/dev/null || true
                break
            fi
            sleep 1
        done
    ) &
    local monitor_pid=$!

    claude "$prompt" --max-turns "$max_turns" || true

    kill $monitor_pid 2>/dev/null || true
    wait $monitor_pid 2>/dev/null || true

    # Validate result (with one retry on failure)
    if [[ ! -f "$PHASE_RESULT_FILE" ]] || ! jq -e . "$PHASE_RESULT_FILE" >/dev/null 2>&1; then
        print_warning "Phase $phase produced no valid result. Retrying..."
        rm -f "$PHASE_RESULT_FILE"

        # Re-launch monitor for retry
        (
            while true; do
                if [[ -f "$PHASE_RESULT_FILE" ]]; then
                    sleep 2
                    pkill -INT -f "claude.*buildcrew-$phase" 2>/dev/null || true
                    break
                fi
                sleep 1
            done
        ) &
        local retry_monitor_pid=$!

        claude "$prompt" --max-turns "$max_turns" || true

        kill $retry_monitor_pid 2>/dev/null || true
        wait $retry_monitor_pid 2>/dev/null || true

        if [[ ! -f "$PHASE_RESULT_FILE" ]] || ! jq -e . "$PHASE_RESULT_FILE" >/dev/null 2>&1; then
            print_error "Phase $phase failed after retry"
            return 1
        fi
    fi

    local verdict
    verdict=$(jq -r '.verdict // "unknown"' "$PHASE_RESULT_FILE")
    print_success "Phase $phase complete — verdict: $verdict"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Phase-Isolated Mode: process_task_isolated
# ─────────────────────────────────────────────────────────────────────────────────

process_task_isolated() {
    local task="$1"

    print_info "Running in phase-isolated mode (5 invocations)"

    # Clean up artifacts from any previous task
    rm -f .claude/research.md .claude/current-plan.md .claude/plan-review.md \
          .claude/code-review.md .claude/test-report.md .claude/security-audit.md \
          .claude/verify-report.md .claude/current-test-plan.md \
          "$PHASE_RESULT_FILE" "$STATUS_FILE"

    # --- Group 1: Research + Plan ---
    run_phase_group "research" "$task" || return 1

    # --- Group 2: Plan Review (max 3 external cycles) ---
    local plan_review_cycle=0
    while true; do
        ((plan_review_cycle++))
        run_phase_group "review" "$task" "Plan review cycle $plan_review_cycle of 3" || return 1

        local verdict
        verdict=$(jq -r '.verdict' "$PHASE_RESULT_FILE")
        case "$verdict" in
            approved) print_human_review; break ;;
            rejected) mark_task_blocked "$task" "Plan rejected"; return 1 ;;
            needs_revision)
                if (( plan_review_cycle >= 3 )); then
                    mark_task_blocked "$task" "Plan review failed to converge after 3 cycles"
                    return 1
                fi
                ;;
            *) mark_task_blocked "$task" "Unexpected plan review verdict: $verdict"; return 1 ;;
        esac
    done

    # --- Group 3 + 4: Build → Review/Test (with rebuild loop) ---
    local build_attempt=0
    while true; do
        ((build_attempt++))
        if (( build_attempt > 2 )); then
            mark_task_blocked "$task" "Build failed after 2 attempts"
            return 1
        fi

        local build_context=""
        if (( build_attempt > 1 )); then
            local prev_reason
            prev_reason=$(jq -r '.details // "unknown"' "$PHASE_RESULT_FILE")
            build_context="This is build attempt $build_attempt. Previous attempt failed: $prev_reason. Avoid the same mistakes."
        fi

        run_phase_group "build" "$task" "$build_context" || return 1
        run_phase_group "test" "$task" || return 1

        local verdict
        verdict=$(jq -r '.verdict' "$PHASE_RESULT_FILE")
        case "$verdict" in
            approved) break ;;
            needs_rebuild) continue ;;
            test_failure)
                mark_task_blocked "$task" "Tests failing after review"
                return 1
                ;;
            *) mark_task_blocked "$task" "Unexpected review verdict: $verdict"; return 1 ;;
        esac
    done

    # --- Group 5: Verify + Commit ---
    local verify_attempt=0
    while true; do
        ((verify_attempt++))
        if (( verify_attempt > 3 )); then
            mark_task_blocked "$task" "Verification failed after 3 attempts"
            return 1
        fi

        run_phase_group "verify" "$task" || return 1

        local verdict
        verdict=$(jq -r '.verdict' "$PHASE_RESULT_FILE")
        case "$verdict" in
            complete) break ;;
            blocked)
                local failing
                failing=$(jq -r '.failing_check // "unknown"' "$PHASE_RESULT_FILE")
                case "$failing" in
                    tests|security)
                        run_phase_group "build" "$task" "Verify failed: $failing. Fix and rebuild." || return 1
                        run_phase_group "test" "$task" || return 1
                        ;;
                    code_review)
                        run_phase_group "test" "$task" || return 1
                        ;;
                    *)
                        mark_task_blocked "$task" "Verification blocked: $failing"
                        return 1
                        ;;
                esac
                ;;
            *) mark_task_blocked "$task" "Unexpected verify verdict: $verdict"; return 1 ;;
        esac
    done

    # Task succeeded
    mark_task_complete "$task"
    local summary
    summary=$(jq -r '.summary // "Completed"' "$STATUS_FILE" 2>/dev/null || echo "Completed")
    print_success "Completed: $task"
    print_info "Summary: $summary"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Legacy Mode: process_task_legacy (single Claude invocation, all phases)
# ─────────────────────────────────────────────────────────────────────────────────

process_task_legacy() {
    local task="$1"

    print_info "Running in legacy mode (single invocation)"

    # Clear previous status file
    rm -f "$STATUS_FILE"

    # Run Claude with the workflow skill
    print_info "Launching Claude Code..."

    # Start a background monitor that watches for status file
    # When status file appears, send SIGINT to Claude to exit gracefully
    (
        while true; do
            if [[ -f "$STATUS_FILE" ]]; then
                sleep 2  # Give Claude a moment to finish
                # Find and interrupt the claude process
                pkill -INT -f "claude.*Execute the buildcrew skill" 2>/dev/null || true
                break
            fi
            sleep 1
        done
    ) &
    MONITOR_PID=$!

    # Run Claude (monitor will terminate it when status file appears)
    claude "Execute the buildcrew skill for this task: $task" \
        --max-turns "$MAX_TURNS" || true

    # Clean up monitor
    kill $MONITOR_PID 2>/dev/null || true
    wait $MONITOR_PID 2>/dev/null || true

    # Check completion status
    if [[ -f "$STATUS_FILE" ]]; then
        # Validate JSON before parsing
        if ! jq -e . "$STATUS_FILE" >/dev/null 2>&1; then
            print_error "Status file contains invalid JSON"
            print_info "File contents: $(cat "$STATUS_FILE" 2>/dev/null | head -c 200)"
            mark_task_blocked "$task" "Invalid status file JSON"
            return 1
        fi

        local status
        status=$(jq -r '.status // ""' "$STATUS_FILE")

        # Validate status field
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

# ─────────────────────────────────────────────────────────────────────────────────
# Main workflow
# ─────────────────────────────────────────────────────────────────────────────────

main() {
    check_prerequisites

    # Clear any previous stop signal
    clear_stop_signal

    print_header "BuildCrew - Autonomous Development Pipeline"
    print_info "To stop after the current task: buildcrew stop"

    # Detect mode
    local use_isolation=false
    if is_phase_isolation_available; then
        use_isolation=true
        print_info "Mode: Phase-isolated (5 invocations per task)"
    else
        print_info "Mode: Legacy (single invocation per task)"
    fi

    local completed=0
    local failed=0
    local start_time
    start_time=$(date +%s)

    # Show initial status
    print_info "Backlog status:"
    echo "  Pending:   $(count_tasks pending)"
    echo "  Completed: $(count_tasks completed)"
    echo "  Blocked:   $(count_tasks blocked)"

    while true; do
        # Check for stop signal
        if check_stop_signal; then
            handle_stop
            break
        fi

        # Get next task
        local task
        task=$(get_next_task)

        if [[ -z "$task" ]]; then
            break
        fi

        print_task_start "$task"

        if [[ "$DRY_RUN" == "true" ]]; then
            if [[ "$use_isolation" == "true" ]]; then
                print_info "[DRY RUN] Would execute 5 phase groups for: $task"
            else
                print_info "[DRY RUN] Would execute: claude -p \"Execute the buildcrew skill for this task: $task\""
            fi
            mark_task_complete "$task"
            ((completed++))
        else
            if [[ "$use_isolation" == "true" ]]; then
                if process_task_isolated "$task"; then
                    ((completed++))
                else
                    ((failed++))
                fi
            else
                if process_task_legacy "$task"; then
                    ((completed++))
                else
                    ((failed++))
                fi
            fi
        fi

        # Check if we should exit after one task
        if [[ "$SINGLE_TASK" == "true" ]]; then
            print_info "Single task mode - exiting after first task"
            break
        fi

        # Pause between tasks with stop signal check
        if [[ -n "$(get_next_task)" ]]; then
            echo ""
            print_info "Next task in ${PAUSE_BETWEEN_TASKS}s... (run 'buildcrew stop' to exit)"
            for ((i=PAUSE_BETWEEN_TASKS; i>0; i--)); do
                if check_stop_signal; then
                    handle_stop
                    # Break out of both loops
                    break 2
                fi
                sleep 1
            done
        fi
    done

    # Final summary
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    print_header "Workflow Complete"
    echo -e "  ${GREEN}Completed:${NC} $completed"
    echo -e "  ${YELLOW}Failed:${NC}    $failed"
    echo -e "  ${CYAN}Duration:${NC}  ${duration}s"
    echo ""

    # Show remaining status
    local remaining
    remaining=$(count_tasks pending)
    if [[ "$remaining" -gt 0 ]]; then
        print_info "$remaining tasks still pending in backlog"
    else
        print_success "All backlog tasks processed!"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────────
# Run (only when executed directly, not sourced)
# ─────────────────────────────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    main "$@"
fi
