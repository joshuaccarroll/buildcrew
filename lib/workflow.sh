#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BuildCrew - Autonomous Claude Code Development Pipeline
# https://github.com/joshuaccarroll/buildcrew
# ═══════════════════════════════════════════════════════════════════════════════
#
# This script orchestrates an autonomous development workflow using Claude Code.
# It reads tasks from BACKLOG.md and processes each one through:
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
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────────

BACKLOG_FILE="BACKLOG.md"
STATUS_FILE=".claude/workflow-status.json"
MAX_TURNS=100
PAUSE_BETWEEN_TASKS=3

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

# Check if backlog is fresh/unconfigured (template or missing)
is_fresh_backlog() {
    # No backlog file
    [[ ! -f "$BACKLOG_FILE" ]] && return 0

    # Contains template placeholder tasks
    grep -q "Your first task here" "$BACKLOG_FILE" && return 0

    # No pending tasks at all
    local pending_tasks
    pending_tasks=$(grep -c '^\- \[ \]' "$BACKLOG_FILE" 2>/dev/null)
    [[ -z "$pending_tasks" || "$pending_tasks" -eq 0 ]] && return 0

    return 1
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
        exec claude -p "Run /build to help define this project and create a backlog."
    fi
}

# Get the next uncompleted task from the backlog
get_next_task() {
    grep -m1 '^\- \[ \]' "$BACKLOG_FILE" 2>/dev/null | sed 's/^- \[ \] //' || echo ""
}

# Mark a task as completed in the backlog
mark_task_complete() {
    local task="$1"
    local escaped_task
    escaped_task=$(echo "$task" | sed 's/[\/&]/\\&/g; s/\[/\\[/g; s/\]/\\]/g')

    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s/^- \[ \] ${escaped_task}$/- [x] ${escaped_task}/" "$BACKLOG_FILE"
    else
        sed -i "s/^- \[ \] ${escaped_task}$/- [x] ${escaped_task}/" "$BACKLOG_FILE"
    fi
}

# Mark a task as blocked in the backlog
mark_task_blocked() {
    local task="$1"
    local reason="$2"
    local escaped_task
    escaped_task=$(echo "$task" | sed 's/[\/&]/\\&/g; s/\[/\\[/g; s/\]/\\]/g')

    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s/- \[ \] ${escaped_task}/- [!] ${escaped_task} (blocked: ${reason})/" "$BACKLOG_FILE"
    else
        sed -i "s/- \[ \] ${escaped_task}/- [!] ${escaped_task} (blocked: ${reason})/" "$BACKLOG_FILE"
    fi
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
# Main workflow
# ─────────────────────────────────────────────────────────────────────────────────

main() {
    check_prerequisites

    print_header "BuildCrew - Autonomous Development Pipeline"

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
        # Get next task
        local task
        task=$(get_next_task)

        if [[ -z "$task" ]]; then
            break
        fi

        print_task_start "$task"

        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "[DRY RUN] Would execute: claude -p \"Execute the buildcrew skill for this task: $task\""
            mark_task_complete "$task"
            ((completed++))
        else
            # Clear previous status file
            rm -f "$STATUS_FILE"

            # Run Claude with the workflow skill
            print_info "Launching Claude Code..."

            if claude -p "Execute the buildcrew skill for this task: $task" \
                --max-turns "$MAX_TURNS" \
                --verbose; then

                # Check completion status
                if [[ -f "$STATUS_FILE" ]]; then
                    local status
                    status=$(jq -r '.status // "unknown"' "$STATUS_FILE" 2>/dev/null || echo "unknown")

                    if [[ "$status" == "complete" ]]; then
                        local summary
                        summary=$(jq -r '.summary // "No summary provided"' "$STATUS_FILE" 2>/dev/null)
                        mark_task_complete "$task"
                        print_success "Completed: $task"
                        print_info "Summary: $summary"
                        ((completed++))
                    else
                        local reason
                        reason=$(jq -r '.reason // "Unknown reason"' "$STATUS_FILE" 2>/dev/null)
                        mark_task_blocked "$task" "$reason"
                        print_warning "Blocked: $task"
                        print_warning "Reason: $reason"
                        ((failed++))
                    fi
                else
                    print_warning "No status file found - assuming task needs attention"
                    mark_task_blocked "$task" "No status file"
                    ((failed++))
                fi
            else
                print_error "Claude exited with an error"
                mark_task_blocked "$task" "Claude error"
                ((failed++))
            fi
        fi

        # Check if we should exit after one task
        if [[ "$SINGLE_TASK" == "true" ]]; then
            print_info "Single task mode - exiting after first task"
            break
        fi

        # Brief pause between tasks
        if [[ -n "$(get_next_task)" ]]; then
            print_info "Continuing to next task in ${PAUSE_BETWEEN_TASKS}s..."
            sleep "$PAUSE_BETWEEN_TASKS"
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
