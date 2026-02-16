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
# Source shared utilities (works both when exec'd and when sourced by tests)
# ─────────────────────────────────────────────────────────────────────────────────

__WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$__WORKFLOW_DIR/common.sh"

# ─────────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────────

PHASE_RESULT_FILE=".claude/phase-result.json"
STOP_FILE=".buildcrew/.stop-workflow"
LOCKFILE=".buildcrew/.workflow-lock"
MAX_TURNS=100
PAUSE_BETWEEN_TASKS=5
MAX_INVOCATIONS=${MAX_INVOCATIONS:-15}
__INVOCATION_COUNT=0

# Max turns per phase group (used in isolated mode)
# Uses a function instead of declare -A for bash 3.2 (macOS) compatibility
get_phase_max_turns() {
    case "$1" in
        research) echo 40 ;;
        review)   echo 50 ;;
        build)    echo 50 ;;
        test)     echo 60 ;;
        verify)   echo 30 ;;
        *)        echo 30 ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────────
# Argument parsing (only when executed directly)
# ─────────────────────────────────────────────────────────────────────────────────

DRY_RUN=false
SINGLE_TASK=false
HUMAN_REVIEW=false
GIT_BRANCH=false
ORIGINAL_BRANCH=""
HAS_REMOTE=false
GH_AVAILABLE=false
USE_TEAMS=false

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
            --review)
                HUMAN_REVIEW=true
                shift
                ;;
            --branch)
                GIT_BRANCH=true
                shift
                ;;
            --teams)
                USE_TEAMS=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --dry-run    Show what would be done without executing"
                echo "  --single     Process only one task then exit"
                echo "  --review     Pause for human review after plan and plan review (phase-isolated mode only)"
                echo "  --branch     Create a feature branch per task with optional PR (phase-isolated mode only)"
                echo "  --teams      Use agent teams mode (experimental, requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1)"
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
# Workflow-specific helpers
# ─────────────────────────────────────────────────────────────────────────────────

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
    stop_file_monitor
    rm -f "$LOCKFILE"
}

# Pause for human review when --review is set
# Returns: 0 = continue, 1 = skip task, 2 = quit pipeline
handle_human_review() {
    local task="$1"
    local description="$2"
    local artifact="$3"

    [[ "$HUMAN_REVIEW" == "true" ]] || return 0

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

task_to_branch_name() {
    local task="$1"
    local slug
    # Lowercase, replace non-alphanumeric with hyphens, collapse multiple hyphens, trim
    slug=$(echo "$task" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
    # Truncate to 60 chars
    slug="${slug:0:60}"
    echo "buildcrew/$slug"
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

    # Global invocation ceiling — prevent runaway API cost
    if (( __INVOCATION_COUNT >= MAX_INVOCATIONS )); then
        print_error "Global invocation ceiling reached ($__INVOCATION_COUNT/$MAX_INVOCATIONS) — aborting phase: $phase"
        return 1
    fi

    rm -f "$PHASE_RESULT_FILE"

    print_info "Phase: $phase (max $max_turns turns)"

    local prompt="Execute the buildcrew-$phase skill for this task: $task"
    if [[ -n "$extra_context" ]]; then
        prompt="$prompt. Context: $extra_context"
    fi

    # Inject project context
    local project_context
    project_context=$(load_project_context)
    if [[ -n "$project_context" ]]; then
        prompt="$prompt"$'\n\nProject Context:\n'"$project_context"
    fi

    # Start file watcher
    start_file_monitor "$PHASE_RESULT_FILE" "claude.*buildcrew-$phase"

    __INVOCATION_COUNT=$(( __INVOCATION_COUNT + 1 ))
    claude "$prompt" --max-turns "$max_turns" || true

    stop_file_monitor

    # Validate result (with one retry on failure)
    if [[ ! -f "$PHASE_RESULT_FILE" ]] || ! jq -e . "$PHASE_RESULT_FILE" >/dev/null 2>&1; then
        print_warning "Phase $phase produced no valid result. Retrying..."
        rm -f "$PHASE_RESULT_FILE"

        # Check ceiling again before retry
        if (( __INVOCATION_COUNT >= MAX_INVOCATIONS )); then
            print_error "Global invocation ceiling reached ($__INVOCATION_COUNT/$MAX_INVOCATIONS) — cannot retry phase: $phase"
            return 1
        fi

        start_file_monitor "$PHASE_RESULT_FILE" "claude.*buildcrew-$phase"

        __INVOCATION_COUNT=$(( __INVOCATION_COUNT + 1 ))
        claude "$prompt" --max-turns "$max_turns" || true

        stop_file_monitor

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

    # Reset global invocation counter for this task
    __INVOCATION_COUNT=0

    print_info "Running in phase-isolated mode (5 invocations)"

    # Clean up artifacts from any previous task
    rm -f .claude/research.md .claude/current-plan.md .claude/plan-review.md \
          .claude/code-review.md .claude/test-report.md .claude/security-audit.md \
          .claude/verify-report.md .claude/current-test-plan.md \
          "$PHASE_RESULT_FILE" "$STATUS_FILE"

    # --- Group 1: Research + Plan ---
    run_phase_group "research" "$task" || return 1

    # Human review pause: after research+plan, before AI review starts
    local hr_exit=0
    handle_human_review "$task" "Implementation plan ready" ".claude/current-plan.md" || hr_exit=$?
    if [[ $hr_exit -eq 1 ]]; then
        mark_task_blocked "$task" "Skipped during human review"
        return 1
    elif [[ $hr_exit -eq 2 ]]; then
        touch "$STOP_FILE"
        mark_task_blocked "$task" "Pipeline stopped by human review"
        return 1
    fi

    # --- Group 2: Plan Review (max 3 external cycles) ---
    local plan_review_cycle=0
    while true; do
        ((plan_review_cycle++))
        run_phase_group "review" "$task" "Plan review cycle $plan_review_cycle of 3" || return 1

        local verdict
        verdict=$(jq -r '.verdict' "$PHASE_RESULT_FILE")
        case "$verdict" in
            approved)
                local hr_exit=0
                handle_human_review "$task" "Plan approved — review before build" ".claude/plan-review.md" || hr_exit=$?
                if [[ $hr_exit -eq 1 ]]; then
                    mark_task_blocked "$task" "Skipped during human review"
                    return 1
                elif [[ $hr_exit -eq 2 ]]; then
                    touch "$STOP_FILE"
                    mark_task_blocked "$task" "Pipeline stopped by human review"
                    return 1
                fi
                break ;;
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

    # Start file monitor
    start_file_monitor "$STATUS_FILE" "claude.*Execute the buildcrew skill"

    # Build prompt with optional project context
    local prompt="Execute the buildcrew skill for this task: $task"
    local project_context
    project_context=$(load_project_context)
    if [[ -n "$project_context" ]]; then
        prompt="$prompt"$'\n\nProject Context:\n'"$project_context"
    fi

    # Run Claude (monitor will terminate it when status file appears)
    claude "$prompt" \
        --max-turns "$MAX_TURNS" || true

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

    check_prerequisites

    # Clear any previous stop signal
    clear_stop_signal

    print_header "BuildCrew - Autonomous Development Pipeline"
    print_info "To stop after the current task: buildcrew stop"

    # Detect mode (teams > phase-isolated > legacy)
    local use_isolation=false
    local use_teams=false
    if [[ "$USE_TEAMS" == "true" ]]; then
        # Source teams module
        source "$__WORKFLOW_DIR/teams.sh"

        if ! check_teams_prerequisites; then
            exit 1
        fi
        use_teams=true
        print_info "Mode: Agent Teams (experimental)"
        print_warning "Agent teams is experimental. Token usage will be higher than phase-isolated mode."
        if [[ "$HUMAN_REVIEW" == "true" ]]; then
            print_warning "--review is not yet supported with --teams (team lead manages workflow internally). Ignoring."
            HUMAN_REVIEW=false
        fi
    elif is_phase_isolation_available; then
        use_isolation=true
        print_info "Mode: Phase-isolated (5 invocations per task)"
    else
        print_info "Mode: Legacy (single invocation per task)"
        if [[ "$HUMAN_REVIEW" == "true" ]]; then
            print_warning "--review requires phase-isolated mode (no phase boundaries in legacy mode). Ignoring."
            HUMAN_REVIEW=false
        fi
        if [[ "$GIT_BRANCH" == "true" ]]; then
            print_warning "--branch requires phase-isolated mode (no phase boundaries in legacy mode). Ignoring."
            GIT_BRANCH=false
        fi
        if [[ "$USE_TEAMS" == "true" ]]; then
            print_warning "--teams requires phase-isolated mode. Ignoring."
            USE_TEAMS=false
        fi
    fi

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
    echo $$ > "$LOCKFILE"
    trap cleanup EXIT INT TERM

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
            if [[ "$GIT_BRANCH" == "true" ]]; then
                print_info "[DRY RUN] Would create branch: $(task_to_branch_name "$task")"
            fi
            if [[ "$use_teams" == "true" ]]; then
                print_info "[DRY RUN] Would launch agent teams for: $task"
            elif [[ "$use_isolation" == "true" ]]; then
                print_info "[DRY RUN] Would execute 5 phase groups for: $task"
            else
                print_info "[DRY RUN] Would execute: claude -p \"Execute the buildcrew skill for this task: $task\""
            fi
            mark_task_complete "$task"
            ((completed++))
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
            local task_result=0
            if [[ "$use_teams" == "true" ]]; then
                if process_task_teams "$task"; then
                    task_result=0
                else
                    task_result=1
                fi
            elif [[ "$use_isolation" == "true" ]]; then
                if process_task_isolated "$task"; then
                    task_result=0
                else
                    task_result=1
                fi
            else
                if process_task_legacy "$task"; then
                    task_result=0
                else
                    task_result=1
                fi
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
    main
fi
