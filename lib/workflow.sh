#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BuildCrew - Autonomous Claude Code Development Pipeline
# https://github.com/joshuaccarroll/buildcrew
# ═══════════════════════════════════════════════════════════════════════════════
#
# This script orchestrates BuildCrew's execution mode — the autonomous development
# pipeline. It reads tasks from BACKLOG.md and processes each one through phase groups:
#
# Phase-isolated mode (up to 8 separate Claude invocations):
#   spec (optional, skipped with --skip-spec)
#   research + plan
#   plan-review (3-pass)
#   tdd-scaffold (standard complexity)
#   build
#   codereview (adversarial PE review — independent phase)
#   verify + security audit + commit + signal
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
# Source shared utilities (works both when exec'd and when sourced by tests)
# ─────────────────────────────────────────────────────────────────────────────────

__WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$__WORKFLOW_DIR/common.sh"
source "$__WORKFLOW_DIR/uat.sh"
source "$__WORKFLOW_DIR/artifact.sh"
source "$__WORKFLOW_DIR/uat_signal.sh"
source "$__WORKFLOW_DIR/precompute.sh"

# Load project config safely (key=value only, no shell execution)
load_buildcrew_config() {
    local config_file=".buildcrew/config"
    [[ -f "$config_file" ]] || return 0

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        # Match KEY=VALUE (no spaces around =, value unquoted or quoted)
        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # Strip surrounding quotes if present
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            case "$key" in
                MAX_INVOCATIONS)
                    # Only set if not already defined via env var (env var wins)
                    if [[ -z "${MAX_INVOCATIONS+x}" ]]; then
                        if [[ "$value" =~ ^[1-9][0-9]*$ ]] && [[ ${#value} -le 5 ]]; then
                            MAX_INVOCATIONS="$value"
                        else
                            echo "Warning: invalid MAX_INVOCATIONS in .buildcrew/config: $value (ignored)" >&2
                        fi
                    fi
                    ;;
                COMPLEXITY_AWARE)
                    if [[ -z "${COMPLEXITY_AWARE+x}" ]]; then
                        if [[ "$value" == "true" || "$value" == "false" ]]; then
                            COMPLEXITY_AWARE="$value"
                        else
                            echo "Warning: invalid COMPLEXITY_AWARE in .buildcrew/config: $value (ignored, must be true or false)" >&2
                        fi
                    fi
                    ;;
                AUTO_MODE)
                    if [[ -z "${AUTO_MODE+x}" ]]; then
                        if [[ "$value" == "true" || "$value" == "false" ]]; then
                            AUTO_MODE="$value"
                        else
                            echo "Warning: invalid AUTO_MODE in .buildcrew/config: $value (ignored, must be true or false)" >&2
                        fi
                    fi
                    ;;
                KEEP_LOGS)
                    echo "Warning: KEEP_LOGS in .buildcrew/config is deprecated (logs are now always retained). Remove it from your config." >&2
                    ;;
                MAX_PARALLEL)
                    if [[ -z "${MAX_PARALLEL+x}" ]]; then
                        if [[ "$value" =~ ^[1-9][0-9]*$ ]] && [[ ${#value} -le 2 ]]; then
                            MAX_PARALLEL="$value"
                        else
                            echo "Warning: invalid MAX_PARALLEL in .buildcrew/config: $value (ignored, must be 1-99)" >&2
                        fi
                    fi
                    ;;
                TARGET_DIR)
                    # Batch-mode only: default target directory for tasks without [dir:...] prefix
                    if [[ -z "${TARGET_DIR+x}" ]]; then
                        TARGET_DIR="$value"
                    fi
                    ;;
                CLAUDE_MODEL)
                    if [[ -z "${CLAUDE_MODEL+x}" ]]; then
                        CLAUDE_MODEL="$value"
                    fi
                    ;;
                CLAUDE_EFFORT)
                    if [[ -z "${CLAUDE_EFFORT+x}" ]]; then
                        if [[ "$value" == "low" || "$value" == "medium" || "$value" == "high" ]]; then
                            CLAUDE_EFFORT="$value"
                        else
                            echo "Warning: invalid CLAUDE_EFFORT in .buildcrew/config: $value (ignored, must be low/medium/high)" >&2
                        fi
                    fi
                    ;;
                # Add future config keys here
            esac
        fi
    done < "$config_file"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────────

PHASE_RESULT_FILE=".claude/phase-result.json"
STOP_FILE=".buildcrew/.stop-workflow"
LOCKFILE=".buildcrew/.workflow-lock"
MAX_TURNS=100
PAUSE_BETWEEN_TASKS=5
# 1. Load project config (only sets vars not already in environment)
load_buildcrew_config
# 2. Fall back to built-in default if nothing set it
MAX_INVOCATIONS=${MAX_INVOCATIONS:-15}
COMPLEXITY_AWARE=${COMPLEXITY_AWARE:-true}
AUTO_MODE=${AUTO_MODE:-true}
MAX_PARALLEL=${MAX_PARALLEL:-5}
TARGET_DIR=${TARGET_DIR:-}
NO_UAT=${NO_UAT:-false}
CLAUDE_MODEL=${CLAUDE_MODEL:-auto}
CLAUDE_EFFORT=${CLAUDE_EFFORT:-medium}
__INVOCATION_COUNT=0
__RESUME_PHASES=""
__DISCOVERY_HEARTBEAT_PID=""

# Max turns per phase group (used in isolated mode)
# Uses a function instead of declare -A for bash 3.2 (macOS) compatibility
get_phase_max_turns() {
    case "$1" in
        spec)       echo 50 ;;
        prereqs)    echo 30 ;;
        research)   echo 40 ;;
        review)     echo 50 ;;
        tdd-scaffold) echo 40 ;;
        build)      echo 50 ;;
        docs)       echo 20 ;;
        codereview) echo 40 ;;
        verify)     echo 70 ;;
        *)          echo 30 ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────────
# Argument parsing (only when executed directly)
# ─────────────────────────────────────────────────────────────────────────────────

DRY_RUN=false
SINGLE_TASK=false
HUMAN_REVIEW=false
GIT_BRANCH=false
RESUME_MODE=false
TARGET_TASK=""
TARGET_TASK_EXACT=""
ORIGINAL_BRANCH=""
HAS_REMOTE=false
GH_AVAILABLE=false
SKIP_SPEC=false
SKIP_PREREQS=false
VERBOSE=false
FULL_PIPELINE=false
SEQUENTIAL_MODE=false
BATCH_MAX_TURNS=200
PLAN_MODE=false
INTERACTIVE_FLAG=""
DEPRECATED_AUTO_USED=""

if command -v python3 &>/dev/null; then
    __ACTIVITY_TRACKING=true
else
    print_warning "python3 not found — subagent activity tracking disabled"
    __ACTIVITY_TRACKING=false
fi

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --single)
                SINGLE_TASK=true
                SEQUENTIAL_MODE=true
                shift
                ;;
            --review)
                HUMAN_REVIEW=true
                SEQUENTIAL_MODE=true
                shift
                ;;
            --branch)
                GIT_BRANCH=true
                shift
                ;;
            --resume)
                RESUME_MODE=true
                shift
                ;;
            --task)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --task requires a value (task name or number)"
                    exit 1
                fi
                TARGET_TASK="$2"
                SEQUENTIAL_MODE=true
                shift 2
                ;;
            --task-exact)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --task-exact requires a value (exact task text)"
                    exit 1
                fi
                TARGET_TASK_EXACT="$2"
                SINGLE_TASK=true
                SEQUENTIAL_MODE=true
                shift 2
                ;;
            --skip-spec)
                SKIP_SPEC=true
                shift
                ;;
            --skip-prereqs)
                SKIP_PREREQS=true
                shift
                ;;
            --verbose|--debug)
                VERBOSE=true
                shift
                ;;
            --full-pipeline)
                FULL_PIPELINE=true
                shift
                ;;
            --auto)
                print_warning "--auto is deprecated (auto mode is now the default). Use --interactive to restore interactive pauses."
                DEPRECATED_AUTO_USED=true
                AUTO_MODE=true
                shift
                ;;
            --interactive)
                INTERACTIVE_FLAG=true
                AUTO_MODE=false
                shift
                ;;
            --batch)
                print_warning "--batch is deprecated (batch mode is now the default). Use --sequential to opt out."
                shift
                ;;
            --sequential)
                SEQUENTIAL_MODE=true
                shift
                ;;
            --no-uat)
                NO_UAT=true
                shift
                ;;
            --keep-logs)
                echo "Warning: --keep-logs is deprecated (logs are now always retained). This flag will be removed in a future release." >&2
                shift
                ;;
            --max-invocations)
                if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[1-9][0-9]*$ ]] || [[ ${#2} -gt 5 ]]; then
                    echo "Error: --max-invocations requires a positive integer (1-99999, no leading zeros)"
                    exit 1
                fi
                MAX_INVOCATIONS="$2"
                shift 2
                ;;
            --max-parallel)
                if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[1-9][0-9]*$ ]] || [[ ${#2} -gt 2 ]]; then
                    echo "Error: --max-parallel requires a positive integer (1-99)"
                    exit 1
                fi
                MAX_PARALLEL="$2"
                shift 2
                ;;
            --model)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --model requires a value (e.g. opus, sonnet, claude-sonnet-4-6)"
                    exit 1
                fi
                CLAUDE_MODEL="$2"
                shift 2
                ;;
            --effort)
                if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^(low|medium|high)$ ]]; then
                    echo "Error: --effort requires a value: low, medium, or high"
                    exit 1
                fi
                CLAUDE_EFFORT="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --dry-run    Show what would be done without executing"
                echo "  --single     Process only one task then exit"
                echo "  --review     Pause for human review before build (shows plan inline)"
                echo "  --branch     Create a feature branch per task with optional PR"
                echo "  --task NAME  Target a specific task by name or number (implies --single)"
                echo "  --resume     Resume an interrupted task from where it left off"
                echo "  --skip-spec  Skip the specification refinement phase (for tasks with detailed specs already)"
                echo "  --skip-prereqs  Skip the prerequisites check phase"
                echo "  --max-invocations N  Set maximum Claude invocations per run (default: 15)"
                echo "  --full-pipeline  Force all phases regardless of complexity assessment"
                echo "  --auto       (deprecated) Auto mode is now the default. Use --interactive to opt out"
                echo "  --interactive Restore interactive pauses (spec review, plan review, human review)"
                echo "  --sequential Run tasks one at a time (opt out of parallel batch mode)"
                echo "  --no-uat     Skip UAT after backlog completion (with 'run')"
                echo "  --batch      (deprecated) Batch mode is now the default"
                echo "  --max-parallel N  Max concurrent tasks in parallel mode (default: 5)"
                echo "  --model MODEL  Claude model: auto (default, per-phase), opus, sonnet, haiku, or full model ID"
                echo "  --effort LEVEL Effort level: low, medium, high (default: medium)"
                echo "  --verbose    Show orchestrator decisions, phase verdicts, and invocation counts"
                echo "  --debug      Alias for --verbose"
                echo "  --help, -h   Show this help message"
                exit 0
                ;;
            --plan)
                PLAN_MODE=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # If both --auto and --interactive were specified, --interactive wins (--auto is deprecated)
    if [[ "$INTERACTIVE_FLAG" == "true" && "$DEPRECATED_AUTO_USED" == "true" ]]; then
        print_warning "Both --auto and --interactive specified; --auto is deprecated. Using --interactive."
        AUTO_MODE=false
    fi
}

# ─────────────────────────────────────────────────────────────────────────────────
# Workflow-specific helpers
# ─────────────────────────────────────────────────────────────────────────────────

# Augment a prompt string with TDD context for build/test/codereview phases.
# Args: $1=phase_name $2=prompt_string
# Echoes: augmented prompt (or original if TDD inactive/inapplicable)
# Generates a compact phase result protocol block for the given phase.
# Replaces verbose per-SKILL.md protocol sections with a centralized injection.
__inject_phase_result_protocol() {
    local phase="$1"
    local verdicts extra=""
    case "$phase" in
        spec)          verdicts="complete, needs_probing, vague"
                       extra=$'\nFor needs_probing, include "questions": ["..."] array.' ;;
        research)      verdicts="complete"
                       extra=$'\nInclude "human_review": true and "human_review_reason": "..." when objective criteria are met.' ;;
        review)        verdicts="approved, needs_revision, rejected" ;;
        tdd-scaffold)  verdicts="complete, blocked" ;;
        build)         verdicts="complete" ;;
        codereview)    verdicts="approved, needs_rebuild" ;;
        verify)        verdicts="complete, blocked"
                       extra=$'\nFor blocked, include "failing_check": "tests|quality|security|architecture|acceptance".' ;;
        uat-stories)   verdicts="pass, fail" ;;
        uat-scenarios) verdicts="pass, fail" ;;
        uat-harness)   verdicts="pass, fail, disputed" ;;
        uat-execute)   verdicts="pass, fail, error, disputed" ;;
        *)             verdicts="complete" ;;
    esac
    printf '## Phase Result\nWrite `.claude/phase-result.json` when done: { "phase": "%s", "verdict": "<verdict>", "details": "<summary>" }\nValid verdicts: %s%s\nWriting this file is mandatory. Do not end your response without writing it. Then exit.' \
        "$phase" "$verdicts" "$extra"
}

__inject_tdd_prompt() {
    local phase="$1" prompt="$2"
    if [[ ! -f ".claude/tdd-manifest.json" ]]; then
        printf '%s' "$prompt"; return
    fi
    local tdd_test_count
    tdd_test_count=$(jq -r '.test_count // 0' ".claude/tdd-manifest.json" 2>/dev/null)
    if (( tdd_test_count == 0 )); then
        printf '%s' "$prompt"; return
    fi
    case "$phase" in
        build)
            printf '%s\n\n%s' "$prompt" "TDD MODE: $tdd_test_count failing tests exist. Read .claude/tdd-manifest.json for test locations. PRIMARY goal: make all TDD tests pass. Run tests after each major change. Do NOT modify TDD test files." ;;
        codereview)
            printf '%s\n\n%s' "$prompt" "TDD MODE ACTIVE: Test files listed in .claude/tdd-manifest.json were written by the tdd-scaffold phase, not the build phase. Do NOT flag them as issues. Do NOT request they be moved, renamed, or rewritten. Verify the build made them pass." ;;
        *)
            printf '%s' "$prompt" ;;
    esac
}

# Apply a command to each TDD test file listed in the manifest.
# Usage: __for_each_tdd_file chmod a-w
__for_each_tdd_file() {
    [[ -f ".claude/tdd-manifest.json" ]] || return 0
    local _f
    for _f in $(jq -r '.test_files[]? // empty' ".claude/tdd-manifest.json" 2>/dev/null); do
        [[ -f "$_f" ]] && "$@" "$_f" 2>/dev/null || true
    done
}

# Lock TDD test files to read-only during the build phase.
# Prevents accidental modification — tamper detection via checksums remains
# the canonical gate, but chmod provides a first line of defence.
__lock_tdd_files() { __for_each_tdd_file chmod a-w; }

# Restore write permissions on TDD test files after the build phase.
# Must be called even if the build fails (use __with_tdd_lock for safety).
__unlock_tdd_files() { __for_each_tdd_file chmod u+w; }

# Run a command with TDD files locked (read-only) for the duration.
# Ensures unlock happens even if the command fails.
# Usage: __with_tdd_lock run_phase_group "build" "$task" "$ctx"
__with_tdd_lock() {
    __lock_tdd_files
    local _rc=0
    "$@" || _rc=$?
    __unlock_tdd_files
    return $_rc
}

# Run a command with a timeout (in seconds). Returns 124 on timeout.
# Args: $1=timeout_seconds  $2...=command and args
__run_with_timeout() {
    local timeout="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout" "$@"
    else
        # macOS fallback: use perl alarm
        perl -e 'alarm shift; exec @ARGV' "$timeout" "$@"
    fi
}

# Validate TDD scaffold output: run the test command and verify tests fail.
# If tests pass (exit 0) the scaffold is invalid — tests should fail before build.
# Returns 0 if validation passes (tests failed as expected), 1 otherwise.
__validate_tdd_scaffold() {
    [[ -f ".claude/tdd-manifest.json" ]] || return 0
    local test_cmd
    test_cmd=$(jq -r '.test_command // ""' ".claude/tdd-manifest.json" 2>/dev/null)
    [[ -n "$test_cmd" ]] || return 0

    print_info "Validating TDD scaffold — tests should fail..."
    local rc=0
    __run_with_timeout 30 bash -c "$test_cmd" >/dev/null 2>&1 || rc=$?

    if [[ $rc -eq 0 ]]; then
        print_warning "TDD scaffold validation failed: tests pass before build (expected failures)"
        return 1
    elif [[ $rc -eq 124 ]]; then
        print_warning "TDD scaffold validation timed out (30s) — proceeding anyway"
        return 0
    else
        print_info "TDD scaffold validated — tests fail as expected (exit $rc)"
        return 0
    fi
}

# Clean up TDD scaffold artifacts before re-planning.
# Safe: only removes files in the dedicated tests/tdd/ directory and stubs.
__cleanup_tdd_artifacts() {
    [[ -f ".claude/tdd-manifest.json" ]] || return 0
    # Remove the dedicated TDD test directory (safe — only contains scaffold-created files)
    local tdd_dir
    tdd_dir=$(jq -r '.test_dir // ""' ".claude/tdd-manifest.json" 2>/dev/null) || true
    if [[ -n "$tdd_dir" && -d "$tdd_dir" ]]; then
        rm -rf "$tdd_dir"
    fi
    # Remove stub files (build agent should have replaced these, but clean up if not)
    local _f
    for _f in $(jq -r '.stub_files[]? // empty' ".claude/tdd-manifest.json" 2>/dev/null); do
        [[ -f "$_f" ]] && rm -f "$_f"
    done
    rm -f .claude/tdd-manifest.json
}

# Check if the replan limit has been reached. Returns 1 (and marks task blocked)
# if already replanned once — caller must then `return 1`.
# Args: $1=task  $2=block_reason
__check_replan_limit() {
    local task="$1" block_reason="$2"
    if (( __replan_count >= 1 )); then
        print_error "Circuit breaker triggered again after re-planning. Stopping task."
        mark_task_blocked "$task" "$block_reason"
        clear_task_progress
        return 1
    fi
    return 0
}

# Trigger a full re-plan from research. Caller must `break` after calling this.
# Args: $1=context_message
__trigger_replan() {
    local context_msg="$1"
    ((__replan_count++))
    __replan_context="$context_msg"
    print_debug "Re-plan context: $__replan_context"
    __need_replan=true
    __completed_phases=""
    __cleanup_tdd_artifacts
    clear_task_progress
    update_workflow_state "replanning" "running"
}

run_optional_docs() {
    local task="$1" context="$2"
    [[ -d ".claude/skills/buildcrew-docs" ]] || return 0
    run_phase_group "docs" "$task" "$context" || true
}


print_task_start() {
    echo -e "\n${YELLOW}───────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}${BOLD}Task:${NC} $1"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}\n"
}

print_human_review_banner() {
    echo -e "\n${YELLOW}${BOLD}⚠═══════════════════════════════════════════════════════════════⚠${NC}"
    echo -e "${YELLOW}${BOLD}   HUMAN REVIEW REQUIRED${NC}"
    echo -e "${YELLOW}   \"The hard work of thinking can't be outsourced to AI,${NC}"
    echo -e "${YELLOW}    only amplified by it.\" —Jake Nations${NC}"
    echo -e "${YELLOW}${BOLD}⚠═══════════════════════════════════════════════════════════════⚠${NC}\n"
}

# Cleanup handler for EXIT/INT/TERM
cleanup() {
    trap '' INT TERM  # prevent re-entry
    stop_file_monitor
    # Kill child processes (claude -p) in the process group
    kill -- -$$ 2>/dev/null || true
    clear_workflow_state
    rm -f "$LOCKFILE"
}

# cleanup_log — called at the normal end of main() with the failed task count.
# Logs are always retained. On error() exits, the EXIT trap fires cleanup()
# (not cleanup_log), so the log is silently retained — the startup
# "Activity log: ..." message tells the user where it is.
cleanup_log() {
    [[ -z "$__LOG_FILE" ]] && return 0
    print_info "Activity log saved: $__LOG_FILE"
}

# Cleanup handler for discovery mode EXIT/INT/TERM trap.
# Kills heartbeat if running, clears state, removes lockfile.
_discovery_cleanup() {
    if [[ -n "${__DISCOVERY_HEARTBEAT_PID:-}" ]]; then
        kill "$__DISCOVERY_HEARTBEAT_PID" 2>/dev/null || true
        wait "$__DISCOVERY_HEARTBEAT_PID" 2>/dev/null || true
    fi
    clear_workflow_state
    rm -f "$LOCKFILE"
}

# Launch Claude in discovery mode, emitting state files for buildcrew-dash visibility.
# Unlike the former approach (which used exec), this keeps the shell alive so the
# heartbeat and cleanup trap can fire.
enter_discovery_mode() {
    local prompt="$1"
    mkdir -p .buildcrew
    log_init
    __WF_TASK_NUM=0
    __WF_TOTAL_TASKS=0
    __WF_TASK_NAME="Discovery mode"
    __INVOCATION_COUNT=0
    echo $$ > "$LOCKFILE"
    update_workflow_state "discovery" "running"
    trap '_discovery_cleanup' EXIT INT TERM
    ( while kill -0 $$ 2>/dev/null; do sleep 5; update_workflow_state "discovery" "running"; done ) &
    export __DISCOVERY_HEARTBEAT_PID=$!
    claude "$prompt" || true
    # Inline cleanup (normal exit path)
    kill "$__DISCOVERY_HEARTBEAT_PID" 2>/dev/null || true
    wait "$__DISCOVERY_HEARTBEAT_PID" 2>/dev/null || true
    __DISCOVERY_HEARTBEAT_PID=""
    clear_workflow_state
    rm -f "$LOCKFILE"
    trap - EXIT INT TERM
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────────
# Parallel batch mode — worktree-based parallel task execution
# ─────────────────────────────────────────────────────────────────────────────────

BATCH_DIR=".buildcrew/batch"
BATCH_MANIFEST="$BATCH_DIR/manifest.json"
BATCH_WORKTREE_DIR="$BATCH_DIR/worktrees"

__BATCH_HEARTBEAT_PID=""

# Batch state arrays (indexed, bash 3.2 compatible — no declare -A)
_batch_tasks=()
_batch_slugs=()
_batch_target_dirs=()
_batch_plan_refs=()

# Non-git parent mode detection (set in main())
__BATCH_PARENT_IS_GIT=true
# Absolute CWD captured once at batch startup (avoids repeated $(pwd) calls)
__BATCH_CWD=""
_batch_pids=()
_batch_running=0
_batch_completed=0
_batch_failed=0
_batch_rate_limited=0
_batch_next_idx=0
_batch_start_time=0
_batch_dashboard_lines=0

# ── Manifest functions ────────────────────────────────────────────────────────

# Initialize a new batch manifest.
_batch_init_manifest() {
    local base_branch="$1" base_commit="$2"
    mkdir -p "$BATCH_DIR" "$BATCH_WORKTREE_DIR"
    jq -n \
        --arg id "$(date +%Y%m%d-%H%M%S)-$$" \
        --arg branch "$base_branch" \
        --arg commit "$base_commit" \
        --argjson max "$MAX_PARALLEL" \
        --arg started "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        '{batch_id: $id, base_branch: $branch, base_commit: $commit,
          max_parallel: $max, started_at: $started, tasks: []}' \
        > "$BATCH_MANIFEST.tmp" \
        && mv "$BATCH_MANIFEST.tmp" "$BATCH_MANIFEST"
}

# Add a task entry to the manifest.
_batch_add_task() {
    local index="$1" text="$2" slug="$3" target_dir="${4:-}" plan_ref="${5:-}"
    local branch="buildcrew/$slug"
    local worktree
    worktree=$(_batch_worktree_path "$slug" "$target_dir")
    jq --argjson idx "$index" \
       --arg text "$text" \
       --arg slug "$slug" \
       --arg branch "$branch" \
       --arg wt "$worktree" \
       --arg td "$target_dir" \
       --arg pr "$plan_ref" \
       '.tasks += [{index: $idx, text: $text, slug: $slug, branch: $branch,
                    worktree: $wt, target_dir: $td, plan_ref: $pr, status: "pending",
                    exit_code: null, started_at: null, completed_at: null}]' \
       "$BATCH_MANIFEST" > "$BATCH_MANIFEST.tmp" \
       && mv "$BATCH_MANIFEST.tmp" "$BATCH_MANIFEST"
}

# Update a task's status in the manifest.
_batch_mark_task() {
    local index="$1" status="$2" exit_code="${3:-null}"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%S)
    if [[ "$status" == "running" ]]; then
        jq --argjson idx "$index" \
           --arg status "$status" \
           --arg ts "$ts" \
           '(.tasks[] | select(.index == $idx)) |= (.status = $status | .started_at = $ts)' \
           "$BATCH_MANIFEST" > "$BATCH_MANIFEST.tmp" \
           && mv "$BATCH_MANIFEST.tmp" "$BATCH_MANIFEST"
    else
        jq --argjson idx "$index" \
           --arg status "$status" \
           --arg ts "$ts" \
           --argjson ec "$exit_code" \
           '(.tasks[] | select(.index == $idx)) |= (.status = $status | .completed_at = $ts | .exit_code = $ec)' \
           "$BATCH_MANIFEST" > "$BATCH_MANIFEST.tmp" \
           && mv "$BATCH_MANIFEST.tmp" "$BATCH_MANIFEST"
    fi
}

# Load manifest for resume. Returns 0 if valid manifest with incomplete tasks exists.
_batch_load_manifest() {
    [[ -f "$BATCH_MANIFEST" ]] || return 1
    jq -e . "$BATCH_MANIFEST" >/dev/null 2>&1 || return 1
    local incomplete
    incomplete=$(jq '[.tasks[] | select(.status != "completed")] | length' "$BATCH_MANIFEST")
    [[ "$incomplete" -gt 0 ]] || return 1
    return 0
}

# Get the status of a task from the manifest.
_batch_get_task_status() {
    local manifest_idx="$1"
    jq -r --argjson idx "$manifest_idx" \
        '.tasks[] | select(.index == $idx) | .status' "$BATCH_MANIFEST" 2>/dev/null || echo "unknown"
}

# ── Worktree management ──────────────────────────────────────────────────────

# Resolve worktree path: absolute when target_dir is set, relative otherwise.
_batch_worktree_path() {
    local slug="$1" target_dir="${2:-}"
    if [[ -n "$target_dir" ]]; then
        echo "${__BATCH_CWD}/$BATCH_WORKTREE_DIR/$slug"
    else
        echo "$BATCH_WORKTREE_DIR/$slug"
    fi
}

# Create a git worktree for a task. Returns 0 on success, 1 on failure.
# When target_dir is set, creates the worktree from that repo instead of CWD.
_batch_create_worktree() {
    local slug="$1" base_branch="$2" target_dir="${3:-}"
    local branch_name="buildcrew/$slug"
    local worktree_path abs_target_dir

    # Resolve git repo directory and worktree path based on mode
    local repo_dir="." source_dir="."
    if [[ -n "$target_dir" ]]; then
        # Non-git parent mode: resolve target repo
        abs_target_dir="$(cd "$target_dir" 2>/dev/null && pwd)" || {
            print_error "Target directory '$target_dir' does not exist"
            return 1
        }
        repo_dir="$abs_target_dir"
        source_dir="$abs_target_dir"
        worktree_path=$(_batch_worktree_path "$slug" "$target_dir")
        # Resolve base branch from target repo (ignore caller's base_branch)
        base_branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD)
    else
        worktree_path=$(_batch_worktree_path "$slug")
    fi

    # Clean up stale branch/worktree from previous run
    git -C "$repo_dir" worktree prune 2>/dev/null || true
    if git -C "$repo_dir" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        if ! git -C "$repo_dir" branch -D "$branch_name" 2>/dev/null; then
            print_warning "Could not delete stale branch '$branch_name' — may still be checked out by a worktree"
        fi
    fi
    if [[ -d "$worktree_path" ]]; then
        git -C "$repo_dir" worktree remove --force "$worktree_path" 2>/dev/null || rm -rf "$worktree_path"
    fi

    # Create worktree with new branch
    local worktree_err
    if ! worktree_err=$(git -C "$repo_dir" worktree add -b "$branch_name" "$worktree_path" "$base_branch" 2>&1); then
        print_error "Failed to create worktree for '$slug': $worktree_err"
        return 1
    fi

    # Copy skills (preserving symlinks) and settings from source repo
    if [[ -d "$source_dir/.claude/skills" ]] || [[ -L "$source_dir/.claude/skills" ]]; then
        mkdir -p "$worktree_path/.claude/skills"
        cp -a "$source_dir/.claude/skills/"* "$worktree_path/.claude/skills/" 2>/dev/null || true
    fi

    # Fallback: if source repo had no skills, symlink from BUILDCREW_HOME
    if [[ ! -d "$worktree_path/.claude/skills/buildcrew" ]] && [[ -d "$BUILDCREW_HOME/skills" ]]; then
        mkdir -p "$worktree_path/.claude/skills"
        local skill_dir skill_name
        for skill_dir in "$BUILDCREW_HOME/skills"/*/; do
            [ -d "$skill_dir" ] || continue
            skill_name="$(basename "$skill_dir")"
            if [[ ! -e "$worktree_path/.claude/skills/$skill_name" ]]; then
                ln -s "$skill_dir" "$worktree_path/.claude/skills/$skill_name"
            fi
        done
    fi

    local f
    for f in .claude/settings.json .claude/settings.local.json .claude/.buildcrew-link; do
        if [[ -f "$source_dir/$f" ]]; then
            mkdir -p "$worktree_path/$(dirname "$f")"
            cp "$source_dir/$f" "$worktree_path/$f" 2>/dev/null || true
        fi
    done

    # Fallback: create .buildcrew-link if source repo didn't have one
    if [[ ! -f "$worktree_path/.claude/.buildcrew-link" ]]; then
        mkdir -p "$worktree_path/.claude"
        echo "BUILDCREW_HOME=$BUILDCREW_HOME" > "$worktree_path/.claude/.buildcrew-link"
    fi

    # Copy buildcrew config, lessons, and context from CWD (parent/orchestrator state)
    mkdir -p "$worktree_path/.buildcrew"
    if [[ -f ".buildcrew/config" ]]; then
        cp ".buildcrew/config" "$worktree_path/.buildcrew/config"
    fi
    if [[ -f ".buildcrew/lessons.md" ]]; then
        cp ".buildcrew/lessons.md" "$worktree_path/.buildcrew/lessons.md"
    fi
    if [[ -d ".buildcrew/context" ]]; then
        cp -R ".buildcrew/context" "$worktree_path/.buildcrew/context"
    fi

    # Create logs dir in worktree for child output
    mkdir -p "$worktree_path/.buildcrew/logs"

    return 0
}

# Remove a worktree (keeps the branch for review).
# Tries relative path first, then absolute path (non-git parent mode).
_batch_remove_worktree() {
    local slug="$1"
    local wt_path="$BATCH_WORKTREE_DIR/$slug"

    # Also check absolute path for non-git parent mode
    [[ -n "$__BATCH_CWD" ]] && [[ ! -d "$wt_path" ]] && wt_path="${__BATCH_CWD}/$BATCH_WORKTREE_DIR/$slug"

    # Try standard removal first
    if git worktree remove --force "$wt_path" 2>/dev/null; then
        return 0
    fi

    # Fallback: discover git repo from inside the worktree and remove from there
    if [[ -d "$wt_path" ]]; then
        local git_dir
        git_dir=$(git -C "$wt_path" rev-parse --git-common-dir 2>/dev/null) || true
        if [[ -n "$git_dir" ]]; then
            local repo_dir
            repo_dir=$(cd "$wt_path" && cd "$git_dir/.." 2>/dev/null && pwd) || true
            if [[ -n "$repo_dir" ]]; then
                git -C "$repo_dir" worktree remove --force "$wt_path" 2>/dev/null || rm -rf "$wt_path"
                return 0
            fi
        fi
        # Last resort
        rm -rf "$wt_path"
    fi
}

# Clean up worktrees for completed tasks only.
_batch_cleanup_completed_worktrees() {
    [[ -f "$BATCH_MANIFEST" ]] || return 0
    local slug
    while IFS= read -r slug; do
        [[ -n "$slug" ]] && _batch_remove_worktree "$slug"
    done < <(jq -r '.tasks[] | select(.status == "completed") | .slug' "$BATCH_MANIFEST")
}

# ── Task launch and pool management ──────────────────────────────────────────

# Launch a single task in its worktree as a background process.
_batch_launch_task() {
    local idx="$1"
    local task="${_batch_tasks[$idx]}"
    local slug="${_batch_slugs[$idx]}"
    local target_dir="${_batch_target_dirs[$idx]:-}"
    local plan_ref="${_batch_plan_refs[$idx]:-}"
    local manifest_idx=$((idx + 1))

    # Prepend [plan:...] to task text so child workflow receives it
    if [[ -n "$plan_ref" ]]; then
        task="[plan:${plan_ref}] ${task}"
    fi

    local worktree
    worktree=$(_batch_worktree_path "$slug" "$target_dir")

    _batch_mark_task "$manifest_idx" "running"

    (
        cd "$worktree" || exit 1
        export BUILDCREW_BATCH_NONCE="${slug}-${idx}"
        export BUILDCREW_BATCH_PARENT_CWD="${__BATCH_CWD}"
        export BUILDCREW_HOME
        export AUTO_MODE=true  # Batch workers must run unattended

        # When target_dir is set, export absolute BACKLOG_FILE path back to parent
        if [[ -n "$target_dir" ]]; then
            export BACKLOG_FILE="${__BATCH_CWD}/${BACKLOG_FILE}"
        fi

        exec "$BUILDCREW_HOME/lib/workflow.sh" \
            --single --task-exact "$task" \
            --max-invocations "$MAX_INVOCATIONS" \
            --model "$CLAUDE_MODEL" \
            $( [[ -n "${CLAUDE_EFFORT:-}" ]] && echo "--effort $CLAUDE_EFFORT" ) \
            $( [[ "$SKIP_SPEC" == "true" ]] && echo "--skip-spec" ) \
            $( [[ "$SKIP_PREREQS" == "true" ]] && echo "--skip-prereqs" ) \
            $( [[ "$FULL_PIPELINE" == "true" ]] && echo "--full-pipeline" ) \
            $( [[ "$VERBOSE" == "true" ]] && echo "--verbose" ) \
            $( [[ "$NO_UAT" == "true" ]] && echo "--no-uat" ) \
            > ".buildcrew/logs/batch-${slug}.log" 2>&1
    ) &
    _batch_pids[$idx]=$!
    _batch_running=$(( _batch_running + 1 ))

    log_msg "Launched task $manifest_idx: '$task' (PID=${_batch_pids[$idx]}, worktree=$worktree)"
}

# Check all running tasks for completion. Handles results.
_batch_poll_tasks() {
    local i
    for i in "${!_batch_pids[@]}"; do
        local pid="${_batch_pids[$i]:-}"
        [[ -z "$pid" ]] && continue
        if ! kill -0 "$pid" 2>/dev/null; then
            local exit_code=0
            wait "$pid" 2>/dev/null || exit_code=$?
            _batch_pids[$i]=""
            _batch_running=$(( _batch_running - 1 ))
            local manifest_idx=$((i + 1))
            local task_text="${_batch_tasks[$i]}"
            if [[ $exit_code -eq 0 ]]; then
                # Sentinel check: verify the task actually reached verify/complete
                local _wt_path _sentinel
                _wt_path=$(_batch_worktree_path "${_batch_slugs[$i]}" "${_batch_target_dirs[$i]:-}")
                local _phase_result="$_wt_path/.claude/phase-result.json"
                if [[ -f "$_phase_result" ]]; then
                    _sentinel=$(jq -r '"\(.phase)/\(.verdict)"' "$_phase_result" 2>/dev/null) || _sentinel=""
                else
                    _sentinel=""
                fi
                if [[ "$_sentinel" == "verify/complete" ]]; then
                    _batch_mark_task "$manifest_idx" "completed" "0"
                    _batch_completed=$(( _batch_completed + 1 ))
                    # Sync completion to BACKLOG.md (parent-side — child's mark is uncommitted and lost during squash merge)
                    local _saved_bf="$BACKLOG_FILE"
                    [[ "$BACKLOG_FILE" != /* ]] && BACKLOG_FILE="$__BATCH_CWD/$BACKLOG_FILE"
                    mark_task_complete "$task_text"
                    BACKLOG_FILE="$_saved_bf"
                    log_msg "Task $manifest_idx completed: '$task_text'"
                else
                    _batch_mark_task "$manifest_idx" "failed" "0"
                    _batch_failed=$(( _batch_failed + 1 ))
                    log_msg "Task $manifest_idx failed (sentinel=${_sentinel:-missing}): '$task_text'"
                fi
            elif [[ $exit_code -eq 4 ]]; then
                _batch_mark_task "$manifest_idx" "rate_limited" "4"
                _batch_rate_limited=$(( _batch_rate_limited + 1 ))
                log_msg "Task $manifest_idx rate-limited: '$task_text'"
            else
                _batch_mark_task "$manifest_idx" "failed" "$exit_code"
                _batch_failed=$(( _batch_failed + 1 ))
                log_msg "Task $manifest_idx failed (exit=$exit_code): '$task_text'"
            fi
        fi
    done
}

# Display a compact status dashboard.
_batch_refresh_dashboard() {
    # Clear previous dashboard lines
    if (( _batch_dashboard_lines > 0 )); then
        printf '\033[%dA\033[J' "$_batch_dashboard_lines"
    fi

    local now elapsed elapsed_str total pending
    now=$(date +%s)
    elapsed=$(( now - _batch_start_time ))
    elapsed_str=$(printf '%dm%02ds' $((elapsed / 60)) $((elapsed % 60)))
    total=${#_batch_tasks[@]}
    pending=$(( total - _batch_completed - _batch_failed - _batch_rate_limited - _batch_running ))

    echo -e "${BLUE}═══ Batch Status ($elapsed_str) ═════════════════════════════════════${NC}"
    if (( _batch_rate_limited > 0 )); then
        echo -e "  Running: ${GREEN}$_batch_running${NC}/$MAX_PARALLEL  |  Done: ${GREEN}$_batch_completed${NC}  |  Failed: ${RED}$_batch_failed${NC}  |  Rate-Limited: ${YELLOW}$_batch_rate_limited${NC}  |  Pending: $pending  |  Total: $total"
    else
        echo -e "  Running: ${GREEN}$_batch_running${NC}/$MAX_PARALLEL  |  Done: ${GREEN}$_batch_completed${NC}  |  Failed: ${RED}$_batch_failed${NC}  |  Pending: $pending  |  Total: $total"
    fi

    local lines=2
    # Show status for each running task
    local i
    for i in "${!_batch_pids[@]}"; do
        local pid="${_batch_pids[$i]:-}"
        [[ -z "$pid" ]] && continue
        local slug="${_batch_slugs[$i]}"
        local phase="starting"
        local state_file="$BATCH_WORKTREE_DIR/$slug/.buildcrew/.workflow-state"
        if [[ -f "$state_file" ]]; then
            local key val
            while IFS='=' read -r key val; do
                [[ "$key" == "PHASE" ]] && { phase="$val"; break; }
            done < "$state_file"
        fi
        local task_short="${_batch_tasks[$i]}"
        if (( ${#task_short} > 50 )); then
            task_short="${task_short:0:47}..."
        fi
        echo -e "  ${CYAN}[$((i + 1))]${NC} $task_short  ${YELLOW}[$phase]${NC}"
        (( lines++ )) || true
    done
    echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"
    (( lines++ )) || true
    _batch_dashboard_lines=$lines
}

# ── Cleanup and post-completion ───────────────────────────────────────────────

# Start a background heartbeat that updates workflow state every 5 seconds.
_batch_start_heartbeat() {
    ( while kill -0 $$ 2>/dev/null; do sleep 5; update_workflow_state "batch" "running"; done ) &
    __BATCH_HEARTBEAT_PID=$!
}

# Stop the batch heartbeat process.
_batch_stop_heartbeat() {
    if [[ -n "${__BATCH_HEARTBEAT_PID:-}" ]]; then
        kill "$__BATCH_HEARTBEAT_PID" 2>/dev/null || true
        wait "$__BATCH_HEARTBEAT_PID" 2>/dev/null || true
        __BATCH_HEARTBEAT_PID=""
    fi
}

# Trap handler for Ctrl-C during batch execution.
_batch_parallel_cleanup() {
    trap '' INT TERM
    echo ""
    print_warning "Batch interrupted. Terminating running tasks..."

    # Kill entire process group (reaches all workers + grandchildren).
    # Safe: trap '' INT TERM above makes orchestrator ignore this self-signal.
    kill -- -$$ 2>/dev/null || true

    # Mark still-live tracked tasks as interrupted in manifest
    local i
    for i in "${!_batch_pids[@]}"; do
        local pid="${_batch_pids[$i]:-}"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            local manifest_idx=$((i + 1))
            _batch_mark_task "$manifest_idx" "interrupted" "130"
        fi
    done

    # Grace period for graceful shutdown
    sleep 2

    # Force-kill any remaining tracked processes (per-PID, not process-group —
    # SIGKILL cannot be trapped, so process-group SIGKILL would kill the orchestrator)
    for i in "${!_batch_pids[@]}"; do
        local pid="${_batch_pids[$i]:-}"
        [[ "$pid" == "$$" ]] && continue
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done

    # Reap all children
    wait 2>/dev/null || true

    _batch_stop_heartbeat

    clear_workflow_state
    rm -f "$LOCKFILE"

    print_info "Batch state saved to $BATCH_MANIFEST"
    print_info "Resume with: buildcrew run --batch --resume"
    return 130 2>/dev/null || exit 130
}

# Push branches and create PRs for completed tasks.
_batch_create_prs() {
    local base_branch="$1"
    # PR creation not supported in non-git-parent mode (multi-repo)
    if [[ "$__BATCH_PARENT_IS_GIT" == "false" ]]; then
        print_info "PR creation not supported in multi-repo mode. Push branches manually from each target repo."
        return
    fi
    local i
    for i in "${!_batch_tasks[@]}"; do
        local manifest_idx=$((i + 1))
        local status
        status=$(_batch_get_task_status "$manifest_idx")
        if [[ "$status" == "completed" ]]; then
            local branch_name="buildcrew/${_batch_slugs[$i]}"
            local task_text="${_batch_tasks[$i]}"
            print_info "Pushing $branch_name..."
            if git push -u origin "$branch_name" 2>/dev/null; then
                local pr_title
                pr_title=$(echo "$task_text" | cut -c1-70)
                if gh pr create --title "$pr_title" \
                    --body "Task: $task_text"$'\n\n'"*Generated by BuildCrew batch mode*" \
                    --base "$base_branch" \
                    --head "$branch_name" 2>/dev/null; then
                    print_success "PR created for: $task_text"
                else
                    print_warning "PR creation failed for: $task_text"
                fi
            else
                print_warning "Push failed for: $branch_name"
            fi
        fi
    done
}

# Merge completed worktree branches onto a new merge branch (smallest diff first).
# Prints the merge branch name to stdout on success, returns 1 if all merges fail.
_batch_merge_worktrees() {
    local base_branch="$1"
    local merge_branch="buildcrew/batch-merged-$(date +%Y%m%d-%H%M%S)"

    cd "$__BATCH_CWD" || return 1

    local base_commit
    base_commit=$(jq -r '.base_commit' "$BATCH_MANIFEST")

    git checkout -b "$merge_branch" "$base_branch" 2>/dev/null || return 1

    # Sort completed tasks by diff size (smallest first)
    local sorted_entries=()
    local i
    for i in "${!_batch_tasks[@]}"; do
        local status
        status=$(_batch_get_task_status $((i + 1)))
        [[ "$status" != "completed" ]] && continue
        local branch="buildcrew/${_batch_slugs[$i]}"
        local diff_size=999
        diff_size=$(git diff --numstat "${base_commit}..${branch}" 2>/dev/null | awk '{s+=$1+$2}END{print s+0}') || diff_size=999
        sorted_entries+=("$diff_size:$i")
    done
    # Sort by diff size (numeric)
    local sorted_sorted=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && sorted_sorted+=("$line")
    done < <(printf '%s\n' "${sorted_entries[@]}" | sort -t: -k1 -n)

    local merged_count=0 conflict_count=0
    local entry
    for entry in "${sorted_sorted[@]}"; do
        i="${entry#*:}"
        local manifest_idx=$((i + 1))
        local branch="buildcrew/${_batch_slugs[$i]}"

        if git merge --squash "$branch" 2>/dev/null && git commit -m "batch: ${_batch_tasks[$i]}" 2>/dev/null; then
            merged_count=$((merged_count + 1))
        else
            git merge --abort 2>/dev/null || git reset --hard HEAD 2>/dev/null || true
            conflict_count=$((conflict_count + 1))
            _batch_mark_task "$manifest_idx" "merge_conflict"
            log_msg "Merge conflict: task $manifest_idx (${_batch_tasks[$i]})"
        fi
    done

    if (( merged_count == 0 )); then
        git checkout "$base_branch" 2>/dev/null
        git branch -D "$merge_branch" 2>/dev/null || true
        return 1
    fi

    print_info "Merged $merged_count task(s). Conflicts: $conflict_count" >&2
    echo "$merge_branch"
}

# Assemble combined context from all merged task worktrees into .claude/batch-combined-context.md.
# Must run before worktree cleanup.
_batch_assemble_combined_context() {
    cd "$__BATCH_CWD" || return 0
    mkdir -p .claude

    local context_file=".claude/batch-combined-context.md"
    echo "# Batch Combined Context" > "$context_file"
    echo "" >> "$context_file"
    echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$context_file"
    echo "" >> "$context_file"

    local i
    for i in "${!_batch_tasks[@]}"; do
        local status
        status=$(_batch_get_task_status $((i + 1)))
        [[ "$status" != "completed" ]] && continue

        local wt_path
        wt_path=$(_batch_worktree_path "${_batch_slugs[$i]}" "${_batch_target_dirs[$i]:-}")

        echo "---" >> "$context_file"
        echo "## Task $((i + 1)): ${_batch_tasks[$i]}" >> "$context_file"
        echo "" >> "$context_file"

        # Copy spec (extract AC lines in full, truncate rest)
        if [[ -f "$wt_path/.claude/spec.md" ]]; then
            echo "### Acceptance Criteria" >> "$context_file"
            grep -E '^- \[ \] AC-|^- \[x\] AC-' "$wt_path/.claude/spec.md" >> "$context_file" 2>/dev/null || true
            echo "" >> "$context_file"
        fi

        # Copy plan (truncate to 50 lines, single read)
        if [[ -f "$wt_path/.claude/current-plan.md" ]]; then
            echo "### Plan" >> "$context_file"
            local plan_preview
            plan_preview=$(head -51 "$wt_path/.claude/current-plan.md")
            local preview_lines
            preview_lines=$(printf '%s\n' "$plan_preview" | wc -l)
            printf '%s\n' "$plan_preview" | head -50 >> "$context_file"
            if (( preview_lines > 50 )); then
                echo "... (truncated) ..." >> "$context_file"
            fi
            echo "" >> "$context_file"
        fi
    done

    log_msg "Assembled batch combined context: $context_file"
}

# Run post-build phases (verify) on merged code.
_batch_run_post_build() {
    local merge_branch="$1"
    local base_branch="$2"
    local task_summary="Batch verification: merged tasks on $merge_branch"

    cd "$__BATCH_CWD" || return 1

    # Docs (optional, non-blocking)
    if [[ "$COMPLEXITY_AWARE" == "true" ]]; then
        run_optional_docs "$task_summary" \
            "Batch mode: reviewing combined changes. See .claude/batch-combined-context.md"
    fi


    # Merged verify (includes AC verification)
    run_phase_group "verify" "$task_summary" \
        "BATCH MODE: Read .claude/batch-combined-context.md for all task specs/plans. Verify each task's ACs independently." \
        || return 1

    local verdict
    verdict=$(jq -r '.verdict' "$PHASE_RESULT_FILE" 2>/dev/null)
    [[ "$verdict" == "complete" ]] && return 0
    return 1
}

# Post-completion: summary, optional PR creation, worktree cleanup.
_batch_post_completion() {
    local base_branch="$1"

    _batch_stop_heartbeat

    local end_time duration
    end_time=$(date +%s)
    duration=$(( end_time - _batch_start_time ))

    echo ""
    print_header "Batch Execution Complete"
    echo -e "  ${GREEN}Completed:${NC}  $_batch_completed"
    echo -e "  ${RED}Failed:${NC}     $_batch_failed"
    echo -e "  ${CYAN}Duration:${NC}   $(printf '%dm%02ds' $((duration / 60)) $((duration % 60)))"
    echo ""

    # List branches for completed tasks
    if (( _batch_completed > 0 )); then
        print_info "Completed task branches:"
        local i
        for i in "${!_batch_tasks[@]}"; do
            local status
            status=$(_batch_get_task_status $((i + 1)))
            if [[ "$status" == "completed" ]]; then
                echo -e "  ${GREEN}*${NC} buildcrew/${_batch_slugs[$i]}  --  ${_batch_tasks[$i]}"
            fi
        done
        echo ""
    fi

    # List failures
    if (( _batch_failed > 0 )); then
        print_warning "Failed tasks:"
        local i
        for i in "${!_batch_tasks[@]}"; do
            local status
            status=$(_batch_get_task_status $((i + 1)))
            if [[ "$status" == "failed" ]]; then
                local slug="${_batch_slugs[$i]}"
                local log_path="$BATCH_WORKTREE_DIR/$slug/.buildcrew/logs/batch-${slug}.log"
                echo -e "  ${RED}x${NC} ${_batch_tasks[$i]}  (log: $log_path)"
            fi
        done
        echo ""
    fi

    # List merge conflicts (single pass: collect lines, then print if any)
    local merge_conflict_lines=""
    for i in "${!_batch_tasks[@]}"; do
        local status
        status=$(_batch_get_task_status $((i + 1)))
        if [[ "$status" == "merge_conflict" ]]; then
            merge_conflict_lines="${merge_conflict_lines}  ${YELLOW}!${NC} buildcrew/${_batch_slugs[$i]}  --  ${_batch_tasks[$i]}"$'\n'
        fi
    done
    if [[ -n "$merge_conflict_lines" ]]; then
        print_warning "Merge conflicts (inspect branches manually):"
        echo -e "$merge_conflict_lines"
    fi

    # Assemble combined context (before worktree cleanup)
    if (( _batch_completed > 0 )); then
        _batch_assemble_combined_context
    fi

    # Merge + post-build verification (single-repo mode only)
    local merge_branch=""
    if (( _batch_completed > 0 )) && [[ "$__BATCH_PARENT_IS_GIT" == "true" ]]; then
        print_header "Post-Build: Merge + Verify"
        merge_branch=$(_batch_merge_worktrees "$base_branch") || true

        if [[ -n "$merge_branch" ]]; then
            if _batch_run_post_build "$merge_branch" "$base_branch"; then
                print_success "Post-build verification passed on $merge_branch"

                # Post-completion UAT on merged code
                if [[ "$NO_UAT" != "true" && -f "README.md" ]]; then
                    local _uat_project _uat_result=0
                    _uat_project="$(basename "$(pwd)")"
                    local _uat_task="[UAT] Fix failing acceptance tests for $_uat_project — see .buildcrew/uat-context.md for details"
                    run_inline_uat "$_uat_project" "$_uat_task" "standard" || _uat_result=$?
                    if [[ $_uat_result -eq 2 ]]; then
                        print_warning "UAT completed with disputed scenarios"
                    elif [[ $_uat_result -ne 0 ]]; then
                        print_error "UAT failed — run 'buildcrew uat' after fixing issues"
                    fi
                fi
            else
                print_warning "Post-build verification failed"
                # Log per-task AC results if available
                if [[ -f ".claude/outcome-report.md" ]]; then
                    print_info "AC results in .claude/outcome-report.md"
                fi
                # Print individual branch names for inspection
                print_info "Individual task branches preserved for inspection:"
                for i in "${!_batch_tasks[@]}"; do
                    local status
                    status=$(_batch_get_task_status $((i + 1)))
                    if [[ "$status" == "completed" ]]; then
                        echo -e "  ${CYAN}*${NC} buildcrew/${_batch_slugs[$i]}"
                    fi
                done
                # Restore clean state
                git checkout "$base_branch" 2>/dev/null || true
                git branch -D "$merge_branch" 2>/dev/null || true
                merge_branch=""
                # Mark merged tasks as verify_failed
                for i in "${!_batch_tasks[@]}"; do
                    local status
                    status=$(_batch_get_task_status $((i + 1)))
                    if [[ "$status" == "completed" ]]; then
                        _batch_mark_task $((i + 1)) "verify_failed"
                    fi
                done
            fi
        else
            print_warning "No tasks merged cleanly — skipping post-build verification"
        fi
    fi

    # PR creation offer (only if gh is available, remote exists, and parent is a git repo)
    if (( _batch_completed > 0 )) && [[ "$__BATCH_PARENT_IS_GIT" == "true" ]]; then
        if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
            if git remote get-url origin &>/dev/null 2>&1; then
                if [[ -t 0 ]] && [[ "$AUTO_MODE" != "true" ]]; then
                    echo -e "  ${BOLD}[p]${NC} Push branches and create PRs  |  ${BOLD}[Enter]${NC} Skip"
                    read -r pr_response
                    if [[ "$pr_response" == "p" || "$pr_response" == "P" ]]; then
                        _batch_create_prs "$base_branch"
                    fi
                else
                    print_info "Push branches and create PRs manually, or re-run with --interactive."
                fi
            fi
        fi
    fi

    # Clean up completed worktrees (leave failed for debugging)
    _batch_cleanup_completed_worktrees

    clear_workflow_state
    rm -f "$LOCKFILE"

    trap - EXIT INT TERM
    if (( _batch_failed > 0 )); then
        exit 1
    fi
    exit 0
}

# ── Parse task list and handle slug collisions ────────────────────────────────

# Check if a slug is already enrolled in the _batch_slugs array.
_is_slug_enrolled() {
    local slug="$1"
    local idx
    for idx in "${!_batch_slugs[@]}"; do
        [[ "${_batch_slugs[$idx]}" == "$slug" ]] && return 0
    done
    return 1
}

# Validate target directory when parent is not a git repo.
# Returns 0 if valid, prints warning and returns 1 if invalid.
_validate_target_dir() {
    local text="$1"
    local target_dir="$2"

    if [[ -z "$target_dir" ]]; then
        print_warning "Hot-reload: skipping '$text' — no target directory"
        return 1
    elif [[ ! -d "$target_dir" ]]; then
        print_warning "Hot-reload: skipping '$text' — target dir '$target_dir' does not exist"
        return 1
    elif ! git -C "$target_dir" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        print_warning "Hot-reload: skipping '$text' — target dir '$target_dir' is not a git repo"
        return 1
    elif [[ -n "$(git -C "$target_dir" status --porcelain 2>/dev/null)" ]]; then
        print_warning "Hot-reload: skipping '$text' — target dir '$target_dir' has uncommitted changes"
        return 1
    fi
    return 0
}

# Parse the numbered task list into _batch_tasks[], _batch_slugs[], and _batch_target_dirs[] arrays.
# gather_pending_tasks preserves [dir:...] prefixes; this function extracts and strips them.
_batch_parse_task_list() {
    local task_list="$1"
    _batch_tasks=()
    _batch_slugs=()
    _batch_target_dirs=()
    _batch_plan_refs=()
    local i=0
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local text="${line#*. }"  # strip " 1. " prefix
        [[ -z "$text" ]] && continue

        # Extract and strip [plan:...] prefix (before [dir:...])
        local plan_ref
        plan_ref=$(extract_task_plan_ref "$text")
        text=$(strip_task_plan_ref "$text")

        # Extract and strip [dir:...] prefix
        local target_dir
        target_dir=$(resolve_task_target_dir "$text")
        text=$(strip_task_dir "$text")

        _batch_tasks[$i]="$text"
        _batch_target_dirs[$i]="$target_dir"
        _batch_plan_refs[$i]="$plan_ref"

        # Prefix slug with dir name for uniqueness across repos
        local slug
        slug=$(task_to_slug "$text")
        if [[ -n "$target_dir" ]]; then
            slug="$(task_to_slug "$target_dir")-${slug}"
            slug="${slug:0:60}"
        fi

        # Collision check: deduplicate slugs
        if _is_slug_enrolled "$slug" || git rev-parse --verify "buildcrew/$slug" >/dev/null 2>&1; then
            slug="${slug}-${i}"
        fi
        _batch_slugs[$i]="$slug"
        (( i++ )) || true
    done <<< "$task_list"
}

# Detect new pending tasks in BACKLOG.md and enroll them into the running batch.
# Called periodically from _batch_dispatch_loop (every ~15s).
_batch_check_new_tasks() {
    local base_branch="$1"

    # Re-read BACKLOG via gather_pending_tasks (resolves relative path same as _batch_resume)
    local _saved_bf="$BACKLOG_FILE"
    [[ "$BACKLOG_FILE" != /* ]] && BACKLOG_FILE="$__BATCH_CWD/$BACKLOG_FILE"
    gather_pending_tasks
    BACKLOG_FILE="$_saved_bf"

    [[ "$__BATCH_TASK_COUNT" -eq 0 ]] && return 0

    local line text plan_ref target_dir slug new_idx added=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        text="${line#*. }"  # strip " N. " prefix
        [[ -z "$text" ]] && continue

        # Extract and strip [plan:...] then [dir:...] — same order as _batch_parse_task_list
        plan_ref=$(extract_task_plan_ref "$text")
        text=$(strip_task_plan_ref "$text")
        target_dir=$(resolve_task_target_dir "$text")
        text=$(strip_task_dir "$text")

        # Generate slug matching _batch_parse_task_list logic
        slug=$(task_to_slug "$text")
        if [[ -n "$target_dir" ]]; then
            slug="$(task_to_slug "$target_dir")-${slug}"
            slug="${slug:0:60}"
        fi

        # Dedup: skip if slug already enrolled
        _is_slug_enrolled "$slug" && continue

        # New task: suffix slug on branch collision (genuinely new task, old branch exists)
        new_idx=${#_batch_tasks[@]}
        if git rev-parse --verify "buildcrew/$slug" >/dev/null 2>&1; then
            slug="${slug}-${new_idx}"
        fi

        # Validate target dir when parent is not a git repo
        if [[ "$__BATCH_PARENT_IS_GIT" == "false" ]]; then
            _validate_target_dir "$text" "$target_dir" || continue
        fi

        # Create worktree first — only enroll on success
        if ! _batch_create_worktree "$slug" "$base_branch" "$target_dir"; then
            print_warning "Hot-reload: failed to create worktree for '$text' — skipping"
            continue
        fi

        # Enroll in parallel arrays
        _batch_tasks[$new_idx]="$text"
        _batch_slugs[$new_idx]="$slug"
        _batch_target_dirs[$new_idx]="$target_dir"
        _batch_plan_refs[$new_idx]="$plan_ref"
        _batch_pids[$new_idx]=""

        # Update manifest (1-based index)
        _batch_add_task $((new_idx + 1)) "$text" "$slug" "$target_dir" "$plan_ref"

        # Keep total task counter accurate for status reporting
        __WF_TOTAL_TASKS=${#_batch_tasks[@]}

        log_msg "Hot-reload: enrolled new task '$text' (slug: $slug)"
        (( added++ )) || true
    done <<< "$__BATCH_TASK_LIST"

    if (( added > 0 )); then
        print_info "Hot-reload: added $added new task(s) to batch"
    fi
}

# ── Shared dispatch loop ──────────────────────────────────────────────────────

# Main dispatch loop — launches tasks up to MAX_PARALLEL, polls for completion.
_batch_dispatch_loop() {
    local base_branch="$1"
    local _batch_stopping=false
    local _reload_counter=0
    local _batch_paused=false
    local _batch_quit=false
    local _batch_rate_limit_backoff=300  # 5 min initial backoff

    while [[ "$_batch_quit" != "true" ]] && (( _batch_completed + _batch_failed < ${#_batch_tasks[@]} )); do
        _batch_poll_tasks || true

        # Rate limit pause: stop launching new tasks, drain, then enter pause UI
        if [[ "$_batch_paused" != "true" ]] && _check_rate_limit_pause "$__BATCH_CWD"; then
            _batch_paused=true
            _clear_rate_limit_pause "$__BATCH_CWD"
            print_warning "API rate/usage limit detected. Draining $_batch_running running task(s) before pausing..."
        fi

        if [[ "$_batch_paused" == "true" ]]; then
            if (( _batch_running == 0 )); then
                if _batch_handle_rate_limit_pause "$_batch_rate_limit_backoff"; then
                    _batch_paused=false
                    # Double backoff for next pause (cap at 60 min)
                    _batch_rate_limit_backoff=$(( _batch_rate_limit_backoff * 2 > 3600 ? 3600 : _batch_rate_limit_backoff * 2 ))
                    # Reset index so requeued tasks get picked up from the beginning
                    _batch_next_idx=0
                else
                    _batch_quit=true
                    break
                fi
            fi
            _batch_refresh_dashboard
            sleep 3
            continue
        fi

        # Hot-reload: check for new tasks periodically (every ~15s at current 3s sleep)
        (( _reload_counter++ )) || true
        if [[ "${BATCH_HOT_RELOAD:-}" != "false" ]] && (( _reload_counter >= 5 )); then
            _reload_counter=0
            if [[ "$_batch_stopping" != "true" ]]; then
                _batch_check_new_tasks "$base_branch"
            fi
        fi

        # Stop signal: drain running tasks, then exit
        if [[ "$_batch_stopping" != "true" ]] && check_stop_signal; then
            _batch_stopping=true
            log_msg "Stop signal detected. Running: $_batch_running, completed: $_batch_completed, next_idx: $_batch_next_idx"
            print_warning "Stop signal received. Draining $_batch_running running task(s) — no new launches."
            clear_stop_signal
        fi

        if [[ "$_batch_stopping" == "true" ]]; then
            if (( _batch_running == 0 )); then
                break
            fi
            _batch_refresh_dashboard
            sleep 3
            continue
        fi

        # Launch new tasks while slots are available
        while (( _batch_running < MAX_PARALLEL && _batch_next_idx < ${#_batch_tasks[@]} )); do
            local manifest_idx=$(( _batch_next_idx + 1 ))
            local status
            status=$(_batch_get_task_status "$manifest_idx")

            # Skip completed or already-failed tasks
            if [[ "$status" == "completed" || "$status" == "failed" ]]; then
                (( _batch_next_idx++ )) || true
                continue
            fi

            # Ensure worktree exists (resume case — fresh runs already created them)
            local slug="${_batch_slugs[$_batch_next_idx]}"
            local target_dir="${_batch_target_dirs[$_batch_next_idx]:-}"
            local wt_check_path
            wt_check_path=$(_batch_worktree_path "$slug" "$target_dir")
            if [[ ! -d "$wt_check_path" ]]; then
                if ! _batch_create_worktree "$slug" "$base_branch" "$target_dir"; then
                    _batch_mark_task "$manifest_idx" "failed" "1"
                    _batch_failed=$(( _batch_failed + 1 ))
                    (( _batch_next_idx++ )) || true
                    continue
                fi
            fi

            _batch_launch_task "$_batch_next_idx"
            (( _batch_next_idx++ )) || true
        done

        _batch_refresh_dashboard
        sleep 3
    done

    if [[ "$_batch_quit" == "true" ]]; then
        local _batch_skipped=$(( total - _batch_completed - _batch_failed ))
        if (( _batch_skipped > 0 )); then
            print_info "$_batch_skipped task(s) pending. Resume with: buildcrew run --batch --resume"
        fi
        return 0
    fi

    if [[ "$_batch_stopping" == "true" ]]; then
        local _batch_skipped=$(( ${#_batch_tasks[@]} - _batch_completed - _batch_failed ))
        if (( _batch_skipped > 0 )); then
            print_info "$_batch_skipped task(s) were not started. Resume with: buildcrew run --batch --resume"
        fi
    fi

    _batch_post_completion "$base_branch"
}

# ── Resume support ────────────────────────────────────────────────────────────

_batch_resume() {
    # Force auto mode
    AUTO_MODE=true

    # Capture CWD once for consistent path resolution
    __BATCH_CWD="$(pwd)"

    # Load tasks from manifest
    _batch_tasks=()
    _batch_slugs=()
    _batch_target_dirs=()
    _batch_plan_refs=()
    local count base_branch
    count=$(jq '.tasks | length' "$BATCH_MANIFEST")
    base_branch=$(jq -r '.base_branch' "$BATCH_MANIFEST")

    # Load all task fields in a single jq call (avoids 4N process spawns)
    local i=0
    while IFS=$'\t' read -r t_text t_slug t_td t_pr; do
        _batch_tasks[$i]="$t_text"
        _batch_slugs[$i]="$t_slug"
        _batch_target_dirs[$i]="$t_td"
        _batch_plan_refs[$i]="$t_pr"
        (( i++ )) || true
    done < <(jq -r '.tasks[] | [.text, .slug, (.target_dir // ""), (.plan_ref // "")] | @tsv' "$BATCH_MANIFEST")

    local total=${#_batch_tasks[@]}
    local already_done
    already_done=$(jq '[.tasks[] | select(.status == "completed")] | length' "$BATCH_MANIFEST")

    # Reconcile: mark previously-completed tasks in BACKLOG.md (idempotent — only matches - [ ] lines)
    if (( already_done > 0 )); then
        local _saved_bf="$BACKLOG_FILE"
        [[ "$BACKLOG_FILE" != /* ]] && BACKLOG_FILE="$__BATCH_CWD/$BACKLOG_FILE"
        local reconcile_text
        while IFS= read -r reconcile_text; do
            [[ -n "$reconcile_text" ]] && mark_task_complete "$reconcile_text"
        done < <(jq -r '.tasks[] | select(.status == "completed") | .text' "$BATCH_MANIFEST")
        BACKLOG_FILE="$_saved_bf"
    fi

    # Pool state
    _batch_pids=()
    _batch_running=0
    _batch_completed=$already_done
    _batch_failed=0
    _batch_rate_limited=0
    _batch_next_idx=0
    _batch_start_time=$(date +%s)
    _batch_dashboard_lines=0

    i=0
    while (( i < total )); do
        _batch_pids[$i]=""
        (( i++ )) || true
    done

    trap '_batch_parallel_cleanup' EXIT INT TERM
    _batch_start_heartbeat

    print_header "Batch Mode - Resuming"
    print_info "Tasks: $total  |  Already completed: $already_done  |  Max parallel: $MAX_PARALLEL"
    echo ""

    clear_stop_signal
    _batch_dispatch_loop "$base_branch"
}

# ── Main batch entry point ────────────────────────────────────────────────────

enter_batch_mode() {
    local task_list="$1"

    # Capture CWD once for consistent path resolution
    __BATCH_CWD="$(pwd)"

    # Force auto mode for background processes
    if [[ "$AUTO_MODE" != "true" ]]; then
        print_warning "Batch mode requires auto mode (background processes cannot be interactive) -- overriding config"
        AUTO_MODE=true
    fi

    # Determine base branch and commit (conditional on git availability)
    local base_branch base_commit
    if [[ "$__BATCH_PARENT_IS_GIT" == "true" ]]; then
        base_branch=$(git rev-parse --abbrev-ref HEAD)
        base_commit=$(git rev-parse HEAD)
    else
        base_branch="none"
        base_commit="none"
    fi

    # Parse task list into arrays
    _batch_parse_task_list "$task_list"
    local total=${#_batch_tasks[@]}
    if [[ $total -eq 0 ]]; then
        print_error "No tasks to process"
        exit 1
    fi

    # Validate target directories when parent is not a git repo
    if [[ "$__BATCH_PARENT_IS_GIT" == "false" ]]; then
        local validation_errors=()
        local i=0
        while (( i < total )); do
            local td="${_batch_target_dirs[$i]:-}"
            local task_text="${_batch_tasks[$i]}"
            if [[ -z "$td" ]]; then
                validation_errors+=("Task $((i+1)) '$task_text': no target directory (add [dir:...] prefix or set TARGET_DIR in .buildcrew/config)")
            elif [[ ! -d "$td" ]]; then
                validation_errors+=("Task $((i+1)) '$task_text': target directory '$td' does not exist")
            elif ! git -C "$td" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
                validation_errors+=("Task $((i+1)) '$task_text': target directory '$td' is not a git repository")
            elif [[ -n "$(git -C "$td" status --porcelain 2>/dev/null)" ]]; then
                validation_errors+=("Task $((i+1)) '$task_text': target repo '$td' has uncommitted changes")
            fi
            (( i++ )) || true
        done
        if [[ ${#validation_errors[@]} -gt 0 ]]; then
            print_error "Target directory validation failed:"
            local err
            for err in "${validation_errors[@]}"; do
                echo "  - $err" >&2
            done
            exit 1
        fi
    fi

    # Initialize manifest
    _batch_init_manifest "$base_branch" "$base_commit"
    local i=0
    while (( i < total )); do
        _batch_add_task $((i + 1)) "${_batch_tasks[$i]}" "${_batch_slugs[$i]}" "${_batch_target_dirs[$i]:-}" "${_batch_plan_refs[$i]:-}"
        (( i++ )) || true
    done

    # Create all worktrees upfront
    print_info "Creating $total worktrees..."
    i=0
    while (( i < total )); do
        if ! _batch_create_worktree "${_batch_slugs[$i]}" "$base_branch" "${_batch_target_dirs[$i]:-}"; then
            print_warning "Failed to create worktree for task $((i + 1)): ${_batch_tasks[$i]}"
            _batch_mark_task $((i + 1)) "failed" "1"
            _batch_failed=$(( _batch_failed + 1 ))
        fi
        (( i++ )) || true
    done

    # Pool state
    _batch_pids=()
    _batch_running=0
    _batch_rate_limited=0
    _batch_next_idx=0
    _batch_start_time=$(date +%s)
    _batch_dashboard_lines=0

    i=0
    while (( i < total )); do
        _batch_pids[$i]=""
        (( i++ )) || true
    done

    # Setup
    __WF_TASK_NUM=0
    __WF_TOTAL_TASKS=$total
    __WF_TASK_NAME="Batch mode"
    update_workflow_state "batch" "running"
    trap '_batch_parallel_cleanup' EXIT INT TERM
    _batch_start_heartbeat

    print_header "Batch Mode - Parallel Execution"
    print_info "Tasks: $total  |  Max parallel: $MAX_PARALLEL  |  Base: $base_branch"
    echo ""

    clear_stop_signal
    _batch_dispatch_loop "$base_branch"
}

# Pause for human review when --review is set
# NOTE: This function has no callers in the current orchestration flow (removed in
# the "consolidate review gates" change). Kept for test compatibility and as a
# general-purpose utility — candidate for removal in a future cleanup task.
# Returns: 0 = continue, 1 = skip task, 2 = quit pipeline
handle_human_review() {
    local task="$1"
    local description="$2"
    local artifact="$3"
    local force="${4:-}"

    [[ "$HUMAN_REVIEW" == "true" || "$force" == "--force" ]] || return 0

    if [[ "$AUTO_MODE" == "true" ]]; then
        print_info "Auto mode: auto-approving human review"
        return 0
    fi

    # Fall back to autonomous if not interactive
    if [[ ! -t 0 ]]; then
        print_warning "Non-interactive terminal — skipping human review pause"
        return 0
    fi

    print_human_review_banner
    echo -e "${CYAN}  $description${NC}"
    echo -e "${CYAN}  Review: $artifact${NC}"
    echo -e "${CYAN}  (Edit the file in your editor if needed before continuing)${NC}"
    echo ""
    echo -e "  ${BOLD}[Enter]${NC} Continue  |  ${BOLD}[s]${NC} Skip task  |  ${BOLD}[q]${NC} Quit pipeline"
    echo ""
    read -r review_response
    case "$review_response" in
        s|S) return 1 ;;
        q|Q) return 2 ;;
        *) return 0 ;;
    esac
}

# Extract and display acceptance criteria lines from .claude/spec.md.
# Used by handle_spec_review for both initial display and post-edit refresh.
_display_spec_acs() {
    local ac_lines
    ac_lines=$(grep '^- \[ \] AC-' ".claude/spec.md" 2>/dev/null) || ac_lines=""
    if [[ -n "$ac_lines" ]]; then
        echo ""
        while IFS= read -r line; do
            echo -e "  ${CYAN}${line}${NC}"
        done <<< "$ac_lines"
    else
        echo ""
        echo -e "  ${YELLOW}No acceptance criteria found. Press [e] to edit the spec.${NC}"
    fi
    echo ""
}

# Display the current implementation plan (.claude/current-plan.md) inline,
# truncated to max_lines. Used by handle_plan_review().
_display_plan() {
    local plan_file=".claude/current-plan.md"
    local max_lines=60
    if [[ ! -f "$plan_file" ]]; then
        echo ""
        echo -e "  ${YELLOW}No plan file found at $plan_file${NC}"
        echo ""
        return
    fi
    local total_lines
    total_lines=$(wc -l < "$plan_file" | tr -d ' ')
    echo ""
    if (( total_lines <= max_lines )); then
        while IFS= read -r line; do
            echo -e "  ${CYAN}${line}${NC}"
        done < "$plan_file"
    else
        local shown=0
        while IFS= read -r line && (( shown < max_lines )); do
            echo -e "  ${CYAN}${line}${NC}"
            ((shown++))
        done < "$plan_file"
        echo ""
        echo -e "  ${YELLOW}... ($((total_lines - max_lines)) more lines -- press [e] to view full plan in editor)${NC}"
    fi
    echo ""
}

# Pre-build plan review — shows the plan inline and allows editing.
# Fires when --review is set, or when force="--force" (AI-recommended review).
# Returns: 0 = approved, 1 = skip task, 2 = quit pipeline
handle_plan_review() {
    local task="$1"
    local description="$2"
    local force="${3:-}"

    [[ "$HUMAN_REVIEW" == "true" || "$force" == "--force" ]] || return 0

    if [[ "$AUTO_MODE" == "true" ]]; then
        print_info "Auto mode: auto-approving plan review"
        return 0
    fi

    if [[ ! -t 0 ]]; then
        print_warning "Non-interactive terminal — skipping plan review pause"
        return 0
    fi

    print_human_review_banner
    echo -e "${CYAN}  $description${NC}"
    _display_plan
    echo -e "  ${BOLD}[Enter]${NC} Approve  |  ${BOLD}[e]${NC} Edit plan  |  ${BOLD}[s]${NC} Skip task  |  ${BOLD}[q]${NC} Quit"
    echo ""

    update_workflow_state "review" "awaiting_input"
    print_info "Awaiting user input: plan review"
    while true; do
        read -r plan_response
        case "$plan_response" in
            e|E)
                ${EDITOR:-vi} ".claude/current-plan.md"
                echo ""
                echo -e "${CYAN}  Plan updated.${NC}"
                _display_plan
                echo -e "  ${BOLD}[Enter]${NC} Approve  |  ${BOLD}[e]${NC} Edit again  |  ${BOLD}[s]${NC} Skip  |  ${BOLD}[q]${NC} Quit"
                echo ""
                ;;
            s|S) return 1 ;;
            q|Q) return 2 ;;
            *) return 0 ;;
        esac
    done
}

# __is_interactive — checks if stdin is a terminal (extracted for testability)
__is_interactive() { [[ -t 0 ]]; }

# handle_spec_interview task
# Presents needs_probing questions to user, re-invokes spec with answers.
# Returns: 0 = interview complete or skipped, 1 = re-invocation failed
handle_spec_interview() {
    local task="$1"

    # Extract questions BEFORE re-invocation (run_phase_group destroys PHASE_RESULT_FILE)
    local questions=()
    while IFS= read -r q; do
        [[ -n "$q" ]] && questions+=("$q")
    done < <(jq -r '.questions // [] | .[]' "$PHASE_RESULT_FILE" 2>/dev/null)

    # Empty questions guard
    if (( ${#questions[@]} == 0 )); then
        print_debug "needs_probing verdict but no questions — treating as complete"
        return 0
    fi

    # Auto mode guard
    if [[ "$AUTO_MODE" == "true" ]]; then
        print_info "Auto mode: skipping spec interview, proceeding with best-effort spec"
        return 0
    fi

    # Non-interactive guard
    if ! __is_interactive; then
        print_warning "Non-interactive terminal — skipping spec interview"
        return 0
    fi

    # Present interview
    echo -e "\n${YELLOW}${BOLD}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}${BOLD}│   SPEC INTERVIEW                                            │${NC}"
    echo -e "${YELLOW}│   The spec phase has questions before finalizing.            │${NC}"
    echo -e "${YELLOW}${BOLD}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    local answers=()
    local i
    update_workflow_state "spec" "awaiting_input"
    for (( i=0; i<${#questions[@]}; i++ )); do
        echo -e "  ${CYAN}$((i+1)). ${questions[$i]}${NC}"
        local ans=""
        read -r -p "  > (Enter to skip) " ans
        answers+=("$ans")
        echo ""
    done

    # Build answer context
    print_info "Re-running spec with your answers..."
    local answer_context="[BUILDCREW_INTERVIEW_ANSWERS]"
    for (( i=0; i<${#questions[@]}; i++ )); do
        answer_context+=$'\n'"Q$((i+1)): ${questions[$i]}"
        answer_context+=$'\n'"A$((i+1)): ${answers[$i]:-}"
    done

    # Re-invoke spec with answers (preserving replan context if set)
    local spec_extra="${__replan_context:+Re-planning context: $__replan_context | }$answer_context"
    run_phase_group "spec" "$task" "$spec_extra" || return 1

    # Check second-pass verdict
    local new_verdict
    new_verdict=$(jq -r '.verdict // "complete"' "$PHASE_RESULT_FILE")
    if [[ "$new_verdict" == "vague" ]]; then
        print_warning "Second-pass spec flagged as too vague: $(jq -r '.details // "unknown"' "$PHASE_RESULT_FILE")"
        return 1
    elif [[ "$new_verdict" == "needs_probing" ]]; then
        print_warning "Interview re-run produced needs_probing again — proceeding with best-effort spec"
    fi

    return 0
}

# Mandatory spec review — guides the human to evaluate the spec before proceeding.
# Distinct from handle_human_review(): always fires (not gated on --review), and
# provides spec-specific framing rather than a generic "approve/skip" prompt.
# Returns: 0 = approved, 1 = skip task, 2 = quit pipeline
handle_spec_review() {
    local task="$1"
    local ac_count="$2"
    local task_num="${3:-}"
    local total_tasks="${4:-}"

    if [[ "$AUTO_MODE" == "true" ]]; then
        print_info "Auto mode: auto-approving spec review"
        return 0
    fi

    # Non-interactive terminals fall through autonomously (same as handle_human_review)
    if [[ ! -t 0 ]]; then
        print_warning "Non-interactive terminal — skipping spec review pause"
        return 0
    fi

    echo -e "\n${YELLOW}${BOLD}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}${BOLD}│   ACCEPTANCE CRITERIA                                       │${NC}"
    echo -e "${YELLOW}│   Review what 'done' means for this task before building.    │${NC}"
    echo -e "${YELLOW}${BOLD}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    if [[ -n "$task_num" && -n "$total_tasks" ]]; then
        echo -e "${CYAN}  Task $task_num of $total_tasks:  $task${NC}"
    else
        echo -e "${CYAN}  Task:  $task${NC}"
    fi
    _display_spec_acs
    echo -e "  ${BOLD}[Enter]${NC} Approve  |  ${BOLD}[e]${NC} Edit spec  |  ${BOLD}[s]${NC} Skip task  |  ${BOLD}[q]${NC} Quit"
    echo ""

    update_workflow_state "spec" "awaiting_input"
    print_info "Awaiting user input: spec review"
    while true; do
        read -r spec_response
        case "$spec_response" in
            e|E)
                ${EDITOR:-vi} ".claude/spec.md"
                ac_count=$(grep -c '^- \[ \] AC-' ".claude/spec.md" 2>/dev/null) || ac_count=0
                echo ""
                echo -e "${CYAN}  Spec updated. ($ac_count acceptance criteria)${NC}"
                _display_spec_acs
                echo -e "  ${BOLD}[Enter]${NC} Approve  |  ${BOLD}[e]${NC} Edit again  |  ${BOLD}[s]${NC} Skip  |  ${BOLD}[q]${NC} Quit"
                echo ""
                ;;
            s|S) return 1 ;;
            q|Q) return 2 ;;
            *) return 0 ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────────
# Git branching helpers (used with --branch)
# ─────────────────────────────────────────────────────────────────────────────────

save_original_branch() {
    ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ -z "$ORIGINAL_BRANCH" ]]; then
        print_error "Could not determine current git branch"
        return 1
    fi
}

ensure_clean_worktree() {
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        print_error "Working tree is not clean. Commit or stash changes before using --branch."
        return 1
    fi
}

task_to_slug() {
    local task="$1"
    local slug
    # Lowercase, replace non-alphanumeric with hyphens, collapse multiple hyphens, trim
    slug=$(echo "$task" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
    # Truncate to 60 chars
    slug="${slug:0:60}"
    echo "$slug"
}

# Extract value from a [key:value] annotation at the start of a task string.
# Returns the value or empty string.
_extract_task_annotation() {
    local key="$1" task="$2"
    if [[ "$task" =~ ^\[${key}:([^\]]+)\] ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# Strip a [key:value] annotation (and trailing space) from the start of a task string.
_strip_task_annotation() {
    local key="$1" task="$2"
    echo "$task" | sed "s/^\\[${key}:[^]]*\\] *//"
}

extract_task_dir()      { _extract_task_annotation "dir"  "$1"; }
strip_task_dir()        { _strip_task_annotation   "dir"  "$1"; }
extract_task_plan_ref() {
    local ref
    ref=$(_extract_task_annotation "plan" "$1")
    # Expand leading ~ to $HOME (tilde not expanded inside double quotes)
    [[ -n "$ref" ]] && ref="${ref/#\~/$HOME}"
    echo "$ref"
}
strip_task_plan_ref()   { _strip_task_annotation   "plan" "$1"; }

# Resolve the target directory for a task: inline [dir:...] > TARGET_DIR config > empty.
resolve_task_target_dir() {
    local task="$1"
    local dir
    dir=$(extract_task_dir "$task")
    if [[ -n "$dir" ]]; then
        echo "$dir"
        return
    fi
    echo "${TARGET_DIR:-}"
}

task_to_branch_name() {
    local task="$1"
    echo "buildcrew/$(task_to_slug "$task")"
}

create_task_branch() {
    local task="$1"
    local branch_name
    branch_name=$(task_to_branch_name "$task")

    if ! ensure_clean_worktree; then
        return 1
    fi

    # Delete existing branch from a previous failed run
    if git rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        print_warning "Branch $branch_name exists from a previous run, recreating from $ORIGINAL_BRANCH"
        git branch -D "$branch_name" 2>/dev/null || true
    fi

    if ! git checkout -b "$branch_name" 2>/dev/null; then
        print_error "Failed to create branch: $branch_name"
        return 1
    fi

    print_success "Created branch: $branch_name"
}

create_task_pr() {
    local task="$1"
    local branch_name
    branch_name=$(task_to_branch_name "$task")

    [[ "$HAS_REMOTE" == "true" ]] || return 0

    local pr_body_file
    pr_body_file=$(mktemp)

    # Build PR body safely in a temp file
    {
        echo "## Task"
        echo "$task"
        echo ""
        echo "## Plan Summary"
        head -20 .claude/current-plan.md 2>/dev/null || echo "No plan available"
        echo ""
        echo "## Verification"
        head -15 .claude/verify-report.md 2>/dev/null || echo "No verification report"
        echo ""
        echo "---"
        echo "*Generated by [BuildCrew](https://github.com/joshuaccarroll/buildcrew)*"
    } > "$pr_body_file"

    # Push branch
    if ! git push -u origin "$branch_name" 2>/dev/null; then
        print_warning "Failed to push branch. Create PR manually."
        rm -f "$pr_body_file"
        return 0
    fi

    if [[ "$GH_AVAILABLE" == "true" ]]; then
        gh pr create --title "$(echo "$task" | cut -c1-70)" \
            --body-file "$pr_body_file" \
            --base "$ORIGINAL_BRANCH" 2>/dev/null || {
            print_warning "PR creation failed. Branch pushed; create PR manually."
        }
    else
        print_info "Branch pushed. Create PR manually (gh CLI not available)."
    fi
    rm -f "$pr_body_file"
}

return_to_original_branch() {
    if [[ -n "$ORIGINAL_BRANCH" ]]; then
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            git stash --include-untracked -m "buildcrew: WIP from incomplete task" 2>/dev/null || true
        fi
        git checkout "$ORIGINAL_BRANCH" 2>/dev/null || true
    fi
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

    # Fresh backlog - launch discovery mode to define the project
    if is_fresh_backlog; then
        print_info "Empty backlog. Launching discovery mode..."
        echo ""
        enter_discovery_mode "Run /build to help define this project and create a backlog."
    fi

    # Completed phase - existing project, no pending tasks
    if is_completed_phase; then
        print_info "All tasks complete! Launching discovery mode to add scope..."
        echo ""
        enter_discovery_mode "Run /build to add new tasks to this project."
    fi
}

# Get the next uncompleted task from the backlog
get_next_task() {
    grep -m1 '^\- \[ \]' "$BACKLOG_FILE" 2>/dev/null | sed 's/^- \[ \] //' || echo ""
}

# Collect all pending tasks into __BATCH_TASK_LIST (global) and set __BATCH_TASK_COUNT.
# Must NOT be called via command substitution — subshell would lose both globals.
gather_pending_tasks() {
    __BATCH_TASK_LIST=$(grep '^\- \[ \]' "$BACKLOG_FILE" 2>/dev/null \
        | sed 's/^- \[ \] //' \
        | sed -E 's/[[:space:]]*\{(trivial|simple|standard)\}[[:space:]]*$//' \
        | awk '{printf "%2d. %s\n", NR, $0}') || __BATCH_TASK_LIST=""
    __BATCH_TASK_COUNT=$(echo "$__BATCH_TASK_LIST" | awk 'NF {n++} END {print n+0}')
}

# Get a specific task by name or number
# If target is a number, returns the Nth pending task (1-indexed)
# If target is a string, returns the first pending task containing that string (case-insensitive)
get_task_by_target() {
    local target="$1"

    if [[ "$target" =~ ^[0-9]+$ ]]; then
        # Numeric: get the Nth pending task
        grep '^\- \[ \]' "$BACKLOG_FILE" 2>/dev/null | sed -n "${target}p" | sed 's/^- \[ \] //' || echo ""
    else
        # String: find first pending task matching (case-insensitive)
        grep -i '^\- \[ \].*'"$target" "$BACKLOG_FILE" 2>/dev/null | head -1 | sed 's/^- \[ \] //' || echo ""
    fi
}

# Extract complexity tag from the END of a task string.
# Matches {trivial}, {simple}, {standard} only at end of string (ignores mid-string occurrences).
# Returns tag name or empty string.
get_task_tag() {
    local task="$1"
    echo "$task" | sed -nE 's/.*\{(trivial|simple|standard)\}[[:space:]]*$/\1/p'
}

# Strip complexity tag suffix and trailing whitespace from task text.
strip_task_tag() {
    local task="$1"
    echo "$task" | sed -E 's/[[:space:]]*\{(trivial|simple|standard)\}[[:space:]]*$//'
}

# Assess task complexity: returns "trivial", "simple", or "standard".
# 1. Explicit tag wins (via get_task_tag)
# 2. Fall back to keyword heuristic
assess_task_complexity() {
    local task="$1"
    local tag
    tag=$(get_task_tag "$task")
    if [[ -n "$tag" ]]; then
        echo "$tag"
        return
    fi

    local task_lower
    task_lower=$(echo "$task" | tr '[:upper:]' '[:lower:]')
    local task_len=${#task}

    # Complexity indicators force standard classification
    local complexity_indicators="system|architect|database|schema|auth|integrat|migrat|redesign|refactor|test|api"
    if echo "$task_lower" | grep -qE "$complexity_indicators"; then
        echo "standard"
        return
    fi

    # Trivial: short task with trivial verb
    if (( task_len < 80 )); then
        if echo "$task_lower" | grep -qE '^(create|chmod|fix typo|rename|delete|bump version|set permission|move|copy) '; then
            echo "trivial"
            return
        fi
    fi

    # Simple: medium task with simple verb
    if (( task_len < 120 )); then
        if echo "$task_lower" | grep -qE '^(config|update|change|fix bug|refactor|add .* to|install|enable|disable) '; then
            echo "simple"
            return
        fi
    fi

    echo "standard"
}

# Mark a task as completed in the backlog
# Tolerates optional [plan:...] and [dir:...] prefixes in the BACKLOG line, preserving them in output.
# Line format: - [ ] [plan:X]? [dir:Y]? <task text> {trivial|simple|standard}?
mark_task_complete() {
    local task="$1"
    TASK="$task" perl -i -pe 's/^- \[ \] (\[plan:[^\]]+\] )?(\[dir:[^\]]+\] )?\Q$ENV{TASK}\E(\s*\{(?:trivial|simple|standard)\})?$/- [x] ${1}${2}$ENV{TASK}/' "$BACKLOG_FILE"
}

# Mark a task as blocked in the backlog
# Tolerates optional [plan:...] and [dir:...] prefixes in the BACKLOG line, preserving them in output.
# Line format: - [ ] [plan:X]? [dir:Y]? <task text> ...
mark_task_blocked() {
    local task="$1"
    local reason="$2"
    TASK="$task" REASON="$reason" perl -i -pe 's/^- \[ \] (\[plan:[^\]]+\] )?(\[dir:[^\]]+\] )?\Q$ENV{TASK}\E.*/- [!] ${1}${2}$ENV{TASK} (blocked: $ENV{REASON})/' "$BACKLOG_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Task progress tracking (for --resume)
# ─────────────────────────────────────────────────────────────────────────────────

PROGRESS_FILE=".buildcrew/task-progress.json"
STEP_PROGRESS_FILE=".buildcrew/.step-progress"

# Save progress after a phase group completes successfully.
# Usage: save_task_progress "task text" "research review" 4
save_task_progress() {
    local task="$1"
    local phases="$2"
    local invocations="$3"
    mkdir -p .buildcrew

    # Convert space-separated phases to JSON array (single jq call, no shell loop)
    local phases_json="[]"
    if [[ -n "$phases" ]]; then
        phases_json=$(printf '%s\n' $phases | jq -R -s 'split("\n") | map(select(length > 0))')
    fi

    jq -n \
        --arg task "$task" \
        --argjson phases "$phases_json" \
        --argjson invocations "$invocations" \
        --arg timestamp "$(date '+%Y-%m-%dT%H:%M:%S')" \
        '{task: $task, completed_phases: $phases, invocation_count: $invocations, timestamp: $timestamp}' \
        > "$PROGRESS_FILE"
}

# Load progress for resume. Sets __RESUME_TASK, __RESUME_PHASES, __RESUME_INVOCATIONS.
# Returns 0 if valid progress found (task still pending), 1 otherwise.
load_task_progress() {
    __RESUME_TASK=""
    __RESUME_PHASES=""
    __RESUME_INVOCATIONS=0

    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi

    if ! jq -e . "$PROGRESS_FILE" >/dev/null 2>&1; then
        print_warning "Invalid progress file — ignoring"
        return 1
    fi

    local saved_task
    saved_task=$(jq -r '.task // ""' "$PROGRESS_FILE")
    if [[ -z "$saved_task" ]]; then
        return 1
    fi

    # Validate saved task is still pending in backlog
    # Line format: - [ ] [plan:X]? [dir:Y]? <task text> {trivial|simple|standard}?
    if ! TASK="$saved_task" perl -ne 'if (/^- \[ \] (\[plan:[^\]]+\] )?(\[dir:[^\]]+\] )?\Q$ENV{TASK}\E(\s*\{(?:trivial|simple|standard)\})?$/) { $f=1; last } END { exit($f ? 0 : 1) }' "$BACKLOG_FILE"; then
        print_warning "Saved task no longer pending in backlog — clearing progress"
        clear_task_progress
        return 1
    fi

    __RESUME_TASK="$saved_task"
    __RESUME_PHASES=$(jq -r '.completed_phases // [] | join(" ")' "$PROGRESS_FILE")
    __RESUME_INVOCATIONS=$(jq -r '.invocation_count // 0' "$PROGRESS_FILE")

    local saved_ts
    saved_ts=$(jq -r '.timestamp // ""' "$PROGRESS_FILE")
    if [[ -n "$saved_ts" ]]; then
        print_info "Resuming task from $saved_ts"
        print_info "Completed phases: ${__RESUME_PHASES:-none}"
    fi

    return 0
}

# Clear progress file (on completion or fresh start).
clear_task_progress() {
    rm -f "$PROGRESS_FILE"
    clear_step_progress
}

# ─────────────────────────────────────────────────────────────────────────────────
# Plan step progress tracking (for chunked build)
# ─────────────────────────────────────────────────────────────────────────────────

# Parse ### Step N: headers from .claude/current-plan.md into STEP_PROGRESS_FILE.
# Echoes step count to stdout. Returns 1 if no parseable steps found.
parse_plan_steps() {
    local plan_file=".claude/current-plan.md"
    if [[ ! -f "$plan_file" ]]; then
        return 1
    fi

    rm -f "$STEP_PROGRESS_FILE"
    grep '^### Step [0-9]' "$plan_file" | while IFS= read -r line; do
        step_num=$(echo "$line" | sed 's/^### Step \([0-9][0-9]*\).*/\1/')
        step_name=$(echo "$line" | sed 's/^### Step [0-9][0-9]*: *//')
        echo "${step_num}|pending|${step_name}" >> "$STEP_PROGRESS_FILE"
    done

    if [[ ! -f "$STEP_PROGRESS_FILE" ]]; then
        return 1
    fi

    local count
    count=$(wc -l < "$STEP_PROGRESS_FILE" | tr -d ' ')
    if [[ "$count" -eq 0 ]]; then
        rm -f "$STEP_PROGRESS_FILE"
        return 1
    fi
    echo "$count"
}

# Echoes the next pending step number to stdout. Returns 1 if none remaining.
get_next_pending_step() {
    if [[ ! -f "$STEP_PROGRESS_FILE" ]]; then
        return 1
    fi
    local num
    while IFS='|' read -r num status name; do
        if [[ "$status" == "pending" ]]; then
            echo "$num"
            return 0
        fi
    done < "$STEP_PROGRESS_FILE"
    return 1
}

# Mark a step as complete. Args: $1=step_num
mark_step_complete() {
    local step_num="$1"
    if [[ ! -f "$STEP_PROGRESS_FILE" ]]; then
        return
    fi
    local tmp
    tmp="${STEP_PROGRESS_FILE}.tmp.$$"
    while IFS='|' read -r num status name; do
        if [[ "$num" == "$step_num" ]]; then
            echo "${num}|complete|${name}"
        else
            echo "${num}|${status}|${name}"
        fi
    done < "$STEP_PROGRESS_FILE" > "$tmp"
    mv "$tmp" "$STEP_PROGRESS_FILE"
}

# Echoes the step name for a given step number. Args: $1=step_num
get_step_name() {
    local step_num="$1"
    if [[ ! -f "$STEP_PROGRESS_FILE" ]]; then
        return 1
    fi
    local num status name
    while IFS='|' read -r num status name; do
        if [[ "$num" == "$step_num" ]]; then
            echo "$name"
            return 0
        fi
    done < "$STEP_PROGRESS_FILE"
    return 1
}

# Remove the step progress file.
clear_step_progress() {
    rm -f "$STEP_PROGRESS_FILE"
}

WORKFLOW_STATE_FILE=".buildcrew/.workflow-state"
__WF_TASK_NUM=""
__WF_TOTAL_TASKS=""
__WF_TASK_NAME=""

# Write current workflow state atomically to the state file.
update_workflow_state() {
    local phase="$1"
    local status="$2"
    local model="${3:-}"
    local tmp
    tmp="${WORKFLOW_STATE_FILE}.tmp.$$"
    mkdir -p .buildcrew .claude
    {
        echo "TASK_NUM=${__WF_TASK_NUM:-}"
        echo "TOTAL_TASKS=${__WF_TOTAL_TASKS:-}"
        echo "TASK_NAME=${__WF_TASK_NAME:-}"
        echo "PHASE=$phase"
        echo "PHASE_STATUS=$status"
        echo "INVOCATION_COUNT=$__INVOCATION_COUNT"
        echo "MAX_INVOCATIONS=$MAX_INVOCATIONS"
        echo "TIMESTAMP=$(date +%s)"
        echo "MODEL=$model"
    } > "$tmp"
    mv -f "$tmp" "$WORKFLOW_STATE_FILE"
    # Also write a JSON snapshot for dashboard and tooling consumers
    local ts
    ts=$(date +%s)
    printf '{"phase":"%s","status":"%s","task_num":%s,"total_tasks":%s,"timestamp":%s}\n' \
        "$phase" "$status" "${__WF_TASK_NUM:-0}" "${__WF_TOTAL_TASKS:-0}" "$ts" \
        > ".claude/workflow-status.json"
    # Track completed phases in-session so phase_completed works within a run
    if [[ "$status" == "complete" || "$status" == "skipped" ]]; then
        local already=false
        local p
        for p in $__RESUME_PHASES; do
            [[ "$p" == "$phase" ]] && already=true && break
        done
        [[ "$already" == "false" ]] && __RESUME_PHASES="${__RESUME_PHASES:+$__RESUME_PHASES }$phase"
    fi
}

# Remove workflow state file and any orphaned temp files.
clear_workflow_state() {
    rm -f "$WORKFLOW_STATE_FILE" "${WORKFLOW_STATE_FILE}.tmp."* 2>/dev/null || true
}

# Check if a phase was already completed in a previous run.
# Usage: if phase_completed "research"; then skip; fi
phase_completed() {
    local phase="$1"
    local p
    for p in $__RESUME_PHASES; do
        if [[ "$p" == "$phase" ]]; then
            return 0
        fi
    done
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────────
# Artifact archival (save debugging artifacts from blocked tasks)
# ─────────────────────────────────────────────────────────────────────────────────

CURRENT_TASK_FILE=".buildcrew/.current-task"
LESSONS_FILE=".buildcrew/lessons.md"
ARTIFACT_FILES=(
    .claude/spec.md .claude/research.md .claude/current-plan.md .claude/plan-review.md
    .claude/review-lens1.md .claude/review-lens2.md .claude/review-lens3.md
    .claude/plan-review-prev.md .claude/review-lens1-prev.md .claude/review-lens2-prev.md .claude/review-lens3-prev.md
    .claude/code-review.md .claude/outcome-report.md
    .claude/security-audit.md .claude/verify-report.md
    .claude/tdd-manifest.json
)

# Archive any existing .claude/ artifacts before cleanup.
# Reads .buildcrew/.current-task to determine which task produced them.
archive_task_artifacts() {
    # Check if any artifacts exist
    local has_artifacts=false
    local f
    for f in "${ARTIFACT_FILES[@]}" "$PHASE_RESULT_FILE" "$STATUS_FILE"; do
        if [[ -f "$f" ]]; then
            has_artifacts=true
            break
        fi
    done
    [[ "$has_artifacts" == "true" ]] || return 0

    # Determine task slug from saved state
    local slug="unknown"
    if [[ -f "$CURRENT_TASK_FILE" ]]; then
        local prev_task
        prev_task=$(cat "$CURRENT_TASK_FILE")
        if [[ -n "$prev_task" ]]; then
            slug=$(task_to_slug "$prev_task")
        fi
    fi

    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')
    local archive_dir=".buildcrew/history/$slug/$timestamp"
    mkdir -p "$archive_dir"

    for f in "${ARTIFACT_FILES[@]}" "$PHASE_RESULT_FILE" "$STATUS_FILE"; do
        if [[ -f "$f" ]]; then
            cp "$f" "$archive_dir/"
        fi
    done

    # Archive TDD test files if present
    if [[ -f ".claude/tdd-manifest.json" ]]; then
        local _tdd_f
        for _tdd_f in $(jq -r '.test_files[]? // empty' ".claude/tdd-manifest.json" 2>/dev/null); do
            [[ -f "$_tdd_f" ]] && cp "$_tdd_f" "$archive_dir/"
        done
    fi

    print_info "Archived artifacts to $archive_dir"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Lessons system (Change 2: Self-Improvement Loop)
# ─────────────────────────────────────────────────────────────────────────────────

_lesson_writing_instruction() {
    cat << 'EOF'
LESSON REQUIRED: After completing your fix, append a lesson to .buildcrew/lessons.md.
Write it BEFORE writing phase-result.json (which triggers process termination).
Use this exact format:

---

## Lesson: [date]

**Phase**: [the current phase, e.g. build, verify]
**What went wrong**: [specific description of what failed]
**What fixed it**: [specific description of what you changed]
**Rule**: [one-sentence rule to prevent this in future]
**Applies to**: [phase] persona

---
EOF
}

LESSONS_MAX_ENTRIES=25
LESSONS_SUMMARIZE_COUNT=10

# Append a structured lesson to .buildcrew/lessons.md after a failure.
# Usage: append_lesson "phase" "what_went_wrong" "what_fixed_it" "rule"
append_lesson() {
    local phase="$1"
    local what_went_wrong="$2"
    local what_fixed_it="$3"
    local rule="$4"

    mkdir -p .buildcrew

    # Count existing lesson entries (lines starting with "## Lesson")
    local entry_count=0
    if [[ -f "$LESSONS_FILE" ]]; then
        entry_count=$(grep -c '^## Lesson' "$LESSONS_FILE" 2>/dev/null) || entry_count=0

        # Deduplication: skip if this exact rule already exists
        # Use -qF for **Rule**: match (prefix is structured enough to avoid false positives)
        # Use -xqF for condensed bullets (full-line match prevents substring false positives)
        if grep -qF -- "**Rule**: ${rule}" "$LESSONS_FILE" 2>/dev/null || \
           grep -xqF -- "- ${rule}" "$LESSONS_FILE" 2>/dev/null; then
            print_debug "Lesson skipped (duplicate rule): $rule"
            return 0
        fi
    fi

    # Summarize oldest entries if at cap
    if (( entry_count >= LESSONS_MAX_ENTRIES )); then
        _summarize_old_lessons
    fi

    # Get next lesson number
    local next_num=1
    if [[ -f "$LESSONS_FILE" ]]; then
        local last_num
        last_num=$(grep '^## Lesson [0-9]' "$LESSONS_FILE" 2>/dev/null | tail -1 | sed 's/^## Lesson //' | sed 's/:.*//' || echo 0)
        next_num=$(( last_num + 1 ))
    else
        # Initialize file header
        cat > "$LESSONS_FILE" << 'LESSONS_HEADER'
# BuildCrew Lessons

Lessons learned from failures across runs. Injected into every persona's context automatically.
Use `buildcrew lessons` to list, `buildcrew lessons promote N` to graduate to project rules,
and `buildcrew lessons prune` to remove stale entries.

---

LESSONS_HEADER
    fi

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M')
    cat >> "$LESSONS_FILE" << EOF

## Lesson ${next_num}: ${timestamp}

**Phase**: ${phase}
**What went wrong**: ${what_went_wrong}
**What fixed it**: ${what_fixed_it}
**Rule**: ${rule}
**Applies to**: ${phase} persona

---
EOF
    print_info "Lesson recorded in $LESSONS_FILE"
}

# Check whether new lessons were recorded during a task and print a nudge.
# Usage: _check_lessons_nudge <lessons_before_count>
_check_lessons_nudge() {
    local lessons_before="${1:-0}"
    local lessons_after=0
    if [[ -f "$LESSONS_FILE" ]]; then
        lessons_after=$(grep -c '^## Lesson' "$LESSONS_FILE" 2>/dev/null) || lessons_after=0
    fi
    local new_lessons=$(( lessons_after - lessons_before ))
    if (( new_lessons > 0 )); then
        print_info "$new_lessons new lesson(s) recorded from this task. Run 'buildcrew lessons' to review."
        print_info "Tip: 'buildcrew lessons promote <N>' graduates a lesson to permanent project rules."
    fi
}

# Summarize oldest LESSONS_SUMMARIZE_COUNT entries into a Patterns section.
_summarize_old_lessons() {
    local tmp_file
    tmp_file=$(mktemp)

    # Extract the header/patterns section (before first "## Lesson") and all lesson entries
    local header_end
    header_end=$(grep -n '^## Lesson' "$LESSONS_FILE" 2>/dev/null | head -1 | cut -d: -f1)
    if [[ -z "$header_end" ]]; then
        return 0
    fi

    # Get existing patterns section (if any) or just the header
    local existing_patterns=""
    if grep -q '^## Patterns' "$LESSONS_FILE" 2>/dev/null; then
        existing_patterns=$(awk '/^## Patterns/,/^## Lesson/' "$LESSONS_FILE" 2>/dev/null | sed '$d')
    fi

    # Get all lesson entries
    local all_lessons
    all_lessons=$(grep -n '^## Lesson' "$LESSONS_FILE" 2>/dev/null)
    local total_lessons
    total_lessons=$(echo "$all_lessons" | wc -l | tr -d ' ')

    if (( total_lessons <= LESSONS_SUMMARIZE_COUNT )); then
        return 0
    fi

    # Get line numbers of the first LESSONS_SUMMARIZE_COUNT lessons to summarize
    local last_to_summarize_line
    last_to_summarize_line=$(echo "$all_lessons" | sed -n "${LESSONS_SUMMARIZE_COUNT}p" | cut -d: -f1)
    local first_to_keep_line
    first_to_keep_line=$(echo "$all_lessons" | sed -n "$((LESSONS_SUMMARIZE_COUNT + 1))p" | cut -d: -f1)

    if [[ -z "$first_to_keep_line" ]]; then
        return 0
    fi

    # Build new file: header + condensed patterns + remaining lessons
    {
        # File header (lines before first lesson, excluding any old patterns section)
        awk "NR < ${header_end} && !/^## Patterns/" "$LESSONS_FILE"

        # Condensed patterns section
        echo "## Patterns (condensed from oldest ${LESSONS_SUMMARIZE_COUNT} lessons)"
        echo ""
        echo "*The following patterns were extracted from the first ${LESSONS_SUMMARIZE_COUNT} lessons:*"
        echo ""
        # Emit preserved bullet rules from previous condensation cycles (if any)
        if [[ -n "$existing_patterns" ]]; then
            printf '%s\n' "$existing_patterns" | grep '^- ' || true
        fi
        # Extract just the "Rule" lines from summarized lessons as bullet points
        awk "NR >= ${header_end} && NR < ${first_to_keep_line} && /^\*\*Rule\*\*:/" "$LESSONS_FILE" | \
            sed 's/\*\*Rule\*\*: /- /'
        echo ""
        echo "---"
        echo ""

        # Remaining lessons (keep from first_to_keep_line onwards)
        awk "NR >= ${first_to_keep_line}" "$LESSONS_FILE"
    } > "$tmp_file"

    mv "$tmp_file" "$LESSONS_FILE"
    print_info "Condensed oldest ${LESSONS_SUMMARIZE_COUNT} lessons into patterns section"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Detect whether phase-isolated mode is available
# ─────────────────────────────────────────────────────────────────────────────────

# Detection checks TWO things:
# 1. The buildcrew SKILL.md has the phase-isolation marker (confirming buildcrew is updated)
# 2. The phase-specific skill directories exist (confirming the split files are available)
is_phase_isolation_available() {
    local skill_file
    skill_file=$(find -H .claude/skills/buildcrew -name "SKILL.md" 2>/dev/null | head -1)

    if [[ -n "$skill_file" ]] && grep -q 'phase-isolation' "$skill_file" \
        && [[ -d .claude/skills/buildcrew-research ]] \
        && [[ -d .claude/skills/buildcrew-review ]] \
        && [[ -d .claude/skills/buildcrew-build ]] \
        && [[ -d .claude/skills/buildcrew-codereview ]] \
        && [[ -d .claude/skills/buildcrew-verify ]]; then
        return 0
    fi
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────────
# Phase-Isolated Mode: run_phase_group
# ─────────────────────────────────────────────────────────────────────────────────

if [[ -z "${RATE_LIMIT_PATTERN+x}" ]]; then
    readonly RATE_LIMIT_PATTERN='rate.limit.reached|rate.limit.exceeded|rate_limit_error|usage.limit'
fi

# Helper: Check for rate limit in log and signal pause if detected.
# Args: $1=phase, $2=log_offset, $3=message (optional, defaults to generic)
# Returns: 0 if rate limit detected and handled, 1 otherwise
_check_and_signal_rate_limit() {
    local phase="$1" offset="$2" msg="${3:-API rate/usage limit detected — signaling pause}"
    if _check_rate_limit_in_log "$offset"; then
        print_warning "Phase $phase: $msg"
        update_workflow_state "$phase" "rate_limited"
        _signal_rate_limit_pause || true
        return 0
    fi
    return 1
}

# Check recent log output for max-turns indicator.
# Args: $1=log_offset (byte offset captured before claude -p call)
# Returns: 0 if max-turns detected, 1 otherwise
_check_max_turns_in_log() {
    local offset="$1"
    if [[ -z "${__LOG_FILE:-}" || ! -f "$__LOG_FILE" ]]; then
        return 1
    fi
    local recent
    recent=$(tail -c +"$(( offset + 1 ))" "$__LOG_FILE" 2>/dev/null || true)
    if echo "$recent" | grep -qi "max.turns"; then
        return 0
    fi
    return 1
}

# Check recent log output for permission denial indicator.
# Args: $1=log_offset (byte offset captured before claude -p call)
# Sets: __PERM_DENIED_TOOL to the tool name (or "unknown tool")
# Returns: 0 if permission denial detected, 1 otherwise
_check_permission_denied_in_log() {
    local offset="$1"
    __PERM_DENIED_TOOL=""
    if [[ -z "${__LOG_FILE:-}" || ! -f "$__LOG_FILE" ]]; then
        return 1
    fi
    local recent
    recent=$(tail -c +"$(( offset + 1 ))" "$__LOG_FILE" 2>/dev/null || true)
    if [[ -z "$recent" ]]; then
        return 1
    fi

    # Pattern 1: Claude CLI structured permission output — extract Bash(...) tool name
    # from lines that contain permission/approval/blocked keywords.
    # Two-stage grep avoids false positives from settings.json content in phase output.
    local match=""
    match=$(echo "$recent" | grep -iE 'blocked|denied|approval|permission|allowed' | grep -oE 'Bash\([^)]+\)' | head -1) || true
    if [[ -n "$match" ]]; then
        __PERM_DENIED_TOOL="$match"
        return 0
    fi

    # Pattern 2: Generic permission/approval language (fallback — sets tool to "unknown")
    if echo "$recent" | grep -qi "tool use was blocked\|requires approval\|permission.*denied\|not allowed to use"; then
        __PERM_DENIED_TOOL="unknown tool"
        return 0
    fi

    return 1
}

# Check recent log output for rate/usage limit indicator.
# Args: $1=log_offset (byte offset captured before claude -p call)
# Returns: 0 if rate limit detected, 1 otherwise
_check_rate_limit_in_log() {
    local offset="$1"
    if [[ -z "${__LOG_FILE:-}" || ! -f "$__LOG_FILE" ]]; then
        return 1
    fi
    local recent
    recent=$(tail -c +"$(( offset + 1 ))" "$__LOG_FILE" 2>/dev/null || true)
    if [[ -z "$recent" ]]; then
        return 1
    fi
    if echo "$recent" | grep -qiE "$RATE_LIMIT_PATTERN"; then
        return 0
    fi
    return 1
}

# Signal rate limit pause to parent via sentinel file in batch parent directory.
# Requires: BUILDCREW_BATCH_PARENT_CWD env var set
# Returns: 0 on success, 1 on error
_signal_rate_limit_pause() {
    local parent_cwd="${BUILDCREW_BATCH_PARENT_CWD:-}"
    if [[ -z "$parent_cwd" ]]; then
        return 1
    fi
    touch "${parent_cwd}/.buildcrew/.rate-limit-pause" 2>/dev/null || return 1
    return 0
}

# Check if rate limit pause signal exists in parent directory.
# Args: $1=parent_cwd (batch parent directory)
# Returns: 0 if sentinel exists, 1 otherwise
_check_rate_limit_pause() {
    local parent_cwd="$1"
    [[ -f "${parent_cwd}/.buildcrew/.rate-limit-pause" ]]
}

# Clear rate limit pause signal from parent directory.
# Args: $1=parent_cwd (batch parent directory)
_clear_rate_limit_pause() {
    local parent_cwd="$1"
    rm -f "${parent_cwd}/.buildcrew/.rate-limit-pause"
}

# Requeue all rate-limited tasks back to pending status.
# Updates .buildcrew/.batch-state with task_status[N]=pending
_batch_requeue_rate_limited_tasks() {
    local state_file=".buildcrew/.batch-state"
    if [[ ! -f "$state_file" ]]; then
        return 0
    fi
    local tmp
    tmp=$(mktemp)
    sed 's/task_status\(\[[0-9]*\]\)=rate_limited/task_status\1=pending/g' "$state_file" > "$tmp"
    mv "$tmp" "$state_file"
    return 0
}


# Handle rate limit pause: interactive UI with retry/wait/quit options.
# Args: $1=backoff_seconds (how long [w]ait option waits)
# Returns: 0 on resume (retry), 1 on quit
_batch_handle_rate_limit_pause() {
    local backoff="${1:-300}"
    local total=${#_batch_tasks[@]}
    local pending=$(( total - _batch_completed - _batch_failed - _batch_rate_limited ))

    echo ""
    echo -e "${YELLOW}═══ PAUSED — API Rate/Usage Limit ════════════════════════════════${NC}"
    echo ""
    echo -e "  Completed: ${GREEN}$_batch_completed${NC}  |  Rate-limited: ${YELLOW}$_batch_rate_limited${NC}  |  Failed: ${RED}$_batch_failed${NC}  |  Pending: $pending"
    echo ""
    echo -e "  [Enter]  Retry now"
    echo -e "  [w]      Wait $(( backoff / 60 )) minute(s) then auto-retry"
    echo -e "  [q]      Quit batch (resumable with: buildcrew run --batch --resume)"
    echo ""

    local choice=""
    if read -t 30 -r -n 1 choice 2>/dev/null; then
        echo ""
        case "$choice" in
            q|Q)
                print_info "Batch paused. Resume later with: buildcrew run --batch --resume"
                return 1
                ;;
            w|W)
                print_info "Waiting $(( backoff / 60 )) minute(s) before retry..."
                sleep "$backoff"
                ;;
            *)
                print_info "Retrying now..."
                ;;
        esac
    else
        echo ""
        print_info "No input received — auto-retrying..."
    fi

    # Requeue all rate_limited tasks in JSON manifest back to pending
    local i
    for i in "${!_batch_tasks[@]}"; do
        local midx=$(( i + 1 ))
        local st
        st=$(_batch_get_task_status "$midx")
        if [[ "$st" == "rate_limited" ]]; then
            _batch_mark_task "$midx" "pending"
        fi
    done
    _batch_requeue_rate_limited_tasks  # Also update .batch-state key-value file
    _batch_rate_limited=0
    print_info "Rate-limited tasks requeued — resuming batch."
    return 0
}

# Convert a tool description string to a permission rule for settings.local.json.
# Examples:
#   "Bash(docker:*)"         -> "Bash(docker:*)"   (pass-through)
#   'approval to run `npm test`' -> "Bash(npm:*)"
#   "unknown tool"           -> ""  (cannot parse)
_tool_desc_to_permission() {
    local desc="$1"
    # Pass-through: already looks like a permission rule
    if echo "$desc" | grep -qE '^Bash\([^)]+\)$'; then
        echo "$desc"
        return
    fi
    # Extract command from backtick-quoted content: `npm test` -> npm
    local cmd
    cmd=$(echo "$desc" | sed -nE 's/.*`([^`]+)`.*/\1/p' | head -1)
    if [[ -n "$cmd" ]]; then
        local prefix
        prefix=$(echo "$cmd" | awk '{print $1}')
        if [[ -n "$prefix" ]]; then
            echo "Bash($prefix:*)"
            return
        fi
    fi
    # Fallback: first word as command (strip non-alnum chars)
    # Note: "unknown tool" -> "unknown" which is rejected below intentionally,
    # so callers get "" and are forced to use the [e]dit path.
    cmd=$(echo "$desc" | awk '{print $1}' | sed 's/[^a-zA-Z0-9_./-]//g')
    if [[ -n "$cmd" && "$cmd" != "unknown" ]]; then
        echo "Bash($cmd:*)"
        return
    fi
    # Cannot parse
    echo ""
}

# Append a permission rule to .claude/settings.local.json.
# Creates the file (and directory) if missing. Idempotent.
# Args: $1=tool_desc (description string or Bash(...) rule)
_add_permission_to_settings() {
    local tool_desc="$1"
    local settings_file=".claude/settings.local.json"
    local perm_rule
    perm_rule=$(_tool_desc_to_permission "$tool_desc")
    if [[ -z "$perm_rule" ]]; then
        return 1
    fi
    # Ensure .claude directory exists
    mkdir -p .claude
    # Create file if missing
    if [[ ! -f "$settings_file" ]]; then
        echo '{"permissions":{"allow":[]}}' > "$settings_file"
    fi
    # Check if already present (jq -e exits non-zero on null)
    if jq -e --arg r "$perm_rule" '.permissions.allow | index($r)' "$settings_file" >/dev/null 2>&1; then
        return 0
    fi
    # Add atomically via temp file
    local tmp_file="${settings_file}.tmp.$$"
    if jq --arg r "$perm_rule" '.permissions.allow += [$r]' "$settings_file" > "$tmp_file" 2>/dev/null; then
        mv "$tmp_file" "$settings_file"
    else
        rm -f "$tmp_file"
        return 1
    fi
}

# Known-safe tool prefixes that can be auto-approved in --auto mode.
# Anything not on this list requires interactive approval.
__SAFE_AUTO_APPROVE_TOOLS="cat ls head tail wc grep find file stat diff sort uniq tr cut tee mkdir cp mv rm touch chmod sed awk test echo printf date pwd cd basename dirname readlink"

# Prompt the user to approve a tool permission after a phase is blocked.
# In --auto mode, approves known-safe tools and blocks unsafe ones.
# Args: $1=tool_desc, $2=phase
# Returns: 0 if approved (settings updated), 1 if skipped/blocked
_prompt_permission_approval() {
    local tool_desc="$1"
    local phase="$2"

    if [[ "$AUTO_MODE" == "true" ]]; then
        local perm_rule
        perm_rule=$(_tool_desc_to_permission "$tool_desc")
        if [[ -z "$perm_rule" ]]; then
            print_warning "Auto mode: cannot parse permission for '$tool_desc' -- skipping"
            return 1
        fi
        # Extract the command prefix from Bash(prefix:*)
        local cmd_prefix
        cmd_prefix=$(echo "$perm_rule" | sed -nE 's/^Bash\(([^:]+):\*\)$/\1/p')
        # Only auto-approve known-safe tools
        if [[ -n "$cmd_prefix" ]] && echo " $__SAFE_AUTO_APPROVE_TOOLS " | grep -q " $cmd_prefix "; then
            print_info "Auto mode: auto-approving safe tool permission ($perm_rule)"
            _add_permission_to_settings "$tool_desc" || true
            return 0
        fi
        print_warning "Auto mode: refusing to auto-approve potentially unsafe tool ($perm_rule) -- marking blocked"
        return 1
    fi

    if [[ ! -t 0 ]]; then
        print_warning "Non-interactive terminal -- cannot prompt for permission (tool: $tool_desc)"
        return 1
    fi

    echo ""
    print_warning "Phase '$phase' was blocked by a tool permission."
    echo -e "  Tool: $tool_desc"
    echo ""
    echo -e "  [a] Approve and add to .claude/settings.local.json, then retry"
    echo -e "  [e] Edit .claude/settings.local.json manually, then retry"
    echo -e "  [s] Skip (mark task blocked)"
    echo ""
    while true; do
        read -r -p "  > " perm_response
        case "$perm_response" in
            a|A)
                if _add_permission_to_settings "$tool_desc"; then
                    print_success "Permission added"
                    return 0
                else
                    print_error "Could not auto-add permission. Use [e] to add manually."
                fi ;;
            e|E)
                ${EDITOR:-vi} ".claude/settings.local.json"
                print_info "Settings updated. Retrying phase."
                return 0 ;;
            s|S) return 1 ;;
            *) echo "  Please enter [a], [e], or [s]:" ;;
        esac
    done
}

__run_phase_group_impl() {
    local phase="$1"
    local task="$2"
    local extra_context="${3:-}"
    local task_complexity="${4:-standard}"
    local max_turns
    max_turns=$(get_phase_max_turns "$phase")

    # Global invocation ceiling — prevent runaway API cost
    if (( __INVOCATION_COUNT >= MAX_INVOCATIONS )); then
        print_error "Global invocation ceiling reached ($__INVOCATION_COUNT/$MAX_INVOCATIONS) — aborting phase: $phase"
        return 1
    fi

    print_debug "Invocation budget: $__INVOCATION_COUNT/$MAX_INVOCATIONS used"
    rm -f "$PHASE_RESULT_FILE"

    print_info "Phase: $phase (max $max_turns turns)"

    # Build prompt: inline SKILL.md content directly so phase instructions are
    # always available even if the Skill tool fails in headless (claude -p) mode.
    local skill_file=".claude/skills/buildcrew-${phase}/SKILL.md"
    local prompt

    # pkill cross-talk safety: when running in batch mode, include a unique nonce
    # in the prompt so the file monitor's pkill pattern only matches this worker.
    local batch_nonce="${BUILDCREW_BATCH_NONCE:-}"
    local phase_tag="buildcrew-${phase}"
    if [[ -n "$batch_nonce" ]]; then
        phase_tag="buildcrew-${phase}:${batch_nonce}"
    fi

    # Extract allowed-tools from SKILL.md frontmatter before stripping it
    local allowed_tools=""
    if [[ -f "$skill_file" ]]; then
        allowed_tools=$(awk 'NR==1&&/^---/{f=1;next} f&&/^---/{f=0;next} f&&/^allowed-tools:/{sub(/^allowed-tools:[[:space:]]*/,"");print}' "$skill_file")
        # Strip YAML frontmatter (content between first and second --- delimiters)
        local skill_content
        skill_content=$(awk 'NR==1&&/^---/{f=1;next} f&&/^---/{f=0;next} !f' "$skill_file")
        prompt="Execute the $phase_tag skill for this task: $task"
        if [[ -n "$extra_context" ]]; then
            prompt="$prompt. Context: $extra_context"
        fi
        prompt="$prompt"$'\n\n---\n\n'"$skill_content"
    else
        prompt="Execute the $phase_tag skill for this task: $task"
        if [[ -n "$extra_context" ]]; then
            prompt="$prompt. Context: $extra_context"
        fi
    fi

    # Inject project context
    local project_context
    project_context=$(load_project_context)
    if [[ -n "$project_context" ]]; then
        prompt="$prompt"$'\n\nProject Context:\n'"$project_context"
    fi

    # Inject skill catalog only for phases that use the Skill tool
    if [[ "$allowed_tools" == *"Skill"* ]]; then
        local skill_catalog
        skill_catalog=$(build_skill_catalog)
        if [[ -n "$skill_catalog" ]]; then
            prompt="$prompt"$'\n\nSkill Catalog:\n'"$skill_catalog"
        fi
    fi

    # Inject TDD context for build/test/codereview phases
    prompt=$(__inject_tdd_prompt "$phase" "$prompt")

    # Inject context management guidance (compressed)
    prompt="$prompt"$'\n\n'"## Context Management
Use Task subagents for: reading 3+ files, research, code review/analysis, any investigation where only the summary matters. Stay in main context for: direct file edits, short reads (1-2 files), back-and-forth conversations."

    # Inject phase-filtered lessons (only lessons relevant to this phase)
    local phase_lessons
    phase_lessons=$(load_phase_lessons "$phase")
    if [[ -n "$phase_lessons" ]]; then
        prompt="$prompt"$'\n\n'"# Lessons Learned"$'\n'"$phase_lessons"
    fi

    # Inject phase result protocol (centralized, replaces per-SKILL.md sections)
    local result_protocol
    result_protocol=$(__inject_phase_result_protocol "$phase")
    prompt="$prompt"$'\n\n'"$result_protocol"

    # Inject concision directives for phases where verbose output is wasteful
    case "$phase" in
        research|tdd-scaffold)
            prompt="$prompt"$'\n\n'"Be extremely concise. Sacrifice grammar for concision. No preamble, no summaries of what you will do — execute directly."
            ;;
        review|codereview)
            prompt="$prompt"$'\n\n'"Be direct and terse in analysis. No preamble. State findings, not your review process."
            ;;
    esac

    # Build --allowedTools flag if declared in skill frontmatter
    local allowed_tools_flag=""
    if [[ -n "$allowed_tools" ]]; then
        allowed_tools_flag="--allowedTools $allowed_tools"
    fi

    local resolved_model
    resolved_model=$(resolve_phase_model "$phase" "$task_complexity")
    local model_effort_flags=""
    model_effort_flags+=" --model $resolved_model"
    [[ -n "${CLAUDE_EFFORT:-}" ]] && model_effort_flags+=" --effort $CLAUDE_EFFORT"
    print_debug "Phase $phase: model=$resolved_model effort=${CLAUDE_EFFORT:-medium} (complexity=${task_complexity})"

    # Save terminal state — claude may leave terminal in raw/no-echo mode when
    # killed by SIGINT (from the file monitor), breaking subsequent read prompts.
    local __saved_stty=""
    if [[ -t 0 ]]; then
        __saved_stty=$(stty -g 2>/dev/null) || __saved_stty=""
    fi

    # Start file watcher (uses phase_tag for pkill pattern — unique per worker in batch mode)
    start_file_monitor "$PHASE_RESULT_FILE" "claude.*${phase_tag}"

    update_workflow_state "$phase" "running" "$resolved_model"
    __INVOCATION_COUNT=$(( __INVOCATION_COUNT + 1 ))
    print_debug "Invoking claude for phase: $phase (invocation $__INVOCATION_COUNT/$MAX_INVOCATIONS, max_turns=$max_turns)"
    log_msg "=== PHASE: $phase started (max_turns=$max_turns, invocation=$__INVOCATION_COUNT/$MAX_INVOCATIONS) ==="
    local __log_offset=0
    if [[ -n "${__LOG_FILE:-}" && -f "$__LOG_FILE" ]]; then
        __log_offset=$(wc -c < "$__LOG_FILE" | tr -d ' ')
    fi
    if [[ -n "$__LOG_FILE" ]]; then
        log_msg "--- claude output start: $phase ---"
        if [[ "$__ACTIVITY_TRACKING" == "true" ]]; then
            claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag $model_effort_flags --output-format stream-json --verbose 2>&1 | python3 "$BUILDCREW_HOME/lib/stream_processor.py" --activity-file ".buildcrew/.agent-activity" --max-turns "$max_turns" | tee -a "$__LOG_FILE" || true
        else
            claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag $model_effort_flags 2>&1 | tee -a "$__LOG_FILE" || true
        fi
        log_msg "--- claude output end: $phase ---"
    else
        if [[ "$__ACTIVITY_TRACKING" == "true" ]]; then
            claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag $model_effort_flags --output-format stream-json --verbose 2>&1 | python3 "$BUILDCREW_HOME/lib/stream_processor.py" --activity-file ".buildcrew/.agent-activity" --max-turns "$max_turns" || true
        else
            claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag $model_effort_flags || true
        fi
    fi

    stop_file_monitor
    rm -f ".buildcrew/.agent-activity"
    # Restore terminal state in case claude modified it before being killed
    [[ -n "$__saved_stty" ]] && stty "$__saved_stty" 2>/dev/null || true

    # Validate result (with one retry on failure)
    if [[ ! -f "$PHASE_RESULT_FILE" ]] || ! jq -e . "$PHASE_RESULT_FILE" >/dev/null 2>&1; then
        # Check for rate/usage limit first -- retrying is futile and wastes quota
        if _check_and_signal_rate_limit "$phase" "$__log_offset"; then
            return 4
        fi
        # Check for permission denial first -- this is recoverable
        if _check_permission_denied_in_log "$__log_offset"; then
            if ! _prompt_permission_approval "$__PERM_DENIED_TOOL" "$phase"; then
                update_workflow_state "$phase" "permission_denied" "$resolved_model"
                return 1
            fi
            # Permission approved -- fall through to retry below
        # Check for max-turns before retrying -- retrying at the same limit will hit the same wall
        elif _check_max_turns_in_log "$__log_offset"; then
            print_warning "Phase $phase hit max-turns limit ($max_turns turns)"
            update_workflow_state "$phase" "max_turns" "$resolved_model"
            return 2
        fi

        print_warning "Phase $phase produced no valid result. Retrying..."
        rm -f "$PHASE_RESULT_FILE"

        # Check ceiling again before retry
        if (( __INVOCATION_COUNT >= MAX_INVOCATIONS )); then
            print_error "Global invocation ceiling reached ($__INVOCATION_COUNT/$MAX_INVOCATIONS) — cannot retry phase: $phase"
            return 1
        fi

        start_file_monitor "$PHASE_RESULT_FILE" "claude.*${phase_tag}"

        update_workflow_state "$phase" "running" "$resolved_model"
        __INVOCATION_COUNT=$(( __INVOCATION_COUNT + 1 ))
        print_debug "Phase $phase produced no result file — retrying (invocation $__INVOCATION_COUNT/$MAX_INVOCATIONS)"
        log_msg "=== PHASE: $phase retry (invocation=$__INVOCATION_COUNT/$MAX_INVOCATIONS) ==="
        # Re-capture offset for retry
        __log_offset=0
        if [[ -n "${__LOG_FILE:-}" && -f "$__LOG_FILE" ]]; then
            __log_offset=$(wc -c < "$__LOG_FILE" | tr -d ' ')
        fi
        if [[ -n "$__LOG_FILE" ]]; then
            log_msg "--- claude output start: $phase ---"
            if [[ "$__ACTIVITY_TRACKING" == "true" ]]; then
                claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag $model_effort_flags --output-format stream-json --verbose 2>&1 | python3 "$BUILDCREW_HOME/lib/stream_processor.py" --activity-file ".buildcrew/.agent-activity" --max-turns "$max_turns" | tee -a "$__LOG_FILE" || true
            else
                claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag $model_effort_flags 2>&1 | tee -a "$__LOG_FILE" || true
            fi
            log_msg "--- claude output end: $phase ---"
        else
            if [[ "$__ACTIVITY_TRACKING" == "true" ]]; then
                claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag $model_effort_flags --output-format stream-json --verbose 2>&1 | python3 "$BUILDCREW_HOME/lib/stream_processor.py" --activity-file ".buildcrew/.agent-activity" --max-turns "$max_turns" || true
            else
                claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag $model_effort_flags || true
            fi
        fi

        stop_file_monitor
        rm -f ".buildcrew/.agent-activity"
        [[ -n "$__saved_stty" ]] && stty "$__saved_stty" 2>/dev/null || true

        if [[ ! -f "$PHASE_RESULT_FILE" ]] || ! jq -e . "$PHASE_RESULT_FILE" >/dev/null 2>&1; then
            # Check rate limit on retry result before other checks
            if _check_and_signal_rate_limit "$phase" "$__log_offset" "API rate/usage limit detected on retry — signaling pause"; then
                return 4
            fi
            # Permission denial on retry -- return 3 for wrapper to re-invoke
            if _check_permission_denied_in_log "$__log_offset"; then
                if _prompt_permission_approval "$__PERM_DENIED_TOOL" "$phase"; then
                    return 3  # permission recovered, wrapper will re-invoke
                fi
            fi
            # Log-based check on retry failure
            if _check_max_turns_in_log "$__log_offset"; then
                print_warning "Phase $phase hit max-turns limit on retry ($max_turns turns)"
                update_workflow_state "$phase" "max_turns" "$resolved_model"
                return 2
            fi
            # Heuristic: both attempts failed on a heavy phase = likely max-turns
            if [[ "$phase" == "build" ]]; then
                print_warning "Phase $phase failed both attempts -- treating as likely max-turns"
                update_workflow_state "$phase" "max_turns" "$resolved_model"
                return 2
            fi
            print_error "Phase $phase failed after retry"
            update_workflow_state "$phase" "failed" "$resolved_model"
            return 1
        fi
    fi

    local verdict
    verdict=$(jq -r '.verdict // "unknown"' "$PHASE_RESULT_FILE")
    print_debug "Phase result: verdict=$verdict, details=$(jq -r '.details // "none"' "$PHASE_RESULT_FILE")"
    print_success "Phase $phase complete — verdict: $verdict"
    update_workflow_state "$phase" "complete" "$resolved_model"
    log_msg "=== PHASE: $phase ended (verdict: $verdict) ==="
}

# Wrapper: transparent retry on permission recovery (return code 3 from impl).
# All callers use this function; the impl is private.
run_phase_group() {
    local result=0
    __run_phase_group_impl "$@" || result=$?
    if [[ $result -eq 3 ]]; then
        print_info "Permission recovered -- retrying phase: $1"
        result=0
        __run_phase_group_impl "$@" || result=$?
        if [[ $result -eq 3 ]]; then
            print_error "Permission recovery failed on retry -- giving up"
            result=1
        fi
    fi
    return $result
}

# ─────────────────────────────────────────────────────────────────────────────────
# Chunked phase execution (fallback when a phase hits max-turns)
# ─────────────────────────────────────────────────────────────────────────────────

# Execute build phase one plan step at a time.
# Args: $1=task $2=spec_context (optional) $3=task_complexity (optional)
# Returns: 0=all steps complete, 1=step failed, 2=single step hit max-turns
run_chunked_build() {
    local task="$1"
    local spec_context="${2:-}"
    local task_complexity="${3:-standard}"

    local step_count
    step_count=$(parse_plan_steps) || {
        print_warning "No parseable steps in plan -- cannot chunk build"
        return 1
    }

    print_info "Chunked build: $step_count steps found"

    local step_num
    while step_num=$(get_next_pending_step); do
        # Check MAX_INVOCATIONS ceiling before each chunk
        if (( __INVOCATION_COUNT >= MAX_INVOCATIONS )); then
            print_error "Global invocation ceiling reached during chunked build ($__INVOCATION_COUNT/$MAX_INVOCATIONS)"
            return 1
        fi

        local step_name
        step_name=$(get_step_name "$step_num")

        local chunk_context="CHUNKED BUILD MODE: Execute ONLY Step $step_num"
        chunk_context="$chunk_context ($step_name) from .claude/current-plan.md."
        chunk_context="$chunk_context Steps 1 through $((step_num - 1)) are ALREADY COMPLETE."
        chunk_context="$chunk_context Do NOT proceed to subsequent steps."
        chunk_context="$chunk_context After completing this step, write phase-result.json."
        if [[ -n "$spec_context" ]]; then
            chunk_context="$chunk_context | $spec_context"
        fi

        local chunk_result=0
        run_phase_group "build" "$task" "$chunk_context" "$task_complexity" || chunk_result=$?

        if [[ $chunk_result -eq 4 ]]; then
            return 4
        elif [[ $chunk_result -eq 2 ]]; then
            print_error "Single build step $step_num hit max-turns -- step is too large"
            return 2
        elif [[ $chunk_result -ne 0 ]]; then
            print_error "Chunked build step $step_num failed"
            return 1
        fi

        mark_step_complete "$step_num"
        rm -f "$PHASE_RESULT_FILE"  # Clear for next step
    done

    clear_step_progress
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────
# Verify-failure rebuild context builder
# ─────────────────────────────────────────────────────────────────────────────────

# Build rich context string for rebuild after verify failure.
# Reads phase-result.json details and points the build skill to the right artifacts.
build_verify_failure_context() {
    local failing="$1"
    local details
    details=$(jq -r '.details // "unknown"' "$PHASE_RESULT_FILE" 2>/dev/null)

    local context="REBUILD AFTER VERIFY FAILURE"
    context="$context | Failing check: $failing"
    context="$context | Details: $details"

    case "$failing" in
        tests)
            context="$context | Read .claude/verify-report.md for failure details before fixing."
            ;;
        security)
            context="$context | Read .claude/security-audit.md and .claude/verify-report.md for vulnerability details before fixing."
            ;;
    esac

    echo "$context"
}

# ═════════════════════════════════════════════════════════════════════════════════
# Inline UAT — run UAT phases inside the main pipeline (after verify).
# Args: project_name task task_complexity
# Returns: 0 on all-pass, 1 on max retries/fatal, 2 on only-disputed
# ═════════════════════════════════════════════════════════════════════════════════

# Bridge __MANIFEST_* globals to __UAT_* globals (required by UAT phase functions).
# Call after every publish_artifact + read_manifest.
_bridge_manifest_to_uat() {
    __UAT_ARTIFACT_TYPE="$__MANIFEST_ARTIFACT_TYPE"
    __UAT_ARTIFACT_PATH="$__MANIFEST_ARTIFACT_PATH"
    __UAT_RUN_COMMAND="$__MANIFEST_RUN_COMMAND"
    __UAT_INSTALL_COMMAND="$__MANIFEST_INSTALL_COMMAND"
    __UAT_HEALTH_CHECK="$__MANIFEST_HEALTH_CHECK"
    __UAT_STOP_COMMAND="$__MANIFEST_STOP_COMMAND"
    __UAT_BUILD_ITERATION="$__MANIFEST_BUILD_ITERATION"
    __UAT_README_HASH="$__MANIFEST_README_HASH"
}

# Run the rebuild pipeline (build -> codereview -> verify)
# during an inline UAT retry. Returns non-zero on failure.
# Args: $1=task $2=task_complexity $3=rebuild_context
_uat_rebuild_pipeline() {
    local task="$1"
    local task_complexity="$2"
    local rebuild_context="$3"

    run_phase_group "build" "$task" "$rebuild_context" "$task_complexity" || return 1
    if [[ "$task_complexity" != "trivial" && "$task_complexity" != "simple" ]]; then
        run_optional_docs "$task" ""
        run_phase_group "codereview" "$task" "" "$task_complexity" || return 1
        local cr_verdict
        cr_verdict=$(jq -r '.verdict' "$PHASE_RESULT_FILE")
        if [[ "$cr_verdict" == "needs_rebuild" ]]; then
            print_warning "Code review rejected UAT rebuild — running another build pass"
            run_phase_group "build" "$task" "$rebuild_context" "$task_complexity" || return 1
        fi
    fi
    run_phase_group "verify" "$task" "" "$task_complexity" || return 1
    local verify_verdict
    verify_verdict=$(jq -r '.verdict' "$PHASE_RESULT_FILE")
    if [[ "$verify_verdict" != "complete" ]]; then
        print_error "Verify phase blocked during UAT rebuild"
        return 1
    fi
}

run_inline_uat() {
    local project_name="$1"
    local task="$2"
    local task_complexity="${3:-standard}"

    local project_dir
    project_dir="$(pwd)"

    # Initialize UAT state for dashboard visibility
    init_uat_state "$project_dir" "$project_name"

    # 1. Publish artifact
    publish_artifact "$project_name" || {
        print_error "Failed to publish artifact for UAT"
        cd "$project_dir"
        return 1
    }

    # 2. Read manifest and bridge globals
    local manifest_path="$HOME/.buildcrew/artifacts/$project_name/manifest.json"
    read_manifest "$manifest_path" || {
        print_error "Failed to read artifact manifest"
        cd "$project_dir"
        return 1
    }
    _bridge_manifest_to_uat

    # 3. Create isolated UAT working directory
    local uat_dir="$HOME/.buildcrew/uat-workdirs/$project_name"
    # Clean up any stale directory from prior interrupted run
    if [[ -d "$uat_dir" ]]; then
        rm -rf "$uat_dir"
    fi
    mkdir -p "$uat_dir"
    cd "$uat_dir" || { print_error "Failed to cd to UAT directory"; cd "$project_dir"; return 1; }

    # Save existing trap and set up cleanup trap
    local __saved_trap
    __saved_trap=$(trap -p INT TERM)
    local __inline_uat_cleaned=false
    _inline_uat_cleanup() {
        [[ "$__inline_uat_cleaned" == "true" ]] && return
        __inline_uat_cleaned=true
        clean_uat_state
        uat_stop_server 2>/dev/null || true
        rm -rf "$uat_dir" 2>/dev/null || true
        cd "$project_dir" 2>/dev/null || true
        # Restore caller's trap
        if [[ -n "$__saved_trap" ]]; then
            eval "$__saved_trap"
        else
            trap - INT TERM
        fi
    }
    trap '_inline_uat_cleanup; exit 130' INT TERM

    # 4. Initialize UAT working directory
    __uat_cleaned=false  # Reset uat_cleanup guard for this run
    uat_init "$project_dir/README.md" "$project_name" || {
        print_error "UAT init failed"
        _inline_uat_cleanup
        return 1
    }

    # 4a. Copy precomputed artifact-type.md into UAT working directory
    local precompute_src="$project_dir/.claude/precompute/artifact-type.md"
    if [[ -f "$precompute_src" ]]; then
        mkdir -p .claude/precompute
        cp "$precompute_src" .claude/precompute/artifact-type.md
        print_debug "Copied precomputed artifact-type.md to UAT dir"
    fi

    local run_start_time
    run_start_time=$(date +%s)
    local signal_dir="$HOME/.buildcrew/uat-signals/$project_name"

    # 6. Run Phases 1-3: stories, scenarios, harness
    print_header "Inline UAT — Phases 1-3"
    write_uat_state "stories" "$__UAT_BUILD_ITERATION" "running"
    uat_phase_stories || { print_error "UAT stories phase failed"; _inline_uat_cleanup; return 1; }
    write_uat_state "scenarios" "$__UAT_BUILD_ITERATION" "running"
    uat_phase_scenarios || { print_error "UAT scenarios phase failed"; _inline_uat_cleanup; return 1; }
    _uat_list_scenarios
    write_uat_state "harness" "$__UAT_BUILD_ITERATION" "running"
    uat_phase_harness || { print_error "UAT harness phase failed"; _inline_uat_cleanup; return 1; }

    # 7. Retry loop: setup → execute → verdict
    local retry_count=0
    local max_retries="${UAT_MAX_RETRIES:-3}"
    local failing_scenarios=""
    local build_iteration="$__UAT_BUILD_ITERATION"

    # Helper: rebuild → republish → re-bridge → regen harness
    # Must be called while cwd is $project_dir
    _uat_republish_and_regen() {
        local __regen_task="$1"
        local __regen_complexity="$2"
        local __regen_context="$3"
        _uat_rebuild_pipeline "$__regen_task" "$__regen_complexity" "$__regen_context" || return 1
        publish_artifact "$project_name" || return 1
        read_manifest "$manifest_path" || return 1
        _bridge_manifest_to_uat
        build_iteration="$__UAT_BUILD_ITERATION"
        cd "$uat_dir" || return 1
        uat_phase_harness || return 1
    }

    while true; do
        cd "$uat_dir" || { print_error "Failed to cd to UAT dir"; cd "$project_dir"; return 1; }

        # Phase 4.5: Setup artifact environment
        write_uat_state "setup" "$build_iteration" "running"
        local artifact_context=""
        uat_phase_setup_env \
            "$__UAT_ARTIFACT_TYPE" \
            "$__UAT_ARTIFACT_PATH" \
            "$__UAT_RUN_COMMAND" \
            "$__UAT_INSTALL_COMMAND" \
            "$__UAT_HEALTH_CHECK" || {
            local setup_rc=$?
            if [[ $setup_rc -eq 2 ]]; then
                # Install failure — write error verdict and retry
                local error_json
                error_json=$(jq -n '[{"scenario":"artifact_setup","status":"error","summary":"Artifact install or setup failed","expected":"Artifact installs successfully","actual":"Install command exited non-zero"}]')
                write_verdict "$signal_dir" "$error_json" "$build_iteration"
                write_last_tested_iteration ".buildcrew" "$build_iteration"
                retry_count=$((retry_count + 1))
                if [[ $retry_count -ge $max_retries ]]; then
                    print_error "UAT max retries ($max_retries) exhausted after setup failure"
                    _uat_print_report "$signal_dir" "$run_start_time"
                    _inline_uat_cleanup
                    return 1
                fi
                print_warning "Artifact setup failed — rebuilding (retry $retry_count/$max_retries)"
                cd "$project_dir" || { _inline_uat_cleanup; return 1; }
                _uat_republish_and_regen "$task" "$task_complexity" \
                    "UAT failure context: Artifact setup/install failed. Check .buildcrew/uat-context.md for details. Do NOT access the UAT directory or scenarios." \
                    || { _inline_uat_cleanup; return 1; }
                continue
            fi
            # Fatal setup error
            _inline_uat_cleanup
            return 1
        }
        artifact_context="$__UAT_ARTIFACT_CONTEXT"

        # Clean up partial results from a previous crash
        local results_dir="results/iteration-${build_iteration}"
        if [[ -d "$results_dir" ]] && [[ ! -f "${results_dir}/scenario-results.json" ]]; then
            rm -rf "$results_dir"
        fi
        mkdir -p "$results_dir"

        # Phase 5: Execute scenarios
        write_uat_state "execute" "$build_iteration" "running"
        uat_phase_execute "$build_iteration" "$artifact_context" "$failing_scenarios" || {
            local error_json
            error_json=$(jq -n '[{"scenario":"harness_execution","status":"error","summary":"Phase 5 execution failed","expected":"Test harness runs successfully","actual":"Claude agent crashed or timed out"}]')
            write_verdict "$signal_dir" "$error_json" "$build_iteration"
            write_last_tested_iteration ".buildcrew" "$build_iteration"
            uat_stop_server
            failing_scenarios=""
            retry_count=$((retry_count + 1))
            if [[ $retry_count -ge $max_retries ]]; then
                print_error "UAT max retries ($max_retries) exhausted"
                _uat_print_report "$signal_dir" "$run_start_time"
                _inline_uat_cleanup
                return 1
            fi
            continue
        }

        # Stop server after execute (for api-type artifacts)
        uat_stop_server

        # Log scenario results before verdict for observability
        local scenario_results_file="results/iteration-${build_iteration}/scenario-results.json"
        collect_scenario_results "$scenario_results_file" || true

        # Phase 6: Write verdict
        write_uat_state "verdict" "$build_iteration" "running"
        uat_phase_verdict "$signal_dir" "$build_iteration" || {
            retry_count=$((retry_count + 1))
            if [[ $retry_count -ge $max_retries ]]; then
                print_error "UAT max retries ($max_retries) exhausted"
                _inline_uat_cleanup
                return 1
            fi
            continue
        }

        # Read verdict
        read_verdict "$signal_dir" || {
            print_error "Failed to read verdict after writing"
            _inline_uat_cleanup
            return 1
        }

        # Process verdict
        if [[ "$__VERDICT_STATUS" == "pass" ]]; then
            write_uat_state "complete" "$build_iteration" "pass"
            print_success "Inline UAT: All $__VERDICT_TOTAL scenarios passed!"
            _uat_print_report "$signal_dir" "$run_start_time"
            _inline_uat_cleanup
            return 0
        fi

        # Check for only disputes remaining
        if [[ "$__VERDICT_FAILED" -eq 0 ]] && [[ "$__VERDICT_ERRORED" -eq 0 ]] && [[ "$__VERDICT_DISPUTED" -gt 0 ]]; then
            write_uat_state "complete" "$build_iteration" "pass"
            print_info "Only disputed scenarios remain — exiting with code 2"
            _uat_print_report "$signal_dir" "$run_start_time"
            _inline_uat_cleanup
            return 2
        fi

        # Failures/errors — extract failing scenarios for retry
        failing_scenarios=$(echo "$__VERDICT_SCENARIOS_JSON" | jq -r '.[] | select(.status == "fail" or .status == "error") | .scenario' 2>/dev/null | tr '\n' '|')
        failing_scenarios="${failing_scenarios%|}"

        retry_count=$((retry_count + 1))
        if [[ $retry_count -ge $max_retries ]]; then
            write_uat_state "failed" "$build_iteration" "fail"
            print_error "UAT max retries ($max_retries) exhausted — $__VERDICT_FAILED failures, $__VERDICT_ERRORED errors remain"
            _uat_print_report "$signal_dir" "$run_start_time"
            _inline_uat_cleanup
            return 1
        fi

        print_warning "Inline UAT: ${__VERDICT_FAILED} failures, ${__VERDICT_ERRORED} errors (retry $retry_count/$max_retries)"
        _uat_print_retry_context "$__VERDICT_SCENARIOS_JSON"

        # cd back to project for rebuild (must happen before write_uat_context
        # which writes .buildcrew/uat-context.md via relative path)
        cd "$project_dir" || { _inline_uat_cleanup; return 1; }

        # Write context for rebuild (cwd must be project_dir)
        write_uat_context "$signal_dir/verdict.json" "$retry_count" "$max_retries" || true

        # Republish, re-bridge, regen harness
        write_uat_state "rebuild" "$build_iteration" "running"
        _uat_republish_and_regen "$task" "$task_complexity" \
            "UAT failure context is in .buildcrew/uat-context.md — read it and fix the issues. Do NOT access the UAT directory or scenarios." \
            || { _inline_uat_cleanup; return 1; }
    done
}

# ─────────────────────────────────────────────────────────────────────────────────
# Phase-Isolated Mode: process_task_isolated
# ─────────────────────────────────────────────────────────────────────────────────

process_task_isolated() {
    local task="$1"
    local task_num="${2:-}"
    local total_tasks="${3:-}"
    local task_complexity="${4:-standard}"
    local plan_ref="${5:-}"
    local __completed_phases=""
    local __is_resuming=false
    local __replan_count=0           # circuit breaker: how many times we've re-planned
    local __need_replan=false        # circuit breaker: set true to restart from research
    local __replan_context=""        # circuit breaker: failure context for re-plan prompt
    local build_attempt=0            # tracks total build attempts across build phases
    local __lesson_instruction
    __lesson_instruction="$(_lesson_writing_instruction)"

    # Snapshot lesson count before task starts (for post-task nudge)
    local __lessons_before=0
    if [[ -f "$LESSONS_FILE" ]]; then
        __lessons_before=$(grep -c '^## Lesson' "$LESSONS_FILE" 2>/dev/null) || __lessons_before=0
    fi

    # Resume or fresh start
    if [[ "$RESUME_MODE" == "true" ]] && load_task_progress; then
        if [[ "$__RESUME_TASK" == "$task" ]] || [[ -z "$task" ]]; then
            task="${__RESUME_TASK}"
            __INVOCATION_COUNT=$__RESUME_INVOCATIONS
            __completed_phases="$__RESUME_PHASES"
            __is_resuming=true
            print_info "Resuming task (invocation count: $__INVOCATION_COUNT)"
            print_debug "Resume state: completed_phases=[$__completed_phases], invocations=$__INVOCATION_COUNT"
        else
            print_warning "Progress file is for a different task — starting fresh"
            clear_task_progress
            __INVOCATION_COUNT=0
        fi
    else
        # Reset global invocation counter for this task
        __INVOCATION_COUNT=0
        clear_task_progress
    fi

    print_info "Running in phase-isolated mode"
    if [[ "$task_complexity" != "standard" ]]; then
        print_info "Complexity profile: $task_complexity (skipping non-essential phases)"
    fi

    if [[ "$__is_resuming" != "true" ]]; then
        # Archive artifacts from any previous task before cleanup
        archive_task_artifacts

        # Clean up artifacts from any previous task
        rm -f "${ARTIFACT_FILES[@]}" "$PHASE_RESULT_FILE" "$STATUS_FILE"
        rm -rf .claude/precompute
    fi

    # Precompute phase metadata for downstream skills
    run_precompute

    # Track current task for future archiving
    mkdir -p .buildcrew
    echo "$task" > "$CURRENT_TASK_FILE"
    __WF_TASK_NUM="$task_num"
    __WF_TOTAL_TASKS="$total_tasks"
    __WF_TASK_NAME="$task"

    # Build plan context from [plan:] reference if available
    local plan_context=""
    if [[ -n "$plan_ref" ]] && [[ -f "$plan_ref" ]]; then
        plan_context="$(printf '\n\n## Discovery Plan Context\n\nThis task was generated from the discovery plan file `%s`. Its contents follow:\n\n```\n%s\n```\n\nUse this plan as starting context for understanding the task scope and intent.' "$plan_ref" "$(cat "$plan_ref")")"
    elif [[ -n "$plan_ref" ]]; then
        plan_context="$(printf '\n\n## Discovery Plan Context\n\nThis task references plan file `%s`, but the file was not found. Proceed based on the task description alone.' "$plan_ref")"
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # Outer loop: supports circuit breaker re-planning
    # ─────────────────────────────────────────────────────────────────────────
    local __outer_iterations=0
    local __spec_reviewed=false  # fires once per task, not on replans
    while true; do
        (( ++__outer_iterations ))
        if (( __outer_iterations > 2 )); then
            print_error "Outer loop safety limit exceeded"
            mark_task_blocked "$task" "Safety: outer loop exceeded 2 iterations"
            return 1
        fi
        if (( __outer_iterations > 1 )); then
            print_debug "Outer loop iteration $__outer_iterations (re-planning)"
        fi
        __need_replan=false

    # --- spec (optional, skipped with --skip-spec) ---
    local __spec_context=""
    local needs_human_review=false
    local hr_reason=""

    # Determine whether spec needs to run
    local __run_spec=false
    local __spec_skill_available=false
    [[ -d ".claude/skills/buildcrew-spec" ]] && __spec_skill_available=true

    if [[ "$SKIP_SPEC" != "true" ]] && [[ "$__spec_skill_available" == "true" ]]; then
        if ! phase_completed "spec"; then
            __run_spec=true
        elif [[ -f ".claude/spec.md" ]]; then
            local ac_count=0
            ac_count=$(grep -c '^- \[ \] AC-' ".claude/spec.md" 2>/dev/null) || ac_count=0
            if (( ac_count < 2 )); then
                print_warning "Resumed spec has only $ac_count AC(s) (minimum 2). Re-running spec phase."
                __run_spec=true
            fi
        fi
    fi

    # Plan-ref skip: if a reviewed plan exists with actionable content, skip spec/research/review
    local __plan_ref_skip=false
    if [[ -n "$plan_ref" ]] && [[ -f "$plan_ref" ]] && grep -qE '(## Implementation|## Acceptance|^[0-9]+\.)' "$plan_ref" 2>/dev/null; then
        __plan_ref_skip=true
        mkdir -p .claude
        cp "$plan_ref" .claude/current-plan.md
    fi

    if [[ "$__plan_ref_skip" == "true" ]]; then
        print_info "Skipping phase: spec (reviewed plan provided: $plan_ref)"
        update_workflow_state "spec" "skipped"
        __spec_context="Implementation plan provided at $plan_ref. No separate spec was generated."
    elif [[ "$SKIP_SPEC" == "true" ]]; then
        print_info "Skipping phase: spec (--skip-spec flag set)"
        update_workflow_state "spec" "skipped"
    elif [[ "$task_complexity" == "trivial" || "$task_complexity" == "simple" ]]; then
        print_info "Skipping phase: spec (complexity: $task_complexity)"
        update_workflow_state "spec" "skipped"
    elif [[ "$__run_spec" == "true" ]]; then
        local _spec_rc=0
        run_phase_group "spec" "$task" "${__replan_context:+Re-planning context: $__replan_context}${plan_context}" "$task_complexity" || _spec_rc=$?
        if [[ $_spec_rc -eq 4 ]]; then return 4; fi
        if [[ $_spec_rc -ne 0 ]]; then mark_task_blocked "$task" "spec phase failed to produce a valid result"; clear_task_progress; return 1; fi

        local spec_verdict
        spec_verdict=$(jq -r '.verdict // "complete"' "$PHASE_RESULT_FILE")
        if [[ "$spec_verdict" == "vague" ]]; then
            local vague_reason
            vague_reason=$(jq -r '.details // "Task too vague"' "$PHASE_RESULT_FILE")
            print_debug "Spec verdict: vague — marking task blocked"
            mark_task_blocked "$task" "$vague_reason"
            clear_task_progress
            print_warning "Task flagged as too vague to spec. See .claude/spec.md for details."
            return 1
        elif [[ "$spec_verdict" == "needs_probing" ]]; then
            handle_spec_interview "$task" || { mark_task_blocked "$task" "$(jq -r '.details // "spec interview failed"' "$PHASE_RESULT_FILE" 2>/dev/null || echo "spec interview failed")"; clear_task_progress; return 1; }
        fi

        __spec_context="Specification available at .claude/spec.md — read it for acceptance criteria and scope boundaries."

        # Validate AC count meets minimum (2 required)
        local ac_count=0
        if [[ -f ".claude/spec.md" ]]; then
            ac_count=$(grep -c '^- \[ \] AC-' ".claude/spec.md" 2>/dev/null) || ac_count=0
        fi
        if (( ac_count < 2 )); then
            print_warning "Spec has only $ac_count acceptance criteria (minimum 2). Re-running spec phase."
            local _spec_ac_rc=0
            run_phase_group "spec" "$task" \
                "RETRY: Previous spec had only $ac_count acceptance criteria. Minimum is 2 concrete, testable acceptance criteria. Read .claude/spec.md and add more specific ACs.${plan_context}" \
                "$task_complexity" || _spec_ac_rc=$?
            if [[ $_spec_ac_rc -eq 4 ]]; then return 4; fi
            if [[ $_spec_ac_rc -ne 0 ]]; then mark_task_blocked "$task" "spec phase failed to produce a valid result on AC retry"; clear_task_progress; return 1; fi
            # Re-validate
            ac_count=$(grep -c '^- \[ \] AC-' ".claude/spec.md" 2>/dev/null) || ac_count=0
            if (( ac_count < 2 )); then
                mark_task_blocked "$task" "Spec produced only $ac_count acceptance criteria after retry (minimum 2)"
                clear_task_progress
                return 1
            fi
        fi

        # Spec review — fires once per task (not on circuit-breaker replans)
        if [[ "$__spec_reviewed" == "false" ]]; then
            local spec_review_exit=0
            handle_spec_review "$task" "$ac_count" "$task_num" "$total_tasks" || spec_review_exit=$?
            if [[ $spec_review_exit -eq 1 ]]; then
                mark_task_blocked "$task" "Skipped during spec review"
                clear_task_progress
                return 1
            elif [[ $spec_review_exit -eq 2 ]]; then
                touch "$STOP_FILE"
                mark_task_blocked "$task" "Pipeline stopped during spec review"
                clear_task_progress
                return 1
            fi
            __spec_reviewed=true
        fi

        __completed_phases="${__completed_phases:+$__completed_phases }spec"
        save_task_progress "$task" "$__completed_phases" "$__INVOCATION_COUNT"
    elif [[ "$__spec_skill_available" == "true" ]] && phase_completed "spec"; then
        print_info "Skipping phase: spec (completed in previous run)"
        update_workflow_state "spec" "skipped"
        if [[ -f ".claude/spec.md" ]]; then
            __spec_context="Specification available at .claude/spec.md — read it for acceptance criteria."
        fi
    fi
    # If spec skill is not installed, fall through silently (no message, no context set)

    # --- prereqs (optional, skipped with --skip-prereqs or when skill not installed) ---
    if [[ -d ".claude/skills/buildcrew-prereqs" ]]; then
        if [[ "$SKIP_PREREQS" == "true" ]]; then
            print_info "Skipping phase: prereqs (--skip-prereqs flag set)"
            update_workflow_state "prereqs" "skipped"
        elif phase_completed "prereqs"; then
            print_info "Skipping phase: prereqs (completed in previous run)"
            update_workflow_state "prereqs" "skipped"
        else
            local prereqs_extra="${__spec_context}"
            if [[ "$AUTO_MODE" == "true" ]]; then
                prereqs_extra="${prereqs_extra:+$prereqs_extra | }AUTO MODE: report warnings only, do not block"
            fi
            run_phase_group "prereqs" "$task" "$prereqs_extra" "$task_complexity" || { mark_task_blocked "$task" "prereqs phase failed to produce a valid result"; clear_task_progress; return 1; }

            local prereqs_verdict
            prereqs_verdict=$(jq -r '.verdict // "complete"' "$PHASE_RESULT_FILE")
            case "$prereqs_verdict" in
                complete|skipped)
                    __completed_phases="${__completed_phases:+$__completed_phases }prereqs"
                    save_task_progress "$task" "$__completed_phases" "$__INVOCATION_COUNT"
                    ;;
                blocked)
                    mark_task_blocked "$task" "Unmet prerequisites — run with --skip-prereqs to bypass"
                    clear_task_progress
                    return 1
                    ;;
                *)
                    mark_task_blocked "$task" "prereqs phase returned unknown verdict: $prereqs_verdict"
                    clear_task_progress
                    return 1
                    ;;
            esac
        fi
    fi

    # --- research + plan ---
    if [[ "$__plan_ref_skip" == "true" ]]; then
        print_info "Skipping phase: research (reviewed plan provided: $plan_ref)"
        update_workflow_state "research" "skipped"
    elif phase_completed "research"; then
        print_info "Skipping phase: research (completed in previous run)"
        update_workflow_state "research" "skipped"
    elif [[ "$task_complexity" == "trivial" ]]; then
        print_info "Skipping phase: research (complexity: trivial)"
        update_workflow_state "research" "skipped"
        if [[ "$HUMAN_REVIEW" == "true" ]]; then
            print_info "Note: --review has no effect for trivial tasks (research and review phases are skipped)"
        fi
    else
        local research_extra="${__spec_context}"
        if [[ -n "$__replan_context" ]]; then
            research_extra="${research_extra:+$research_extra | }REPLAN: $__replan_context"
        fi
        if [[ "$task_complexity" == "standard" ]]; then
            research_extra="${research_extra:+$research_extra | }TDD MODE: Tests will be written BEFORE implementation. Your plan MUST include a section documenting public interface contracts (function signatures, CLI commands, API endpoints) with enough detail that tests can be written against them before any code exists. Mark any areas that cannot be tested before implementation (visual, perf) as TDD-exempt."
        fi
        local _research_rc=0
        run_phase_group "research" "$task" "$research_extra" "$task_complexity" || _research_rc=$?
        if [[ $_research_rc -eq 4 ]]; then return 4; fi
        if [[ $_research_rc -ne 0 ]]; then mark_task_blocked "$task" "research phase failed to produce a valid result"; clear_task_progress; return 1; fi
        __completed_phases="${__completed_phases:+$__completed_phases }research"
        save_task_progress "$task" "$__completed_phases" "$__INVOCATION_COUNT"

        # Extract AI-recommended review signal — acted upon at the consolidated pre-build gate
        if [[ -f "$PHASE_RESULT_FILE" ]] && jq -e '.human_review == true' "$PHASE_RESULT_FILE" >/dev/null 2>&1; then
            needs_human_review=true
            hr_reason=$(jq -r '.human_review_reason // "AI recommended review"' "$PHASE_RESULT_FILE")
        fi
    fi

    # --- plan-review (max 3 external cycles, circuit breaker at 2 consecutive failures) ---
    if [[ "$__plan_ref_skip" == "true" ]]; then
        print_info "Skipping phase: review (reviewed plan provided: $plan_ref)"
        update_workflow_state "review" "skipped"
    elif phase_completed "review"; then
        print_info "Skipping phase: review (completed in previous run)"
        update_workflow_state "review" "skipped"
    elif [[ "$task_complexity" == "trivial" || "$task_complexity" == "simple" ]]; then
        print_info "Skipping phase: review (complexity: $task_complexity)"
        update_workflow_state "review" "skipped"
        # Simple tasks skip review but DO run research, so a plan exists.
        # Fire the consolidated plan review gate here (trivial tasks have no plan, so skip them).
        if [[ "$task_complexity" == "simple" ]]; then
            local hr_exit=0
            if [[ "$needs_human_review" == "true" ]]; then
                handle_plan_review "$task" "Plan ready (review skipped for simple task) — $hr_reason" "--force" || hr_exit=$?
            elif [[ "$HUMAN_REVIEW" == "true" ]]; then
                handle_plan_review "$task" "Plan ready (review skipped for simple task) — review before build" || hr_exit=$?
            fi
            if [[ $hr_exit -eq 1 ]]; then
                mark_task_blocked "$task" "Skipped during plan review"
                clear_task_progress
                return 1
            elif [[ $hr_exit -eq 2 ]]; then
                touch "$STOP_FILE"
                mark_task_blocked "$task" "Pipeline stopped during plan review"
                clear_task_progress
                return 1
            fi
        fi
    else
        local plan_review_cycle=0
        local consecutive_review_failures=0
        local prev_review_details=""
        while true; do
            ((plan_review_cycle++))
            local review_extra="Plan review cycle $plan_review_cycle (max 2 before re-planning)"
            if [[ -n "$__spec_context" ]]; then
                review_extra="$review_extra | $__spec_context"
            fi
            if (( plan_review_cycle > 1 )) && [[ -f ".claude/plan-review-prev.md" ]]; then
                review_extra="$review_extra | REVISION CYCLE: Previous review findings are in .claude/plan-review-prev.md — focus on whether those issues were addressed. Previous details: $prev_review_details"
            fi
            local _review_rc=0
            run_phase_group "review" "$task" "$review_extra" "$task_complexity" || _review_rc=$?
            if [[ $_review_rc -eq 4 ]]; then return 4; fi
            if [[ $_review_rc -ne 0 ]]; then mark_task_blocked "$task" "review phase failed to produce a valid result"; clear_task_progress; return 1; fi

            local verdict
            verdict=$(jq -r '.verdict' "$PHASE_RESULT_FILE")
            case "$verdict" in
                approved)
                    consecutive_review_failures=0
                    local hr_exit=0
                    if [[ "$needs_human_review" == "true" ]]; then
                        handle_plan_review "$task" "Plan approved — $hr_reason" "--force" || hr_exit=$?
                    elif [[ "$HUMAN_REVIEW" == "true" ]]; then
                        handle_plan_review "$task" "Plan approved — review before build" || hr_exit=$?
                    fi
                    if [[ $hr_exit -eq 1 ]]; then
                        mark_task_blocked "$task" "Skipped during plan review"
                        clear_task_progress
                        return 1
                    elif [[ $hr_exit -eq 2 ]]; then
                        touch "$STOP_FILE"
                        mark_task_blocked "$task" "Pipeline stopped during plan review"
                        clear_task_progress
                        return 1
                    fi
                    break ;;
                rejected)
                    append_lesson "review" \
                        "Plan rejected after $plan_review_cycle cycle(s)" \
                        "Task marked blocked due to fundamental plan issues" \
                        "Ensure plans are grounded in actual codebase patterns before review"
                    mark_task_blocked "$task" "Plan rejected"
                    clear_task_progress
                    return 1 ;;
                needs_revision)
                    ((consecutive_review_failures++))
                    if (( consecutive_review_failures >= 2 )); then
                        # Circuit breaker: plan is not converging
                        local failure_summary
                        failure_summary=$(jq -r '.details // "Plan failed to converge after 2 revision cycles"' "$PHASE_RESULT_FILE")
                        print_warning "[CIRCUIT BREAKER] Approach failed twice at Plan Review phase. Re-planning from scratch with failure context."
                        print_debug "Circuit breaker: consecutive_failures=$consecutive_review_failures, replan_count=$__replan_count"
                        append_lesson "review" \
                            "Plan failed to converge after $plan_review_cycle cycles: $failure_summary" \
                            "Triggered circuit breaker and re-planned from scratch" \
                            "Start from a different architectural approach when plan review rejects the same issues twice"
                        if ! __check_replan_limit "$task" "Circuit breaker: plan failed twice even after re-planning"; then
                            rm -f .claude/plan-review-prev.md .claude/review-lens1-prev.md .claude/review-lens2-prev.md .claude/review-lens3-prev.md
                            return 1
                        fi
                        __trigger_replan "CIRCUIT BREAKER: Plan review failed twice. Previous approach: $failure_summary. Knowing everything you know now, scrap this and implement the elegant solution."
                        rm -f .claude/plan-review-prev.md .claude/review-lens1-prev.md .claude/review-lens2-prev.md .claude/review-lens3-prev.md
                        break
                    fi
                    prev_review_details=$(jq -r '.details // ""' "$PHASE_RESULT_FILE")
                    [[ -f ".claude/plan-review.md" ]] && cp .claude/plan-review.md .claude/plan-review-prev.md
                    [[ -f ".claude/review-lens1.md" ]] && cp .claude/review-lens1.md .claude/review-lens1-prev.md
                    [[ -f ".claude/review-lens2.md" ]] && cp .claude/review-lens2.md .claude/review-lens2-prev.md
                    [[ -f ".claude/review-lens3.md" ]] && cp .claude/review-lens3.md .claude/review-lens3-prev.md
                    ;;
                *) mark_task_blocked "$task" "Unexpected plan review verdict: $verdict"; clear_task_progress; return 1 ;;
            esac
        done

        if [[ "$__need_replan" == "true" ]]; then
            continue  # restart outer while loop
        fi

        __completed_phases="${__completed_phases:+$__completed_phases }review"
        save_task_progress "$task" "$__completed_phases" "$__INVOCATION_COUNT"
    fi

    # --- tdd-scaffold (standard complexity) ---
    if [[ "$task_complexity" == "standard" ]]; then
        if phase_completed "tdd-scaffold"; then
            print_info "Skipping phase: tdd-scaffold (completed in previous run)"
            update_workflow_state "tdd-scaffold" "skipped"
        else
            local tdd_context="$__spec_context"
            local _tdd_rc=0
            run_phase_group "tdd-scaffold" "$task" "$tdd_context" "$task_complexity" || _tdd_rc=$?
            if [[ $_tdd_rc -eq 4 ]]; then return 4; fi
            if [[ $_tdd_rc -ne 0 ]]; then mark_task_blocked "$task" "tdd-scaffold phase failed"; clear_task_progress; return 1; fi
            local tdd_verdict
            tdd_verdict=$(jq -r '.verdict // "unknown"' "$PHASE_RESULT_FILE")
            case "$tdd_verdict" in
                complete)
                    print_info "TDD scaffold complete — failing tests written"
                    if ! __validate_tdd_scaffold; then
                        print_warning "TDD scaffold produced passing tests — treating as blocked"
                        mark_task_blocked "$task" "TDD scaffold invalid: tests pass before build"
                        clear_task_progress; return 1
                    fi
                    ;;
                blocked)  print_warning "TDD scaffold blocked — proceeding without TDD" ;;
                *) mark_task_blocked "$task" "Unexpected tdd-scaffold verdict: $tdd_verdict"
                   clear_task_progress; return 1 ;;
            esac
            __completed_phases="${__completed_phases:+$__completed_phases }tdd-scaffold"
            save_task_progress "$task" "$__completed_phases" "$__INVOCATION_COUNT"
        fi
    else
        print_info "Skipping phase: tdd-scaffold (complexity: $task_complexity)"
        update_workflow_state "tdd-scaffold" "skipped"
    fi

    # --- build → codereview (with rebuild loop, circuit breaker) ---
    if phase_completed "build"; then
        print_info "Skipping phase: build+codereview (completed in previous run)"
        update_workflow_state "build" "skipped"
    else
        local consecutive_build_failures=0
        while true; do
            ((build_attempt++))
            print_debug "Build attempt $build_attempt"

            local build_context=""
            if [[ -n "$__spec_context" ]]; then
                build_context="$__spec_context"
            fi
            if (( build_attempt > 1 )); then
                local prev_reason
                prev_reason=$(jq -r '.details // "unknown"' "$PHASE_RESULT_FILE")
                build_context="${build_context:+$build_context | }This is build attempt $build_attempt. Previous attempt failed: $prev_reason. Avoid the same mistakes."
                build_context="$build_context"$'\n\n'"$__lesson_instruction"
                # Inject code-review feedback so the build agent knows what to fix
                if [[ -f ".claude/code-review.md" ]]; then
                    local cr_feedback
                    cr_feedback=$(head -80 ".claude/code-review.md")
                    build_context="$build_context"$'\n\n'"## Code Review Feedback (from previous attempt)"$'\n'"$cr_feedback"
                fi
            fi

            # Ensure stale TDD locks are cleared before each build attempt
            __unlock_tdd_files

            local build_result=0
            __with_tdd_lock run_phase_group "build" "$task" "$build_context" "$task_complexity" || build_result=$?

            if [[ $build_result -eq 4 ]]; then
                return 4
            elif [[ $build_result -eq 2 ]]; then
                print_info "Build hit max-turns. Switching to chunked build."
                local chunked_result=0
                __with_tdd_lock run_chunked_build "$task" "$__spec_context" "$task_complexity" || chunked_result=$?
                if [[ $chunked_result -eq 4 ]]; then
                    return 4
                elif [[ $chunked_result -ne 0 ]]; then
                    local block_reason="Chunked build failed"
                    [[ $chunked_result -eq 2 ]] && block_reason="Build step too large even for chunked execution"
                    mark_task_blocked "$task" "$block_reason"
                    clear_task_progress; return 1
                fi
            elif [[ $build_result -ne 0 ]]; then
                mark_task_blocked "$task" "build phase failed to produce a valid result"
                clear_task_progress; return 1
            fi

            # --- docs (non-blocking) ---
            if [[ "$task_complexity" != "trivial" && "$task_complexity" != "simple" ]]; then
                run_optional_docs "$task" "${__spec_context}"
            fi


            # --- code review (independent phase) ---
            local cr_verdict
            if [[ "$task_complexity" == "trivial" || "$task_complexity" == "simple" ]]; then
                print_info "Skipping phase: codereview (complexity: $task_complexity)"
                update_workflow_state "codereview" "skipped"
                cr_verdict="approved"
            else
                local _cr_rc=0
                run_phase_group "codereview" "$task" "${__spec_context}" "$task_complexity" || _cr_rc=$?
                if [[ $_cr_rc -eq 4 ]]; then return 4; fi
                if [[ $_cr_rc -ne 0 ]]; then mark_task_blocked "$task" "codereview phase failed to produce a valid result"; clear_task_progress; return 1; fi
                cr_verdict=$(jq -r '.verdict' "$PHASE_RESULT_FILE")
            fi
            case "$cr_verdict" in
                approved)
                    consecutive_build_failures=0
                    break
                    ;;
                needs_rebuild)
                    ((consecutive_build_failures++))
                    if (( consecutive_build_failures >= 2 )); then
                        local failure_summary
                        failure_summary=$(jq -r '.details // "Code review failed twice"' "$PHASE_RESULT_FILE")
                        print_warning "[CIRCUIT BREAKER] Approach failed twice at Code Review phase. Re-planning from scratch with failure context."
                        print_debug "Circuit breaker: consecutive_failures=$consecutive_build_failures, replan_count=$__replan_count"
                        append_lesson "build" \
                            "Code review NEEDS_REBUILD after $build_attempt attempts: $failure_summary" \
                            "Triggered circuit breaker and re-planned from scratch" \
                            "When code review rejects twice on the same approach, the plan itself is likely flawed — re-plan rather than retry"
                        if ! __check_replan_limit "$task" "Circuit breaker: code review failed twice even after re-planning"; then
                            return 1
                        fi
                        __trigger_replan "CIRCUIT BREAKER: Code review NEEDS_REBUILD twice. Previous failure: $failure_summary. Knowing everything you know now, scrap this and implement the elegant solution."
                        break
                    fi
                    local cr_fail_details
                    cr_fail_details=$(jq -r '.details // "Code review NEEDS_REBUILD"' "$PHASE_RESULT_FILE")
                    append_lesson "build" \
                        "Code review NEEDS_REBUILD on attempt $build_attempt: $cr_fail_details" \
                        "Retrying build with revised approach" \
                        "Read code review carefully before retrying — the issues usually indicate a misunderstanding of the existing codebase"
                    continue ;;
                *)
                    mark_task_blocked "$task" "Unexpected codereview verdict: $cr_verdict"
                    clear_task_progress
                    return 1 ;;
            esac
        done

        if [[ "$__need_replan" == "true" ]]; then
            continue  # restart outer while loop
        fi

        __completed_phases="${__completed_phases:+$__completed_phases }build"
        save_task_progress "$task" "$__completed_phases" "$__INVOCATION_COUNT"
    fi

    # --- verify + commit (never skipped — always re-verify) ---
    # The verify SKILL runs 3 parallel sub-agents: security audit, test suite, AC verification.
    local verify_attempt=0
    local consecutive_verify_failures=0
    while true; do
        ((verify_attempt++))

        local verify_extra="${__spec_context}"
        local _verify_rc=0
        run_phase_group "verify" "$task" "$verify_extra" "$task_complexity" || _verify_rc=$?
        if [[ $_verify_rc -eq 4 ]]; then return 4; fi
        if [[ $_verify_rc -ne 0 ]]; then mark_task_blocked "$task" "verify phase failed to produce a valid result"; clear_task_progress; return 1; fi

        local verdict
        verdict=$(jq -r '.verdict' "$PHASE_RESULT_FILE")
        case "$verdict" in
            complete) break ;;
            blocked)
                ((consecutive_verify_failures++))
                local failing
                failing=$(jq -r '.failing_check // "unknown"' "$PHASE_RESULT_FILE")
                local failure_details
                failure_details=$(jq -r '.details // "unknown"' "$PHASE_RESULT_FILE")

                if (( consecutive_verify_failures >= 2 )); then
                    print_warning "[CIRCUIT BREAKER] Approach failed twice at Verify phase ($failing). Re-planning from scratch."
                    print_debug "Circuit breaker: consecutive_failures=$consecutive_verify_failures, replan_count=$__replan_count"
                    append_lesson "verify" \
                        "Verification blocked twice on '$failing': $failure_details" \
                        "Triggered circuit breaker and re-planned from scratch" \
                        "When verification fails twice on the same check, the build approach itself is wrong — re-plan"
                    if ! __check_replan_limit "$task" "Circuit breaker: verification failed twice even after re-planning"; then
                        return 1
                    fi
                    __trigger_replan "CIRCUIT BREAKER: Verification failed twice on '$failing': $failure_details. Knowing everything you know now, scrap this and implement the elegant solution."
                    break
                fi

                case "$failing" in
                    tests|security)
                        local rebuild_context
                        rebuild_context=$(build_verify_failure_context "$failing")
                        print_debug "Verify rebuild context: $rebuild_context"
                        append_lesson "verify" \
                            "Verify blocked on '$failing': $failure_details" \
                            "Rebuilt with targeted fix for $failing issues" \
                            "Always run the full verify check before considering a build complete"
                        local _rebuild_rc=0
                        run_phase_group "build" "$task" "$rebuild_context"$'\n\n'"$__lesson_instruction" "$task_complexity" || _rebuild_rc=$?
                        if [[ $_rebuild_rc -eq 4 ]]; then return 4; fi
                        if [[ $_rebuild_rc -ne 0 ]]; then mark_task_blocked "$task" "build phase failed during verify fix"; clear_task_progress; return 1; fi
                        if [[ "$task_complexity" == "trivial" || "$task_complexity" == "simple" ]]; then
                            cr_verdict="approved"
                        else
                            run_optional_docs "$task" "${__spec_context}"
                            local _rebuild_cr_rc=0
                            run_phase_group "codereview" "$task" "${__spec_context}" "$task_complexity" || _rebuild_cr_rc=$?
                            if [[ $_rebuild_cr_rc -eq 4 ]]; then return 4; fi
                            if [[ $_rebuild_cr_rc -ne 0 ]]; then mark_task_blocked "$task" "codereview phase failed to produce a valid result"; clear_task_progress; return 1; fi
                            cr_verdict=$(jq -r '.verdict' "$PHASE_RESULT_FILE")
                        fi
                        if [[ "$cr_verdict" == "needs_rebuild" ]]; then
                            mark_task_blocked "$task" "Code review rejected rebuild at verify stage"
                            clear_task_progress; return 1
                        fi
                        ;;
                    *)
                        mark_task_blocked "$task" "Verification blocked: $failing"
                        clear_task_progress
                        return 1
                        ;;
                esac
                ;;
            *) mark_task_blocked "$task" "Unexpected verify verdict: $verdict"; clear_task_progress; return 1 ;;
        esac
    done

    if [[ "$__need_replan" == "true" ]]; then
        continue  # restart outer while loop
    fi

    # Task succeeded — exit the outer while loop
    break

    done  # end of outer re-planning while loop

    # Task succeeded
    clear_task_progress
    rm -f "$CURRENT_TASK_FILE"
    mark_task_complete "$task"
    _check_lessons_nudge "$__lessons_before"
    local summary
    summary=$(jq -r '.summary // "Completed"' "$STATUS_FILE" 2>/dev/null || echo "Completed")
    print_success "Completed: $task"
    print_info "Summary: $summary"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Main workflow
# ─────────────────────────────────────────────────────────────────────────────────

main() {
    # Lockfile: prevent concurrent runs (check early, create after worktree check)
    if [[ -f "$LOCKFILE" ]]; then
        local existing_pid
        existing_pid=$(cat "$LOCKFILE" 2>/dev/null)
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            print_error "Another BuildCrew workflow is already running (PID $existing_pid)"
            print_info "If this is stale, remove $LOCKFILE"
            exit 1
        fi
        # Stale lockfile — previous run crashed
        rm -f "$LOCKFILE"
    fi

    if [[ "$PLAN_MODE" == "true" ]]; then
        # Validate flag compatibility
        if [[ "$SINGLE_TASK" == "true" ]] || [[ -n "$TARGET_TASK" ]]; then
            print_error "--plan cannot be combined with --single or --task"
            exit 1
        fi
        if [[ "$RESUME_MODE" == "true" ]]; then
            print_error "--plan cannot be combined with --resume"
            exit 1
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY RUN] Would enter discovery mode (interactive planning)"
            exit 0
        fi

        # Check prerequisites inline
        if ! command -v claude &>/dev/null; then
            print_error "Claude Code CLI not found. Please install it first."
            exit 1
        fi

        local plan_prompt
        if has_project_file; then
            plan_prompt="Run /build to add new tasks to this project."
        else
            plan_prompt="Run /build to help define this project and create a backlog."
        fi
        enter_discovery_mode "$plan_prompt"
        # enter_discovery_mode calls exit 0, never returns
    fi

    if [[ "$SEQUENTIAL_MODE" != "true" ]]; then
        # Parallel batch mode (default execution path)

        # 1. Advisory: --branch has no effect in parallel mode
        if [[ "$GIT_BRANCH" == "true" ]]; then
            print_warning "--branch has no effect in parallel mode (worktree branches are automatic). Use --sequential --branch for manual PR workflow."
        fi

        # 2. Check for claude and jq
        if ! command -v claude &>/dev/null; then
            print_error "Claude Code CLI not found. Please install it first."
            exit 1
        fi
        if ! command -v jq &>/dev/null; then
            print_error "jq not found. Please install it (brew install jq)"
            exit 1
        fi

        # 3. Detect git repo (required for standard mode, optional for non-git parent)
        if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
            __BATCH_PARENT_IS_GIT=true
            # 4. Working tree must be clean (only when parent is a git repo)
            if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
                print_error "Working tree is not clean. Commit or stash changes first, or use --sequential."
                exit 1
            fi
        else
            __BATCH_PARENT_IS_GIT=false
            # Auto-fallback: non-git dirs without [dir:] prefixes can't use worktrees
            if [[ -z "$TARGET_DIR" ]]; then
                local _has_dir_prefix=false
                if [[ -f "$BACKLOG_FILE" ]] && grep -q '^\- \[ \] .*\[dir:' "$BACKLOG_FILE" 2>/dev/null; then
                    _has_dir_prefix=true
                fi
                if [[ "$_has_dir_prefix" != "true" ]]; then
                    print_info "Non-git directory without [dir:...] prefixes — falling back to sequential mode."
                    SEQUENTIAL_MODE=true
                fi
            fi
        fi
    fi

    # After potential auto-fallback, check if we're still in parallel mode
    if [[ "$SEQUENTIAL_MODE" != "true" ]]; then
        # Non-git parent info message (when target dirs exist)
        if [[ "$__BATCH_PARENT_IS_GIT" == "false" ]]; then
            print_info "Non-git parent directory detected. Tasks must specify target directories via [dir:...] or TARGET_DIR config."
        fi

        # 5. Resume mode with auto-detection
        if [[ "$RESUME_MODE" == "true" ]]; then
            mkdir -p .buildcrew
            log_init
            echo $$ > "$LOCKFILE"
            local _has_manifest=false
            local _has_progress=false
            [[ -f "$BATCH_MANIFEST" ]] && _batch_load_manifest 2>/dev/null && _has_manifest=true
            [[ -f "$PROGRESS_FILE" ]] && _has_progress=true

            if [[ "$_has_manifest" == "true" && "$_has_progress" == "true" ]]; then
                # Both exist — use more recent
                local _manifest_mtime _progress_mtime
                _manifest_mtime=$(stat -f %m "$BATCH_MANIFEST" 2>/dev/null || stat -c %Y "$BATCH_MANIFEST" 2>/dev/null || echo 0)
                _progress_mtime=$(stat -f %m "$PROGRESS_FILE" 2>/dev/null || stat -c %Y "$PROGRESS_FILE" 2>/dev/null || echo 0)
                if [[ "$_manifest_mtime" -ge "$_progress_mtime" ]]; then
                    print_info "Found both sequential and batch progress — resuming the more recent one (batch). Use --sequential to force sequential resume."
                    _batch_resume
                else
                    print_info "Found both sequential and batch progress — resuming the more recent one (sequential). Use --sequential to force sequential resume."
                    SEQUENTIAL_MODE=true
                    # Fall through to sequential path below
                fi
            elif [[ "$_has_manifest" == "true" ]]; then
                print_info "Resuming batch from $BATCH_MANIFEST"
                _batch_resume
            elif [[ "$_has_progress" == "true" ]]; then
                print_info "Detected sequential progress file — resuming in sequential mode."
                SEQUENTIAL_MODE=true
                # Fall through to sequential path below
            else
                print_error "No resumable run found (no batch manifest or sequential progress file)"
                exit 1
            fi
            # _batch_resume calls exit 0 if it ran; if we fall through, sequential handles it
        fi
    fi

    # Final check: if we fell through resume auto-detection into sequential mode
    if [[ "$SEQUENTIAL_MODE" != "true" ]]; then
        # 6. Discovery mode fallback (empty/complete backlogs)
        if is_fresh_backlog; then
            print_info "Empty backlog. Launching discovery mode..."
            echo ""
            enter_discovery_mode "Run /build to help define this project and create a backlog."
        fi
        if is_completed_phase; then
            print_info "All tasks complete! Launching discovery mode to add scope..."
            echo ""
            enter_discovery_mode "Run /build to add new tasks to this project."
        fi

        # 7. Gather and validate pending tasks
        gather_pending_tasks
        if [[ "$__BATCH_TASK_COUNT" -eq 0 ]]; then
            print_error "No pending tasks in $BACKLOG_FILE"
            exit 1
        fi
        local task_list="$__BATCH_TASK_LIST"

        # 8. Advisory messages
        if [[ "$__BATCH_TASK_COUNT" -eq 1 ]]; then
            print_info "Only 1 pending task -- batch mode will still work, but sequential mode may be more thorough"
        fi

        # 9. Dry-run support
        if [[ "$DRY_RUN" == "true" ]]; then
            print_header "Parallel Mode (Dry Run)"
            print_info "Would process $__BATCH_TASK_COUNT tasks in parallel (max $MAX_PARALLEL concurrent):"
            echo ""
            echo "$task_list"
            echo ""
            exit 0
        fi

        # 10. Setup and execute
        print_info "Running in parallel mode (unattended). Use --sequential for interactive mode."
        mkdir -p .buildcrew
        log_init
        log_msg "Batch mode: $__BATCH_TASK_COUNT tasks, max_parallel=$MAX_PARALLEL"
        print_info "Activity log: $__LOG_FILE"
        echo $$ > "$LOCKFILE"
        print_debug "Flags: verbose=$VERBOSE auto=$AUTO_MODE max_parallel=$MAX_PARALLEL"

        enter_batch_mode "$task_list"
        # enter_batch_mode calls exit 0, control does not return here
    fi

    check_prerequisites
    check_context_health

    # Clear any previous stop signal
    clear_stop_signal

    print_header "BuildCrew - Autonomous Development Pipeline"
    print_info "To stop after the current task: buildcrew stop"

    # Require phase-isolated skills (installed via buildcrew init)
    if ! is_phase_isolation_available; then
        error "Phase-isolated skills not found. Run 'buildcrew init' to install them."
    fi

    if [[ "$COMPLEXITY_AWARE" == "true" ]] && [[ "$FULL_PIPELINE" != "true" ]]; then
        print_info "Mode: Phase-isolated (complexity-aware: 2-8 invocations per task, TDD enabled)"
    else
        local _phase_count=5
        [[ "$SKIP_SPEC" != "true" ]] && [[ -d ".claude/skills/buildcrew-spec" ]] && _phase_count=$((_phase_count + 1))
        [[ "$SKIP_PREREQS" != "true" ]] && [[ -d ".claude/skills/buildcrew-prereqs" ]] && _phase_count=$((_phase_count + 1))
        [[ -d ".claude/skills/buildcrew-docs" ]] && _phase_count=$((_phase_count + 1))
        [[ -d ".claude/skills/buildcrew-tdd-scaffold" ]] && _phase_count=$((_phase_count + 1))
        print_info "Mode: Phase-isolated ($_phase_count invocations per task)"
    fi
    print_debug "Flags: skip_spec=$SKIP_SPEC skip_prereqs=$SKIP_PREREQS review=$HUMAN_REVIEW branch=$GIT_BRANCH resume=$RESUME_MODE full_pipeline=$FULL_PIPELINE complexity_aware=$COMPLEXITY_AWARE auto=$AUTO_MODE"

    # Git branch setup
    if [[ "$GIT_BRANCH" == "true" ]]; then
        if ! save_original_branch; then
            print_error "Cannot use --branch: not a git repository or cannot determine branch"
            exit 1
        fi
        if ! ensure_clean_worktree; then
            exit 1
        fi
        print_info "Branch mode: each task gets a feature branch from '$ORIGINAL_BRANCH'"

        # Check for remote
        if git remote get-url origin >/dev/null 2>&1; then
            HAS_REMOTE=true
            # Check for gh CLI
            if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
                GH_AVAILABLE=true
            else
                print_warning "gh CLI not available or not authenticated — branches will be pushed but PRs must be created manually"
            fi
        else
            print_warning "No remote configured — branches will be created locally but cannot be pushed or PRed"
        fi
    fi

    # Create lockfile now (after worktree check, so --branch mode sees clean tree)
    mkdir -p .buildcrew
    log_init
    log_msg "Flags: skip_spec=$SKIP_SPEC skip_prereqs=$SKIP_PREREQS review=$HUMAN_REVIEW branch=$GIT_BRANCH resume=$RESUME_MODE full_pipeline=$FULL_PIPELINE complexity_aware=$COMPLEXITY_AWARE auto=$AUTO_MODE"
    print_info "Activity log: $__LOG_FILE"
    echo $$ > "$LOCKFILE"
    trap cleanup EXIT INT TERM

    local completed=0
    local failed=0
    local start_time
    start_time=$(date +%s)
    local total_tasks
    total_tasks=$(count_tasks pending)
    __WF_TOTAL_TASKS="$total_tasks"
    local task_num=0

    # Show initial status
    print_info "Backlog status:"
    echo "  Pending:   $(count_tasks pending)"
    echo "  Completed: $(count_tasks completed)"
    echo "  Blocked:   $(count_tasks blocked)"

    # Task targeting pre-check
    if [[ -n "$TARGET_TASK" ]]; then
        SINGLE_TASK=true
        print_info "Task targeting: --task '$TARGET_TASK'"
    fi

    # Resume mode pre-check
    if [[ "$RESUME_MODE" == "true" ]]; then
        if [[ ! -f "$PROGRESS_FILE" ]]; then
            print_info "No interrupted task found. Starting normally."
            RESUME_MODE=false
        else
            SINGLE_TASK=true
            print_info "Resume mode: will process one task and exit"
        fi
    fi

    # Track dry-run progress (since dry-run doesn't modify the backlog)
    local dry_run_remaining=0
    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run_remaining=$(count_tasks pending)
    fi

    while true; do
        # Check for stop signal
        if check_stop_signal; then
            handle_stop
            break
        fi

        # Get next task (or targeted task)
        local task
        if [[ -n "$TARGET_TASK_EXACT" ]]; then
            # Exact task text provided (e.g., from batch child) — use directly, skip backlog search
            task="$TARGET_TASK_EXACT"
            TARGET_TASK_EXACT=""
        elif [[ -n "$TARGET_TASK" ]]; then
            task=$(get_task_by_target "$TARGET_TASK")
            if [[ -z "$task" ]]; then
                print_error "No pending task matching '$TARGET_TASK'"
                break
            fi
            # Clear so subsequent iterations (shouldn't happen with SINGLE_TASK) use normal order
            TARGET_TASK=""
        else
            task=$(get_next_task)
        fi

        if [[ -z "$task" ]]; then
            break
        fi

        # Extract and strip [plan:] annotation before complexity assessment
        local plan_ref=""
        plan_ref=$(extract_task_plan_ref "$task")
        task=$(strip_task_plan_ref "$task")

        # Assess complexity and strip tag before processing
        local task_complexity="standard"
        if [[ "$FULL_PIPELINE" != "true" ]] && [[ "$COMPLEXITY_AWARE" == "true" ]]; then
            task_complexity=$(assess_task_complexity "$task")
        fi
        task=$(strip_task_tag "$task")

        print_task_start "$task"

        if [[ "$DRY_RUN" == "true" ]]; then
            if [[ "$GIT_BRANCH" == "true" ]]; then
                print_info "[DRY RUN] Would create branch: $(task_to_branch_name "$task")"
            fi
            if [[ "$RESUME_MODE" == "true" ]] && [[ -f "$PROGRESS_FILE" ]]; then
                local skip_phases
                skip_phases=$(jq -r '.completed_phases // [] | join(", ")' "$PROGRESS_FILE" 2>/dev/null)
                print_info "[DRY RUN] Would resume task, skipping phases: ${skip_phases:-none}"
            else
                local phase_list
                case "$task_complexity" in
                    trivial)
                        phase_list="build verify"
                        ;;
                    simple)
                        phase_list="research build verify"
                        ;;
                    *)
                        phase_list="research review build codereview verify"
                        if [[ "$SKIP_SPEC" != "true" ]] && [[ -d ".claude/skills/buildcrew-spec" ]]; then
                            phase_list="spec $phase_list"
                        fi
                        if [[ "$SKIP_PREREQS" != "true" ]] && [[ -d ".claude/skills/buildcrew-prereqs" ]]; then
                            phase_list="${phase_list/research/prereqs research}"
                        fi
                        if [[ -d ".claude/skills/buildcrew-tdd-scaffold" ]]; then
                            phase_list="${phase_list/review build/review tdd-scaffold build}"
                        fi
                        if [[ -d ".claude/skills/buildcrew-docs" ]]; then
                            phase_list="${phase_list/build codereview/build docs codereview}"
                        fi
                        ;;
                esac
                if [[ "$task_complexity" != "standard" ]]; then
                    print_info "[DRY RUN] Complexity: $task_complexity"
                fi
                print_info "[DRY RUN] Would execute phases: $phase_list"
            fi
            print_info "[DRY RUN] Would mark complete: $task"
            ((completed++))
            ((dry_run_remaining--))
            if (( dry_run_remaining <= 0 )); then
                break
            fi
        else
            # Create feature branch if --branch is set
            if [[ "$GIT_BRANCH" == "true" ]]; then
                if ! create_task_branch "$task"; then
                    mark_task_blocked "$task" "Failed to create branch"
                    ((failed++))
                    continue
                fi
            fi

            # Run the appropriate processor
            ((task_num++))
            __WF_TASK_NUM="$task_num"
            local task_result=0
            process_task_isolated "$task" "$task_num" "$total_tasks" "$task_complexity" "$plan_ref" || task_result=$?

            if [[ $task_result -eq 4 ]]; then
                # Rate/usage limit — pause and retry same task (it remains pending)
                print_warning "API rate/usage limit hit. Task will be retried."
                echo "Press Enter to retry now, or wait for the timeout (5 min auto-retry)..."
                read -t 300 -r || true
                ((task_num--))  # undo increment so task numbering stays correct on retry
                continue
            fi

            if [[ $task_result -eq 0 ]]; then
                ((completed++))
            else
                ((failed++))
            fi

            # Branch cleanup: PR, return to base, sync backlog
            if [[ "$GIT_BRANCH" == "true" ]]; then
                if [[ $task_result -eq 0 ]]; then
                    create_task_pr "$task" || true
                fi
                return_to_original_branch
                # Sync task status to base branch
                if [[ $task_result -eq 0 ]]; then
                    mark_task_complete "$task"
                else
                    mark_task_blocked "$task" "See feature branch for details"
                fi
                git add "$BACKLOG_FILE" 2>/dev/null && \
                    git commit -m "chore(backlog): update task status" 2>/dev/null || true
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
    print_debug "Total invocations used: $__INVOCATION_COUNT"

    # Show remaining status
    local remaining
    remaining=$(count_tasks pending)
    if [[ "$remaining" -gt 0 ]]; then
        print_info "$remaining tasks still pending in backlog"
    else
        print_success "All backlog tasks processed!"

        # Post-completion UAT
        if [[ "$NO_UAT" != "true" && "$failed" -eq 0 && -f "README.md" && "$SINGLE_TASK" != "true" ]]; then
            local _uat_project _uat_result=0
            _uat_project="${TARGET_DIR:-$(basename "$(pwd)")}"
            local _uat_task="[UAT] Fix failing acceptance tests for $_uat_project — see .buildcrew/uat-context.md for details"
            run_inline_uat "$_uat_project" "$_uat_task" "standard" || _uat_result=$?
            if [[ $_uat_result -eq 2 ]]; then
                print_warning "UAT completed with disputed scenarios"
            elif [[ $_uat_result -ne 0 ]]; then
                print_error "UAT failed — run 'buildcrew uat' after fixing issues"
            fi
        elif [[ "$NO_UAT" != "true" && "$failed" -gt 0 ]]; then
            print_info "Skipping UAT — $failed task(s) failed. Run 'buildcrew uat' after fixing."
        fi
    fi

    clear_workflow_state
    cleanup_log "$failed"

    # Propagate failure to exit code so batch parent can detect it
    if [[ "$failed" -gt 0 ]]; then
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────────
# Run (only when executed directly, not sourced)
# ─────────────────────────────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    print_debug "Claude model=$CLAUDE_MODEL effort=$CLAUDE_EFFORT"
    main
fi
