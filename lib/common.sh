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
# sha256_hash — portable SHA-256 hash of a file
# ─────────────────────────────────────────────────────────────────────────────────
# Uses sha256sum on Linux, falls back to shasum -a 256 on macOS.
# Outputs only the hash (no filename).
sha256_hash() {
    local file="$1"
    local hash
    if command -v sha256sum >/dev/null 2>&1; then
        hash=$(sha256sum "$file" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
        hash=$(shasum -a 256 "$file" | cut -d' ' -f1)
    else
        print_error "Neither sha256sum nor shasum found"
        return 1
    fi
    printf '%s' "$hash"
}

# ─────────────────────────────────────────────────────────────────────────────────
# read_config_key — read a single key from .buildcrew/config
# ─────────────────────────────────────────────────────────────────────────────────
# Reads the value for a given UPPERCASE key from .buildcrew/config.
# Returns the value via stdout. Returns empty string if key not found.
read_config_key() {
    local key="$1"
    local config_file=".buildcrew/config"
    [[ -f "$config_file" ]] || return 0

    local line k v
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
            k="${BASH_REMATCH[1]}"
            v="${BASH_REMATCH[2]}"
            # Strip surrounding quotes if present
            v="${v#\"}"
            v="${v%\"}"
            v="${v#\'}"
            v="${v%\'}"
            if [[ "$k" == "$key" ]]; then
                printf '%s' "$v"
                return 0
            fi
        fi
    done < "$config_file"
}

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

# check_context_health — warn about missing context files (once per invocation).
# Checks the 4 files read by load_project_context() and prints a single
# consolidated warning listing any that are absent, with suggested commands.
# Always returns 0 — informational only, never blocks execution.
check_context_health() {
    local -a paths=( ".buildcrew/context/users.md" ".buildcrew/context/principles.md" ".buildcrew/context/domain.md" ".buildcrew/lessons.md" )
    local -a cmds=( "cp .buildcrew/context/users.md.example .buildcrew/context/users.md" "cp .buildcrew/context/principles.md.example .buildcrew/context/principles.md" "cp .buildcrew/context/domain.md.example .buildcrew/context/domain.md" "touch .buildcrew/lessons.md" )
    local msg="" i
    for i in 0 1 2 3; do
        if [[ ! -f "${paths[$i]}" ]]; then
            msg+="  ${paths[$i]}  →  ${cmds[$i]}\n"
        fi
    done
    if [[ -n "$msg" ]]; then
        print_warning "Missing context files:\n${msg}Create them to enrich BuildCrew prompts."
    fi
    return 0
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

# Parses YAML frontmatter from a SKILL.md file.
# Outputs "name\ndescription" if valid, or nothing if invalid/missing.
__parse_skill_frontmatter() {
    awk '
    NR==1 { if ($0 != "---") exit; next }
    /^---$/ { exit }
    /^name: / { n = substr($0, 7); gsub(/^[ \t]+/, "", n); gsub(/[ \t]+$/, "", n) }
    /^description: / { d = substr($0, 14); gsub(/^[ \t]+/, "", d); gsub(/[ \t]+$/, "", d) }
    END {
        if (n == "" || d == "") exit
        if (length(d) > 120) {
            p = 0
            for (i = 120; i >= 1; i--) {
                if (substr(d, i, 1) == " ") { p = i; break }
            }
            if (p > 0) d = substr(d, 1, p - 1) "..."
            else d = substr(d, 1, 120) "..."
        }
        print n
        print d
    }
    ' "$1" 2>/dev/null
}

# Scans a skills directory and appends pipe-delimited entries to all_entries.
# Usage: __collect_skill_entries "/path/to/skills"
# Appends "dirname|name|desc\n" for each valid SKILL.md found.
__collect_skill_entries() {
    local skills_dir="$1"
    local f dir_name parsed name desc
    for f in "$skills_dir"/*/SKILL.md; do
        [[ -f "$f" ]] || continue
        dir_name=$(basename "$(dirname "$f")")
        parsed=$(__parse_skill_frontmatter "$f") || true
        if [[ -n "$parsed" ]]; then
            name="${parsed%%$'\n'*}"
            desc="${parsed#*$'\n'}"
            all_entries="${all_entries}${dir_name}|${name}|${desc}"$'\n'
        fi
    done
}

# Builds a compressed skill catalog from project-local and source skill directories.
# Scans $BUILDCREW_HOME/skills/*/SKILL.md and $PWD/.claude/skills/*/SKILL.md,
# deduplicates by directory basename (project-local wins), sorts by name.
# Outputs "Available Skills:\n- name: desc\n..." to stdout, or nothing if no skills.
# Always returns 0.
build_skill_catalog() {
    local all_entries=""

    # Source skills first, then project-local (last-write-wins for dedup)
    if [[ -n "${BUILDCREW_HOME:-}" && -d "$BUILDCREW_HOME/skills" ]]; then
        __collect_skill_entries "$BUILDCREW_HOME/skills"
    fi

    if [[ -d "$PWD/.claude/skills" ]]; then
        __collect_skill_entries "$PWD/.claude/skills"
    fi

    if [[ -z "$all_entries" ]]; then
        return 0
    fi

    # Dedup by directory basename (field 1), sort by skill name (field 1 after dedup)
    local formatted
    formatted=$(printf '%s' "$all_entries" | awk -F'|' '{
        names[$1] = $2; descs[$1] = $3
    } END {
        for (k in names) print names[k] "|" descs[k]
    }' | LC_ALL=C sort -t'|' -k1,1 | while IFS='|' read -r n d; do
        printf '%s\n' "- $n: $d"
    done) || true

    if [[ -n "$formatted" ]]; then
        printf '%s\n' "Available Skills:"
        printf '%s\n' "$formatted"
    fi

    return 0
}
