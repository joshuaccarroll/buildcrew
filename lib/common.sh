#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BuildCrew - Shared Utilities
# https://github.com/joshuaccarroll/buildcrew
# ═══════════════════════════════════════════════════════════════════════════════
#
# Common colors, print helpers, context loading, status parsing, and file
# monitoring shared across bin/buildcrew, lib/workflow.sh, and lib/plugins.sh.
#
# This file must NOT set shell options (set -e, set -u, etc.) because callers
# have different shell option requirements (workflow.sh uses -euo pipefail,
# bin/buildcrew uses -e, test harness uses +e).
#
# ═══════════════════════════════════════════════════════════════════════════════

# Source guard — prevent double-sourcing
[[ -n "${__BUILDCREW_COMMON_LOADED:-}" ]] && return 0
__BUILDCREW_COMMON_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────────
# Color constants (exported for subshell inheritance)
# ─────────────────────────────────────────────────────────────────────────────────

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export BOLD='\033[1m'
export NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────────
# Print helpers
# ─────────────────────────────────────────────────────────────────────────────────

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}   ${BOLD}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
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

print_debug() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo -e "${CYAN}  [debug] $1${NC}"
    fi
}

error() {
    print_error "$1"
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────────
# Shared constants (plain variables, not exported — tests override via export)
# ─────────────────────────────────────────────────────────────────────────────────

BACKLOG_FILE="${BACKLOG_FILE:-BACKLOG.md}"
STATUS_FILE="${STATUS_FILE:-.claude/workflow-status.json}"

# ─────────────────────────────────────────────────────────────────────────────────
# Task counting
# ─────────────────────────────────────────────────────────────────────────────────

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
# Project context loading
# ─────────────────────────────────────────────────────────────────────────────────

# Loads project context from .buildcrew/context/*.md files and lessons.
# Echoes the context string to stdout. Returns empty string if no files exist.
# All user-facing messages go to stderr (this is called via command substitution).
load_project_context() {
    local project_context=""
    for ctx_file in .buildcrew/context/users.md .buildcrew/context/principles.md .buildcrew/context/domain.md; do
        if [[ -f "$ctx_file" ]]; then
            project_context+="$(cat "$ctx_file")"$'\n\n'
        fi
    done
    # Load lessons (Change 2: Self-Improvement Loop)
    if [[ -f ".buildcrew/lessons.md" ]]; then
        project_context+="$(cat ".buildcrew/lessons.md")"$'\n\n'
    fi
    if [[ -n "$project_context" ]]; then
        local ctx_size=${#project_context}
        if (( ctx_size > 10240 )); then
            echo -e "${YELLOW}⚠ Project context exceeds 10KB ($ctx_size bytes), truncating${NC}" >&2
            project_context="${project_context:0:10240}"$'\n\n[truncated]'
        fi
    fi
    echo "$project_context"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Status file parser (pure data, no side effects)
# ─────────────────────────────────────────────────────────────────────────────────

# Parses a workflow status JSON file and sets globals.
# Returns 0 on valid status, 1 on invalid/missing.
# Sets: __STATUS_RESULT (complete|blocked|error), __STATUS_SUMMARY, __STATUS_REASON
parse_status_file() {
    local status_file="$1"

    __STATUS_RESULT=""
    __STATUS_SUMMARY=""
    __STATUS_REASON=""

    if [[ ! -f "$status_file" ]]; then
        __STATUS_RESULT="error"
        __STATUS_REASON="No status file found"
        return 1
    fi

    if ! jq -e . "$status_file" >/dev/null 2>&1; then
        __STATUS_RESULT="error"
        __STATUS_REASON="Invalid JSON"
        return 1
    fi

    local status
    status=$(jq -r '.status // ""' "$status_file")

    case "$status" in
        complete)
            __STATUS_RESULT="complete"
            __STATUS_SUMMARY=$(jq -r '.summary // "No summary provided"' "$status_file")
            return 0
            ;;
        blocked)
            __STATUS_RESULT="blocked"
            __STATUS_REASON=$(jq -r '.reason // "Unknown reason"' "$status_file")
            return 0
            ;;
        "")
            __STATUS_RESULT="error"
            __STATUS_REASON="Missing status field"
            return 1
            ;;
        *)
            __STATUS_RESULT="error"
            __STATUS_REASON="Unknown status: $status"
            return 1
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────────
# File monitor (watches for a file and sends SIGINT to a process)
# ─────────────────────────────────────────────────────────────────────────────────

__MONITOR_PID=""

start_file_monitor() {
    local file_path="$1"
    local pkill_pattern="$2"

    (
        while true; do
            if [[ -f "$file_path" ]]; then
                sleep 2
                pkill -INT -f "$pkill_pattern" 2>/dev/null || true
                break
            fi
            sleep 1
        done
    ) &
    __MONITOR_PID=$!
}

stop_file_monitor() {
    if [[ -n "$__MONITOR_PID" ]]; then
        kill $__MONITOR_PID 2>/dev/null || true
        wait $__MONITOR_PID 2>/dev/null || true
        __MONITOR_PID=""
    fi
}
