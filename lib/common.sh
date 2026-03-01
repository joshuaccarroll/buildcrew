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

# File-scope log path — must be at file scope (not local) so all functions in
# common.sh and workflow.sh see the same value after sourcing.
__LOG_FILE=""

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
    log_msg "=== $1 ==="
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}   ${BOLD}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_success() {
    log_msg "[OK] $1"
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    log_msg "[WARN] $1"
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    log_msg "[ERROR] $1"
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    log_msg "[INFO] $1"
    echo -e "${CYAN}ℹ $1${NC}"
}

print_debug() {
    log_msg "[DEBUG] $1"
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo -e "${CYAN}  [debug] $1${NC}"
    fi
}

error() {
    print_error "$1"
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────────
# Activity logging
# ─────────────────────────────────────────────────────────────────────────────────

# log_init — create .buildcrew/logs/ and initialize __LOG_FILE.
# Uses PID suffix to prevent filename collision when two runs start in the same second.
log_init() {
    mkdir -p .buildcrew/logs
    __LOG_FILE=".buildcrew/logs/buildcrew-$(date '+%Y-%m-%d_%H-%M-%S')-$$.log"
    echo "[$(date '+%Y-%m-%dT%H:%M:%S')] BuildCrew started (PID=$$)" >> "$__LOG_FILE"
}

# log_msg — append a timestamped, ANSI-stripped entry to __LOG_FILE.
# No-op when __LOG_FILE is empty (tests that skip log_init are unaffected).
# BSD sed on macOS does NOT interpret \x1b in regex; inject the literal ESC byte
# via printf so the strip works on both macOS and Linux.
log_msg() {
    [[ -z "$__LOG_FILE" ]] && return 0
    local esc clean
    esc=$(printf '\033')
    clean=$(printf '%s' "$1" | sed "s/${esc}\[[0-9;]*m//g")
    echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $clean" >> "$__LOG_FILE"
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
            # Truncate to 10KB, then find last section boundary for clean break
            local truncated="${project_context:0:10240}"
            local boundary_line
            boundary_line=$(printf '%s' "$truncated" | grep -n '^\(---\|## \)' | tail -1 | cut -d: -f1)
            if [[ -n "$boundary_line" && "$boundary_line" -gt 1 ]]; then
                project_context=$(printf '%s' "$truncated" | head -n "$(( boundary_line - 1 ))")
            else
                # Fallback: truncate at last newline
                project_context="${truncated%$'\n'*}"
            fi
            project_context="$project_context"$'\n\n[truncated]'
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

# ─────────────────────────────────────────────────────────────────────────────────
# Skill catalog builder
# ─────────────────────────────────────────────────────────────────────────────────

# Builds a compressed catalog of available skills from SKILL.md frontmatter.
# Scans project-local (.claude/skills/*/SKILL.md) and source ($BUILDCREW_HOME/skills/*/SKILL.md).
# Project-local skills override source skills when directory basenames collide.
# Outputs: "Available Skills:\n- name: description" (sorted by name), or empty string if none found.
build_skill_catalog() {
    # Guard: BUILDCREW_HOME may not be set in test/CLI contexts
    local source_dir=""
    if [[ -n "${BUILDCREW_HOME:-}" ]]; then
        source_dir="$BUILDCREW_HOME/skills"
    fi
    local local_dir=".claude/skills"

    # Collect skill directories: source first, then local (local overrides on collision)
    # Use basename as dedup key. Store in "basename:path" format.
    local seen_basenames=""
    local skill_entries=""

    # Helper: extract name and description from a SKILL.md file's YAML frontmatter.
    # Sets __CATALOG_NAME and __CATALOG_DESC. Returns 1 if invalid.
    __extract_skill_frontmatter() {
        local file="$1"
        __CATALOG_NAME=""
        __CATALOG_DESC=""

        [[ -f "$file" ]] || return 1

        # First line must be ---
        local first_line
        first_line=$(head -1 "$file")
        if [[ "$first_line" != "---" ]]; then
            return 1
        fi

        # Read lines between first and second --- delimiters
        local in_frontmatter=0
        local line_num=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            line_num=$(( line_num + 1 ))
            if [[ $line_num -eq 1 ]]; then
                in_frontmatter=1
                continue
            fi
            if [[ $in_frontmatter -eq 1 && "$line" == "---" ]]; then
                break
            fi
            if [[ $in_frontmatter -eq 1 ]]; then
                case "$line" in
                    name:\ *)
                        __CATALOG_NAME="${line#name: }"
                        ;;
                    description:\ *)
                        __CATALOG_DESC="${line#description: }"
                        ;;
                esac
            fi
        done < "$file"

        # Both fields required
        if [[ -z "$__CATALOG_NAME" || -z "$__CATALOG_DESC" ]]; then
            return 1
        fi

        # Truncate description to 120 chars at word boundary
        if [[ ${#__CATALOG_DESC} -gt 120 ]]; then
            local truncated="${__CATALOG_DESC:0:120}"
            # Find last space for word boundary
            if [[ "$truncated" =~ ^(.*[[:space:]])[^[:space:]]*$ ]]; then
                truncated="${BASH_REMATCH[1]}"
                # Trim trailing whitespace
                truncated="${truncated%"${truncated##*[![:space:]]}"}"
            fi
            __CATALOG_DESC="${truncated}..."
        fi

        return 0
    }

    # Process source skills first (BUILDCREW_HOME/skills/*)
    if [[ -n "$source_dir" && -d "$source_dir" ]]; then
        for skill_dir in "$source_dir"/*/; do
            [[ -d "$skill_dir" ]] || continue
            local basename
            basename=$(basename "$skill_dir")
            local skill_file="$skill_dir/SKILL.md"
            if [[ -f "$skill_file" ]] && __extract_skill_frontmatter "$skill_file"; then
                seen_basenames="$seen_basenames $basename"
                skill_entries="$skill_entries"$'\n'"$__CATALOG_NAME: $__CATALOG_DESC"
            fi
        done
    fi

    # Process local skills (override source on basename collision)
    if [[ -d "$local_dir" ]]; then
        for skill_dir in "$local_dir"/*/; do
            [[ -d "$skill_dir" ]] || continue
            local basename
            basename=$(basename "$skill_dir")
            local skill_file="$skill_dir/SKILL.md"
            if [[ -f "$skill_file" ]] && __extract_skill_frontmatter "$skill_file"; then
                # Check if this basename was already seen from source
                local already_seen=0
                for seen in $seen_basenames; do
                    if [[ "$seen" == "$basename" ]]; then
                        already_seen=1
                        break
                    fi
                done
                if [[ $already_seen -eq 1 ]]; then
                    # Remove the source entry and replace with local
                    local new_entries=""
                    local old_name=""
                    # Re-extract the source skill name for this basename
                    local source_file="$source_dir/$basename/SKILL.md"
                    if [[ -f "$source_file" ]]; then
                        local saved_name="$__CATALOG_NAME"
                        local saved_desc="$__CATALOG_DESC"
                        if __extract_skill_frontmatter "$source_file"; then
                            old_name="$__CATALOG_NAME"
                        fi
                        __CATALOG_NAME="$saved_name"
                        __CATALOG_DESC="$saved_desc"
                    fi
                    # Filter out the old entry
                    local IFS_SAVE="$IFS"
                    IFS=$'\n'
                    for entry in $skill_entries; do
                        [[ -z "$entry" ]] && continue
                        if [[ -n "$old_name" && "$entry" == "$old_name: "* ]]; then
                            continue
                        fi
                        new_entries="$new_entries"$'\n'"$entry"
                    done
                    IFS="$IFS_SAVE"
                    skill_entries="$new_entries"
                fi
                skill_entries="$skill_entries"$'\n'"$__CATALOG_NAME: $__CATALOG_DESC"
                seen_basenames="$seen_basenames $basename"
            fi
        done
    fi

    # Remove leading blank lines and sort
    local cleaned
    cleaned=$(echo "$skill_entries" | sed '/^$/d' | sort)

    if [[ -z "$cleaned" ]]; then
        echo ""
        return 0
    fi

    # Format output
    local output="Available Skills:"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        output="$output"$'\n'"- $line"
    done <<< "$cleaned"

    echo "$output"
}
