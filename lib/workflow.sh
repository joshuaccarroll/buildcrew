#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BuildCrew - Autonomous Claude Code Development Pipeline
# https://github.com/joshuaccarroll/buildcrew
# ═══════════════════════════════════════════════════════════════════════════════
#
# This script orchestrates an autonomous development workflow using Claude Code.
# It reads tasks from BACKLOG.md and processes each one through phase groups:
#
# Phase-isolated mode (up to 7 separate Claude invocations):
#   0. Spec (optional, skipped with --skip-spec)
#   1. Research + Plan
#   2. Plan Review (3-pass)
#   3. Build
#   4. Code Review + Refactor + Test
#   4.5. Outcome Verification (validates against spec acceptance criteria)
#   5. Verify + Security Audit + Commit + Signal
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
__RESUME_PHASES=""

# Max turns per phase group (used in isolated mode)
# Uses a function instead of declare -A for bash 3.2 (macOS) compatibility
get_phase_max_turns() {
    case "$1" in
        spec)     echo 30 ;;
        research) echo 40 ;;
        review)   echo 50 ;;
        build)    echo 50 ;;
        test)     echo 60 ;;
        outcome)  echo 40 ;;
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
RESUME_MODE=false
TARGET_TASK=""
ORIGINAL_BRANCH=""
HAS_REMOTE=false
GH_AVAILABLE=false
SKIP_SPEC=false
STRICT_MODE=false

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
                shift 2
                ;;
            --skip-spec)
                SKIP_SPEC=true
                shift
                ;;
            --strict)
                STRICT_MODE=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --dry-run    Show what would be done without executing"
                echo "  --single     Process only one task then exit"
                echo "  --review     Pause for human review after plan and plan review"
                echo "  --branch     Create a feature branch per task with optional PR"
                echo "  --task NAME  Target a specific task by name or number (implies --single)"
                echo "  --resume     Resume an interrupted task from where it left off"
                echo "  --skip-spec  Skip the specification refinement phase (for tasks with detailed specs already)"
                echo "  --strict     Require ALL acceptance criteria to pass before commit (outcome phase)"
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
    local force="${4:-}"

    [[ "$HUMAN_REVIEW" == "true" || "$force" == "--force" ]] || return 0

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

task_to_slug() {
    local task="$1"
    local slug
    # Lowercase, replace non-alphanumeric with hyphens, collapse multiple hyphens, trim
    slug=$(echo "$task" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
    # Truncate to 60 chars
    slug="${slug:0:60}"
    echo "$slug"
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

# Check if this is a brownfield project (has existing source code)
has_existing_codebase() {
    # Language/framework manifest files (Makefile intentionally excluded -- too generic)
    for f in package.json go.mod pyproject.toml Cargo.toml Gemfile composer.json pom.xml build.gradle requirements.txt setup.py .sln; do
        [[ -f "$f" ]] && return 0
    done
    # Check for common source directories (any contents)
    for d in src lib app; do
        [[ -d "$d" ]] && return 0
    done
    return 1
}

# Run norms analysis as a single Claude invocation
run_norms_analysis() {
    local max_turns=40
    print_header "Codebase Norms Analysis"
    print_info "Analyzing codebase patterns, conventions, and team norms..."

    # Offer opt-out for interactive terminals
    if [[ -t 0 ]]; then
        echo -e "${CYAN}Existing codebase detected.${NC} Run norms analysis to learn your conventions?"
        echo -e "  ${BOLD}[Enter]${NC} Yes, analyze  |  ${BOLD}[s]${NC} Skip"
        read -r norms_response
        case "$norms_response" in
            s|S|n|N)
                print_info "Skipping norms analysis. Run later with: buildcrew norms"
                return
                ;;
        esac
    fi

    # Inject project context if available
    local prompt="Execute the buildcrew-norms skill to analyze this codebase."
    local project_context
    project_context=$(load_project_context)
    if [[ -n "$project_context" ]]; then
        prompt="$prompt"$'\n\nProject Context:\n'"$project_context"
    fi

    # Global invocation ceiling check
    if (( __INVOCATION_COUNT >= MAX_INVOCATIONS )); then
        print_warning "Invocation ceiling reached — skipping norms analysis"
        return
    fi

    __INVOCATION_COUNT=$(( __INVOCATION_COUNT + 1 ))
    claude -p "$prompt" --max-turns "$max_turns" || true

    if [[ -f ".buildcrew/norms/NORMS.md" ]]; then
        print_success "Norms generated at .buildcrew/norms/"
        print_info "Review .buildcrew/norms/ and edit if needed."
        # Only pause for interactive terminals
        if [[ -t 0 ]]; then
            print_info "Press Enter to continue, or Ctrl+C to stop and review first."
            read -r
        fi
    else
        print_warning "Norms analysis did not produce output. Continuing without norms."
    fi
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
# Task progress tracking (for --resume)
# ─────────────────────────────────────────────────────────────────────────────────

PROGRESS_FILE=".buildcrew/task-progress.json"

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
    if ! TASK="$saved_task" perl -ne 'if (/^- \[ \] \Q$ENV{TASK}\E$/) { $f=1; last } END { exit($f ? 0 : 1) }' "$BACKLOG_FILE"; then
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
    .claude/code-review.md .claude/test-report.md .claude/outcome-report.md
    .claude/security-audit.md .claude/verify-report.md .claude/current-test-plan.md
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

    print_info "Archived artifacts to $archive_dir"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Lessons system (Change 2: Self-Improvement Loop)
# ─────────────────────────────────────────────────────────────────────────────────

LESSONS_MAX_ENTRIES=100
LESSONS_SUMMARIZE_COUNT=50

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
        entry_count=$(grep -c '^## Lesson [0-9]' "$LESSONS_FILE" 2>/dev/null || echo 0)
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

# Summarize oldest LESSONS_SUMMARIZE_COUNT entries into a Patterns section.
_summarize_old_lessons() {
    local tmp_file
    tmp_file=$(mktemp)

    # Extract the header/patterns section (before first "## Lesson") and all lesson entries
    local header_end
    header_end=$(grep -n '^## Lesson [0-9]' "$LESSONS_FILE" 2>/dev/null | head -1 | cut -d: -f1)
    if [[ -z "$header_end" ]]; then
        return 0
    fi

    # Get existing patterns section (if any) or just the header
    local existing_patterns=""
    if grep -q '^## Patterns' "$LESSONS_FILE" 2>/dev/null; then
        existing_patterns=$(awk '/^## Patterns/,/^## Lesson [0-9]/' "$LESSONS_FILE" 2>/dev/null | sed '$d')
    fi

    # Get all lesson entries
    local all_lessons
    all_lessons=$(grep -n '^## Lesson [0-9]' "$LESSONS_FILE" 2>/dev/null)
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
    claude -p "$prompt" --max-turns "$max_turns" || true

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
        claude -p "$prompt" --max-turns "$max_turns" || true

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
            context="$context | Read .claude/test-report.md and .claude/verify-report.md for failure details before fixing."
            ;;
        security)
            context="$context | Read .claude/security-audit.md and .claude/verify-report.md for vulnerability details before fixing."
            ;;
    esac

    echo "$context"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Phase-Isolated Mode: process_task_isolated
# ─────────────────────────────────────────────────────────────────────────────────

process_task_isolated() {
    local task="$1"
    local __completed_phases=""
    local __is_resuming=false
    local __replan_count=0           # circuit breaker: how many times we've re-planned
    local __need_replan=false        # circuit breaker: set true to restart from research
    local __replan_context=""        # circuit breaker: failure context for re-plan prompt
    local build_attempt=0            # tracks total build attempts across build and outcome phases

    # Resume or fresh start
    if [[ "$RESUME_MODE" == "true" ]] && load_task_progress; then
        if [[ "$__RESUME_TASK" == "$task" ]] || [[ -z "$task" ]]; then
            task="${__RESUME_TASK}"
            __INVOCATION_COUNT=$__RESUME_INVOCATIONS
            __completed_phases="$__RESUME_PHASES"
            __is_resuming=true
            print_info "Resuming task (invocation count: $__INVOCATION_COUNT)"
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

    if [[ "$__is_resuming" != "true" ]]; then
        # Archive artifacts from any previous task before cleanup
        archive_task_artifacts

        # Clean up artifacts from any previous task
        rm -f "${ARTIFACT_FILES[@]}" "$PHASE_RESULT_FILE" "$STATUS_FILE"
    fi

    # Track current task for future archiving
    mkdir -p .buildcrew
    echo "$task" > "$CURRENT_TASK_FILE"

    # ─────────────────────────────────────────────────────────────────────────
    # Outer loop: supports circuit breaker re-planning
    # ─────────────────────────────────────────────────────────────────────────
    local __outer_iterations=0
    while true; do
        (( ++__outer_iterations ))
        if (( __outer_iterations > 2 )); then
            print_error "Outer loop safety limit exceeded"
            mark_task_blocked "$task" "Safety: outer loop exceeded 2 iterations"
            return 1
        fi
        __need_replan=false

    # --- Phase 0: Spec (optional, skipped with --skip-spec) ---
    local __spec_context=""
    local needs_human_review=false
    local hr_reason=""

    if [[ "$SKIP_SPEC" == "true" ]]; then
        print_info "Skipping phase: spec (--skip-spec flag set)"
    elif phase_completed "spec"; then
        print_info "Skipping phase: spec (completed in previous run)"
        if [[ -f ".claude/spec.md" ]]; then
            __spec_context="Specification available at .claude/spec.md — read it for acceptance criteria."
        fi
    elif [[ -d ".claude/skills/buildcrew-spec" ]]; then
        run_phase_group "spec" "$task" "${__replan_context:+Re-planning context: $__replan_context}" || { clear_task_progress; return 1; }

        local spec_verdict
        spec_verdict=$(jq -r '.verdict // "complete"' "$PHASE_RESULT_FILE")
        if [[ "$spec_verdict" == "vague" ]]; then
            local vague_reason
            vague_reason=$(jq -r '.details // "Task too vague"' "$PHASE_RESULT_FILE")
            mark_task_blocked "$task" "$vague_reason"
            clear_task_progress
            print_warning "Task flagged as too vague to spec. See .claude/spec.md for details."
            return 1
        fi

        __spec_context="Specification available at .claude/spec.md — read it for acceptance criteria and scope boundaries."
        __completed_phases="${__completed_phases:+$__completed_phases }spec"
        save_task_progress "$task" "$__completed_phases" "$__INVOCATION_COUNT"
    fi

    # --- Phase 1: Research + Plan ---
    if phase_completed "research"; then
        print_info "Skipping phase: research (completed in previous run)"
    else
        local research_extra="${__spec_context}"
        if [[ -n "$__replan_context" ]]; then
            research_extra="${research_extra:+$research_extra | }REPLAN: $__replan_context"
        fi
        run_phase_group "research" "$task" "$research_extra" || { clear_task_progress; return 1; }
        __completed_phases="${__completed_phases:+$__completed_phases }research"
        save_task_progress "$task" "$__completed_phases" "$__INVOCATION_COUNT"

        # Human review pause: automatic if AI recommends it, or if --review flag set
        local hr_exit=0
        if [[ -f "$PHASE_RESULT_FILE" ]] && jq -e '.human_review == true' "$PHASE_RESULT_FILE" >/dev/null 2>&1; then
            needs_human_review=true
            hr_reason=$(jq -r '.human_review_reason // "AI recommended review"' "$PHASE_RESULT_FILE")
        fi

        if [[ "$needs_human_review" == "true" ]]; then
            handle_human_review "$task" "Implementation plan ready — $hr_reason" ".claude/current-plan.md" "--force" || hr_exit=$?
        elif [[ "$HUMAN_REVIEW" == "true" ]]; then
            handle_human_review "$task" "Implementation plan ready" ".claude/current-plan.md" || hr_exit=$?
        fi
        if [[ $hr_exit -eq 1 ]]; then
            mark_task_blocked "$task" "Skipped during human review"
            clear_task_progress
            return 1
        elif [[ $hr_exit -eq 2 ]]; then
            touch "$STOP_FILE"
            mark_task_blocked "$task" "Pipeline stopped by human review"
            clear_task_progress
            return 1
        fi
    fi

    # --- Phase 2: Plan Review (max 3 external cycles, circuit breaker at 2 consecutive failures) ---
    if phase_completed "review"; then
        print_info "Skipping phase: review (completed in previous run)"
    else
        local plan_review_cycle=0
        local consecutive_review_failures=0
        while true; do
            ((plan_review_cycle++))
            local review_extra="Plan review cycle $plan_review_cycle (max 2 before re-planning)"
            if [[ -n "$__spec_context" ]]; then
                review_extra="$review_extra | $__spec_context"
            fi
            run_phase_group "review" "$task" "$review_extra" || { clear_task_progress; return 1; }

            local verdict
            verdict=$(jq -r '.verdict' "$PHASE_RESULT_FILE")
            case "$verdict" in
                approved)
                    consecutive_review_failures=0
                    local hr_exit=0
                    if [[ "$needs_human_review" == "true" ]]; then
                        handle_human_review "$task" "Plan approved (review recommended by AI)" ".claude/plan-review.md" "--force" || hr_exit=$?
                    elif [[ "$HUMAN_REVIEW" == "true" ]]; then
                        handle_human_review "$task" "Plan approved — review before build" ".claude/plan-review.md" || hr_exit=$?
                    fi
                    if [[ $hr_exit -eq 1 ]]; then
                        mark_task_blocked "$task" "Skipped during human review"
                        clear_task_progress
                        return 1
                    elif [[ $hr_exit -eq 2 ]]; then
                        touch "$STOP_FILE"
                        mark_task_blocked "$task" "Pipeline stopped by human review"
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
                        append_lesson "review" \
                            "Plan failed to converge after $plan_review_cycle cycles: $failure_summary" \
                            "Triggered circuit breaker and re-planned from scratch" \
                            "Start from a different architectural approach when plan review rejects the same issues twice"
                        if (( __replan_count >= 1 )); then
                            print_error "Circuit breaker triggered again after re-planning. Stopping task."
                            mark_task_blocked "$task" "Circuit breaker: plan failed twice even after re-planning"
                            clear_task_progress
                            return 1
                        fi
                        ((__replan_count++))
                        __replan_context="CIRCUIT BREAKER: Plan review failed twice. Previous approach: $failure_summary. Try a fundamentally different approach."
                        __need_replan=true
                        __completed_phases=""
                        clear_task_progress
                        break
                    fi
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

    # --- Phase 3 + 4: Build → Code Review/Test (with rebuild loop, circuit breaker) ---
    if phase_completed "build"; then
        print_info "Skipping phase: build+test (completed in previous run)"
    else
        local consecutive_build_failures=0
        while true; do
            ((build_attempt++))

            local build_context=""
            if [[ -n "$__spec_context" ]]; then
                build_context="$__spec_context"
            fi
            if (( build_attempt > 1 )); then
                local prev_reason
                prev_reason=$(jq -r '.details // "unknown"' "$PHASE_RESULT_FILE")
                build_context="${build_context:+$build_context | }This is build attempt $build_attempt. Previous attempt failed: $prev_reason. Avoid the same mistakes."
            fi

            run_phase_group "build" "$task" "$build_context" || { clear_task_progress; return 1; }

            local test_extra="${__spec_context}"
            run_phase_group "test" "$task" "$test_extra" || { clear_task_progress; return 1; }

            local verdict
            verdict=$(jq -r '.verdict' "$PHASE_RESULT_FILE")
            case "$verdict" in
                approved)
                    consecutive_build_failures=0
                    break ;;
                needs_rebuild|test_failure)
                    ((consecutive_build_failures++))
                    if (( consecutive_build_failures >= 2 )); then
                        local failure_summary
                        failure_summary=$(jq -r '.details // "Build/test failed twice"' "$PHASE_RESULT_FILE")
                        print_warning "[CIRCUIT BREAKER] Approach failed twice at Build/Test phase. Re-planning from scratch with failure context."
                        append_lesson "build" \
                            "Build/test failed after $build_attempt attempts: $failure_summary" \
                            "Triggered circuit breaker and re-planned from scratch" \
                            "When build fails twice on the same approach, the plan itself is likely flawed — re-plan rather than retry"
                        if (( __replan_count >= 1 )); then
                            print_error "Circuit breaker triggered again after re-planning. Stopping task."
                            mark_task_blocked "$task" "Circuit breaker: build/test failed twice even after re-planning"
                            clear_task_progress
                            return 1
                        fi
                        ((__replan_count++))
                        __replan_context="CIRCUIT BREAKER: Build/test failed twice. Previous failure: $failure_summary. The implementation approach needs to change — re-plan with a different strategy."
                        __need_replan=true
                        __completed_phases=""
                        clear_task_progress
                        break
                    fi
                    local first_fail_details
                    first_fail_details=$(jq -r '.details // "Build/test failed"' "$PHASE_RESULT_FILE")
                    append_lesson "build" \
                        "Build/test failed on attempt $build_attempt: $first_fail_details" \
                        "Retrying build with revised approach" \
                        "Read test output carefully before retrying — the error usually indicates a misunderstanding of the existing codebase"
                    continue ;;
                *) mark_task_blocked "$task" "Unexpected review verdict: $verdict"; clear_task_progress; return 1 ;;
            esac
        done

        if [[ "$__need_replan" == "true" ]]; then
            continue  # restart outer while loop
        fi

        __completed_phases="${__completed_phases:+$__completed_phases }build"
        save_task_progress "$task" "$__completed_phases" "$__INVOCATION_COUNT"
    fi

    # --- Phase 4.5: Outcome Verification (validates against spec acceptance criteria) ---
    if phase_completed "outcome"; then
        print_info "Skipping phase: outcome (completed in previous run)"
    elif [[ -d ".claude/skills/buildcrew-outcome" ]] && [[ "$SKIP_SPEC" != "true" ]] && [[ -f ".claude/spec.md" ]]; then
        local outcome_attempt=0
        local consecutive_outcome_failures=0
        while true; do
            ((outcome_attempt++))

            local outcome_extra="Read .claude/spec.md for acceptance criteria to verify. STRICT_MODE=${STRICT_MODE}"
            if (( outcome_attempt > 1 )); then
                local prev_outcome_reason
                prev_outcome_reason=$(jq -r '.details // "unknown"' "$PHASE_RESULT_FILE")
                outcome_extra="$outcome_extra | Retry after fix. Previous failure: $prev_outcome_reason"
            fi

            run_phase_group "outcome" "$task" "$outcome_extra" || { clear_task_progress; return 1; }

            local outcome_verdict
            outcome_verdict=$(jq -r '.verdict // "unknown"' "$PHASE_RESULT_FILE")
            case "$outcome_verdict" in
                passed)
                    consecutive_outcome_failures=0
                    break ;;
                partial)
                    # Some criteria failed — warn but allow if not --strict
                    if [[ "$STRICT_MODE" == "true" ]]; then
                        local partial_details
                        partial_details=$(jq -r '.details // "Some acceptance criteria not met"' "$PHASE_RESULT_FILE")
                        print_warning "--strict mode: partial outcome failure blocks commit. Rebuilding..."
                        # Fall through to failed path
                        ((consecutive_outcome_failures++))
                        if (( consecutive_outcome_failures >= 2 )); then
                            local failure_summary
                            failure_summary=$(jq -r '.details // "Outcome verification failed twice"' "$PHASE_RESULT_FILE")
                            print_warning "[CIRCUIT BREAKER] Approach failed twice at Outcome Verification. Re-planning from scratch."
                            append_lesson "outcome" \
                                "Acceptance criteria not met after $outcome_attempt attempts: $failure_summary" \
                                "Triggered circuit breaker and re-planned from scratch" \
                                "When acceptance criteria fail twice, the implementation misunderstands the spec — re-read spec carefully before coding"
                            if (( __replan_count >= 1 )); then
                                print_error "Circuit breaker triggered again after re-planning. Stopping task."
                                mark_task_blocked "$task" "Circuit breaker: outcome verification failed twice even after re-planning"
                                clear_task_progress
                                return 1
                            fi
                            ((__replan_count++))
                            __replan_context="CIRCUIT BREAKER: Outcome verification failed twice. Unmet criteria: $failure_summary. Re-read the spec in .claude/spec.md and plan differently."
                            __need_replan=true
                            __completed_phases=""
                            clear_task_progress
                            break
                        fi
                        # Rebuild to fix failing criteria
                        append_lesson "outcome" \
                            "Acceptance criteria partially met on attempt $outcome_attempt: $partial_details" \
                            "Rebuilt with targeted fix for failing criteria" \
                            "Partial acceptance at outcome stage means the implementation is incomplete — re-read the specific failing criteria in the spec"
                        ((build_attempt++))
                        run_phase_group "build" "$task" "OUTCOME FIX: $partial_details | $__spec_context" || { clear_task_progress; return 1; }
                        run_phase_group "test" "$task" "$__spec_context" || { clear_task_progress; return 1; }
                        continue
                    else
                        local partial_details
                        partial_details=$(jq -r '.details // "Some acceptance criteria not met"' "$PHASE_RESULT_FILE")
                        print_warning "Outcome verification: some acceptance criteria not fully met. Proceeding without --strict."
                        print_warning "Details: $partial_details"
                        break
                    fi
                    ;;
                failed)
                    ((consecutive_outcome_failures++))
                    if (( consecutive_outcome_failures >= 2 )); then
                        local failure_summary
                        failure_summary=$(jq -r '.details // "Outcome verification failed twice"' "$PHASE_RESULT_FILE")
                        print_warning "[CIRCUIT BREAKER] Approach failed twice at Outcome Verification. Re-planning from scratch."
                        append_lesson "outcome" \
                            "Acceptance criteria failed after $outcome_attempt attempts: $failure_summary" \
                            "Triggered circuit breaker and re-planned from scratch" \
                            "When acceptance criteria fail twice, the implementation misunderstands the spec — re-read spec before coding"
                        if (( __replan_count >= 1 )); then
                            print_error "Circuit breaker triggered again after re-planning. Stopping task."
                            mark_task_blocked "$task" "Circuit breaker: outcome verification failed twice even after re-planning"
                            clear_task_progress
                            return 1
                        fi
                        ((__replan_count++))
                        __replan_context="CIRCUIT BREAKER: Outcome verification failed twice. Unmet criteria: $failure_summary. Re-read the spec in .claude/spec.md and plan differently."
                        __need_replan=true
                        __completed_phases=""
                        clear_task_progress
                        break
                    fi
                    local rebuild_ctx
                    rebuild_ctx=$(jq -r '.details // "Acceptance criteria not met"' "$PHASE_RESULT_FILE")
                    print_info "Outcome verification failed — rebuilding to fix failing criteria..."
                    append_lesson "outcome" \
                        "Acceptance criteria failed: $rebuild_ctx" \
                        "Rebuilt with targeted fix for failing criteria" \
                        "Always run the feature against its acceptance criteria before consider it done"
                    ((build_attempt++))
                    run_phase_group "build" "$task" "OUTCOME FIX: $rebuild_ctx | $__spec_context" || { clear_task_progress; return 1; }
                    run_phase_group "test" "$task" "$__spec_context" || { clear_task_progress; return 1; }
                    continue ;;
                *)
                    mark_task_blocked "$task" "Unexpected outcome verdict: $outcome_verdict"
                    clear_task_progress
                    return 1 ;;
            esac
        done

        if [[ "$__need_replan" == "true" ]]; then
            continue  # restart outer while loop
        fi

        __completed_phases="${__completed_phases:+$__completed_phases }outcome"
        save_task_progress "$task" "$__completed_phases" "$__INVOCATION_COUNT"
    fi

    # --- Phase 5: Verify + Commit (never skipped — always re-verify) ---
    local verify_attempt=0
    local consecutive_verify_failures=0
    while true; do
        ((verify_attempt++))

        local verify_extra="${__spec_context}"
        run_phase_group "verify" "$task" "$verify_extra" || { clear_task_progress; return 1; }

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
                    append_lesson "verify" \
                        "Verification blocked twice on '$failing': $failure_details" \
                        "Triggered circuit breaker and re-planned from scratch" \
                        "When verification fails twice on the same check, the build approach itself is wrong — re-plan"
                    if (( __replan_count >= 1 )); then
                        print_error "Circuit breaker triggered again after re-planning. Stopping task."
                        mark_task_blocked "$task" "Circuit breaker: verification failed twice even after re-planning"
                        clear_task_progress
                        return 1
                    fi
                    ((__replan_count++))
                    __replan_context="CIRCUIT BREAKER: Verification failed twice on '$failing': $failure_details. Plan a different approach that avoids this issue."
                    __need_replan=true
                    __completed_phases=""
                    clear_task_progress
                    break
                fi

                case "$failing" in
                    tests|security)
                        local rebuild_context
                        rebuild_context=$(build_verify_failure_context "$failing")
                        append_lesson "verify" \
                            "Verify blocked on '$failing': $failure_details" \
                            "Rebuilt with targeted fix for $failing issues" \
                            "Always run the full verify check before considering a build complete"
                        run_phase_group "build" "$task" "$rebuild_context" || { clear_task_progress; return 1; }
                        run_phase_group "test" "$task" "$verify_extra" || { clear_task_progress; return 1; }
                        ;;
                    code_review)
                        append_lesson "verify" \
                            "Code review blocked verify on attempt $verify_attempt: $failure_details" \
                            "Re-ran test phase to address code review issues" \
                            "Code review failures at verify stage mean test phase missed quality checks — address style/structure issues during build"
                        run_phase_group "test" "$task" "$verify_extra" || { clear_task_progress; return 1; }
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

    check_prerequisites

    # Clear any previous stop signal
    clear_stop_signal

    # Auto-generate norms for brownfield projects on first run
    if [[ "$DRY_RUN" != "true" ]] && [[ ! -f ".buildcrew/norms/NORMS.md" ]] && has_existing_codebase; then
        run_norms_analysis
    fi

    print_header "BuildCrew - Autonomous Development Pipeline"
    print_info "To stop after the current task: buildcrew stop"

    # Require phase-isolated skills (installed via buildcrew init)
    if ! is_phase_isolation_available; then
        error "Phase-isolated skills not found. Run 'buildcrew init' to install them."
    fi

    local _phase_count=5
    [[ "$SKIP_SPEC" != "true" ]] && [[ -d ".claude/skills/buildcrew-spec" ]] && _phase_count=$((_phase_count + 1))
    [[ -d ".claude/skills/buildcrew-outcome" ]] && _phase_count=$((_phase_count + 1))
    print_info "Mode: Phase-isolated ($_phase_count invocations per task)"

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
        if [[ -n "$TARGET_TASK" ]]; then
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
                local phase_list="research review build test verify"
                if [[ "$SKIP_SPEC" != "true" ]]; then
                    phase_list="spec $phase_list"
                fi
                if [[ -d ".claude/skills/buildcrew-outcome" ]]; then
                    phase_list="${phase_list/test verify/test outcome verify}"
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
            local task_result=0
            if process_task_isolated "$task"; then
                task_result=0
            else
                task_result=1
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
    if [[ "$STRICT_MODE" == "true" ]] && [[ "$SKIP_SPEC" == "true" ]]; then
        print_warning "--strict has no effect with --skip-spec (outcome phase requires a spec)"
    fi
    main
fi
