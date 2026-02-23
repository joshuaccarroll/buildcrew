#!/bin/bash
# BuildCrew status line script for Claude Code
# Invoked by Claude Code with session JSON on stdin; prints a single status line.
# Must always exit 0.

STATE_FILE=".buildcrew/.workflow-state"

# ANSI color codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

# Read stdin with a 1-second timeout to prevent blocking when stdin is empty/slow
stdin_data=""
if read -t 1 -r stdin_data; then
    # Got first line; try to read the rest quickly
    while IFS= read -t 0.1 -r line; do
        stdin_data="$stdin_data
$line"
    done
fi

# Extract context window percentage from JSON
ctx_pct=""
if [[ -n "$stdin_data" ]] && command -v jq >/dev/null 2>&1; then
    ctx_pct=$(printf '%s' "$stdin_data" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
fi

# Format context percentage with color
ctx_str=""
if [[ -n "$ctx_pct" ]]; then
    pct_int=${ctx_pct%.*}
    if (( pct_int >= 90 )); then
        ctx_color="$RED"
    elif (( pct_int >= 70 )); then
        ctx_color="$YELLOW"
    else
        ctx_color="$GREEN"
    fi
    ctx_str="${ctx_color}${pct_int}% ctx${RESET}"
else
    ctx_str="ctx N/A"
fi

# Read workflow state file
TASK_NUM=""
TOTAL_TASKS=""
TASK_NAME=""
PHASE=""
PHASE_STATUS=""
INVOCATION_COUNT=""
MAX_INVOCATIONS=""

if [[ -f "$STATE_FILE" ]]; then
    while IFS='=' read -r key value; do
        case "$key" in
            TASK_NUM)         TASK_NUM="$value" ;;
            TOTAL_TASKS)      TOTAL_TASKS="$value" ;;
            TASK_NAME)        TASK_NAME="$value" ;;
            PHASE)            PHASE="$value" ;;
            PHASE_STATUS)     PHASE_STATUS="$value" ;;
            INVOCATION_COUNT) INVOCATION_COUNT="$value" ;;
            MAX_INVOCATIONS)  MAX_INVOCATIONS="$value" ;;
        esac
    done < "$STATE_FILE"
fi

# Format output
if [[ -n "$PHASE" ]]; then
    # Workflow is active — color-code phase status
    case "$PHASE_STATUS" in
        running)   phase_color="$CYAN" ;;
        complete)  phase_color="$GREEN" ;;
        failed)    phase_color="$RED" ;;
        *)         phase_color="$RESET" ;;
    esac

    task_part=""
    if [[ -n "$TASK_NUM" && -n "$TOTAL_TASKS" ]]; then
        task_part="Task ${TASK_NUM}/${TOTAL_TASKS} | "
    fi

    inv_part=""
    if [[ -n "$INVOCATION_COUNT" && -n "$MAX_INVOCATIONS" ]]; then
        inv_part=" | inv ${INVOCATION_COUNT}/${MAX_INVOCATIONS}"
    fi

    printf '%b' "${task_part}${phase_color}${PHASE}${RESET} | ${ctx_str}${inv_part}"
else
    # No active workflow
    printf '%b' "BuildCrew | ${ctx_str}"
fi

printf '\n'
exit 0
