#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BuildCrew - UAT Orchestrator
# https://github.com/joshuaccarroll/buildcrew
# ═══════════════════════════════════════════════════════════════════════════════
#
# Manages the UAT (User Acceptance Testing) phase pipeline. Handles:
#   - UAT directory initialization
#   - Phase sequencing (stories, scenarios, harness, wait, setup, execute, verdict)
#   - Artifact polling and environment setup
#   - Server lifecycle management (start, health-check, stop)
#   - Retry loop for failing/errored scenarios
#   - Restart recovery (resume from last checkpoint)
#
# Actors:
#   - UAT orchestrator (this file): directory init, polling, server lifecycle,
#     file monitoring, retry loop, verdict writing
#   - UAT Claude agent: invoked per phase via `claude -p` for stories, scenarios,
#     harness, and execute phases
#
# This file must NOT set shell options (set -e, set -u, etc.) because callers
# have different shell option requirements.
#
# ═══════════════════════════════════════════════════════════════════════════════

# Source guard — prevent double-sourcing
[[ -n "${__BUILDCREW_UAT_LOADED:-}" ]] && return 0
__BUILDCREW_UAT_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────────
# Source dependencies
# ─────────────────────────────────────────────────────────────────────────────────

__UAT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$__UAT_LIB_DIR/common.sh"
source "$__UAT_LIB_DIR/uat_signal.sh"
# Note: Do NOT source artifact.sh — that is build-side only.
# We use read_manifest from artifact.sh only via its globals, which we replicate
# with a local manifest reader in uat_phase_wait_artifact.

# ─────────────────────────────────────────────────────────────────────────────────
# UAT Configuration defaults
# ─────────────────────────────────────────────────────────────────────────────────

UAT_POLL_INTERVAL="${UAT_POLL_INTERVAL:-5}"
UAT_ARTIFACT_TIMEOUT="${UAT_ARTIFACT_TIMEOUT:-1800}"
UAT_EXECUTE_TIMEOUT="${UAT_EXECUTE_TIMEOUT:-600}"
UAT_HEALTH_CHECK_TIMEOUT="${UAT_HEALTH_CHECK_TIMEOUT:-30}"
UAT_MAX_RETRIES="${UAT_MAX_RETRIES:-5}"

# Phase result file — same convention as workflow.sh
UAT_PHASE_RESULT_FILE=".claude/phase-result.json"

# ─────────────────────────────────────────────────────────────────────────────────
# UAT Globals (set by various functions, read by callers)
# ─────────────────────────────────────────────────────────────────────────────────

__UAT_SERVER_PID=""
__UAT_ARTIFACT_TYPE=""
__UAT_ARTIFACT_PATH=""
__UAT_RUN_COMMAND=""
__UAT_INSTALL_COMMAND=""
__UAT_HEALTH_CHECK=""
__UAT_STOP_COMMAND=""
__UAT_BUILD_ITERATION=""
__UAT_README_HASH=""

# ─────────────────────────────────────────────────────────────────────────────────
# UAT config loader — reads UAT-specific keys from .buildcrew/config
# ─────────────────────────────────────────────────────────────────────────────────

load_uat_config() {
    local config_file=".buildcrew/config"
    [[ -f "$config_file" ]] || return 0

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # Strip surrounding quotes
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            case "$key" in
                UAT_POLL_INTERVAL)
                    if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
                        UAT_POLL_INTERVAL="$value"
                    fi
                    ;;
                UAT_ARTIFACT_TIMEOUT)
                    if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
                        UAT_ARTIFACT_TIMEOUT="$value"
                    fi
                    ;;
                UAT_EXECUTE_TIMEOUT)
                    if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
                        UAT_EXECUTE_TIMEOUT="$value"
                    fi
                    ;;
                UAT_HEALTH_CHECK_TIMEOUT)
                    if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
                        UAT_HEALTH_CHECK_TIMEOUT="$value"
                    fi
                    ;;
                UAT_MAX_RETRIES)
                    if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
                        UAT_MAX_RETRIES="$value"
                    fi
                    ;;
            esac
        fi
    done < "$config_file"
}

# ─────────────────────────────────────────────────────────────────────────────────
# sha256_hash — portable SHA-256 hash of a file (duplicated from artifact.sh
# to avoid sourcing artifact.sh on the UAT side)
# ─────────────────────────────────────────────────────────────────────────────────

_uat_sha256_hash() {
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
# _uat_read_manifest — read and validate manifest.json (UAT-side copy to avoid
# sourcing artifact.sh)
# ─────────────────────────────────────────────────────────────────────────────────

_uat_read_manifest() {
    local manifest_path="$1"

    # Reset globals
    __UAT_ARTIFACT_TYPE=""
    __UAT_ARTIFACT_PATH=""
    __UAT_RUN_COMMAND=""
    __UAT_INSTALL_COMMAND=""
    __UAT_HEALTH_CHECK=""
    __UAT_STOP_COMMAND=""
    __UAT_BUILD_ITERATION=""
    __UAT_README_HASH=""

    if [[ ! -f "$manifest_path" ]]; then
        return 1
    fi

    if ! jq -e . "$manifest_path" >/dev/null 2>&1; then
        print_warning "Invalid JSON in manifest: $manifest_path"
        return 1
    fi

    __UAT_ARTIFACT_TYPE=$(jq -r '.artifact_type // ""' "$manifest_path")
    __UAT_ARTIFACT_PATH=$(jq -r '.artifact_path // ""' "$manifest_path")
    __UAT_RUN_COMMAND=$(jq -r '.run_command // ""' "$manifest_path")
    __UAT_INSTALL_COMMAND=$(jq -r '.install_command // ""' "$manifest_path")
    __UAT_HEALTH_CHECK=$(jq -r '.health_check // ""' "$manifest_path")
    __UAT_STOP_COMMAND=$(jq -r '.stop_command // ""' "$manifest_path")
    __UAT_BUILD_ITERATION=$(jq -r '.build_iteration // 0' "$manifest_path")
    __UAT_README_HASH=$(jq -r '.readme_hash // ""' "$manifest_path")

    # Validate required fields
    if [[ -z "$__UAT_ARTIFACT_TYPE" ]] || [[ -z "$__UAT_ARTIFACT_PATH" ]]; then
        print_warning "Manifest missing required fields: $manifest_path"
        return 1
    fi

    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 1. uat_init — UAT directory initialization
# ═══════════════════════════════════════════════════════════════════════════════

uat_init() {
    local readme_path="$1"
    local project_name="$2"

    if [[ -z "$readme_path" || -z "$project_name" ]]; then
        print_error "uat_init: readme_path and project_name are required"
        return 1
    fi

    if [[ ! -f "$readme_path" ]]; then
        print_error "uat_init: README not found: $readme_path"
        return 1
    fi

    print_header "UAT Initialization"

    # 1. Create .buildcrew/ directory
    mkdir -p .buildcrew

    # 2. Write isolation CLAUDE.md directive
    local claude_md=".buildcrew/CLAUDE.md"
    cat > "$claude_md" << 'ISOLATION_EOF'
Do NOT read, list, or access any directory outside your working directory except
the files the orchestrator provides. Specifically:
- You may read README.md in your working directory (copied by the orchestrator).
- You may use commands in harness/.artifact-bin/ (created by the orchestrator).
- Do NOT access the project source directory or artifact_path from the manifest.
- Do NOT access the --readme source path directly.
ISOLATION_EOF

    # 3. Create subdirectories
    mkdir -p scenarios harness results

    # 4. Copy README from --readme path into working dir
    cp "$readme_path" README.md

    # 5. Compute and store README hash
    local readme_hash
    readme_hash=$(_uat_sha256_hash README.md) || {
        print_error "uat_init: failed to compute README hash"
        return 1
    }
    echo "$readme_hash" > .buildcrew/last_readme_hash

    # 6. Create signal directory
    create_signal_dir "$project_name" || {
        print_error "uat_init: failed to create signal directory"
        return 1
    }

    # 7. Do NOT delete verdict.json (spec requirement)

    # Load UAT config
    load_uat_config

    print_success "UAT directory initialized for project: $project_name"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2. uat_run_phases — Main orchestrator loop
# ═══════════════════════════════════════════════════════════════════════════════

uat_run_phases() {
    local readme_path="$1"
    local project_name="$2"
    local auto_mode="${3:-false}"

    if [[ -z "$readme_path" || -z "$project_name" ]]; then
        print_error "uat_run_phases: readme_path and project_name are required"
        return 1
    fi

    # Load config
    load_uat_config

    # Set up cleanup trap
    trap 'uat_cleanup' EXIT INT TERM

    # Initialize logging
    log_init

    # ── Restart recovery ──────────────────────────────────────────────────────

    local need_phases_1_3=true
    local last_hash=""

    if [[ -f .buildcrew/last_readme_hash ]]; then
        last_hash=$(cat .buildcrew/last_readme_hash 2>/dev/null)
    fi

    local current_hash
    current_hash=$(_uat_sha256_hash "$readme_path") || {
        print_error "uat_run_phases: failed to compute README hash"
        return 1
    }

    if [[ -n "$last_hash" ]] && [[ "$last_hash" == "$current_hash" ]]; then
        # Hashes match — check if scenarios and harness are non-empty
        local has_scenarios=false
        local has_harness=false
        local f
        for f in scenarios/*.md; do
            [[ -f "$f" ]] && { has_scenarios=true; break; }
        done
        for f in harness/*; do
            [[ -e "$f" ]] && { has_harness=true; break; }
        done

        if [[ "$has_scenarios" == "true" ]] && [[ "$has_harness" == "true" ]]; then
            print_info "Restart recovery: scenarios and harness intact, skipping Phases 1-3"
            need_phases_1_3=false
        fi
    else
        # Hash differs or first run — update README copy
        cp "$readme_path" README.md
        echo "$current_hash" > .buildcrew/last_readme_hash
    fi

    # ── Run Phases 1-3 if needed ──────────────────────────────────────────────

    if [[ "$need_phases_1_3" == "true" ]]; then
        uat_phase_stories || return 1
        uat_phase_scenarios || return 1
        uat_phase_harness || return 1
    fi

    # ── Retry loop: Phase 4 → Phase 6 ────────────────────────────────────────

    local retry_count=0
    local failing_scenarios=""
    local signal_dir="${HOME}/.buildcrew/uat-signals/${project_name}"

    while true; do
        # Phase 4: Wait for artifact
        uat_phase_wait_artifact "$project_name" || return 1

        local build_iteration="$__UAT_BUILD_ITERATION"

        # Check for README changes
        if [[ -n "$__UAT_README_HASH" ]] && [[ -f .buildcrew/last_readme_hash ]]; then
            local stored_hash
            stored_hash=$(cat .buildcrew/last_readme_hash 2>/dev/null)
            if [[ "$stored_hash" != "$__UAT_README_HASH" ]]; then
                print_info "README changed — re-running Phases 1-3"
                cp "$readme_path" README.md
                echo "$__UAT_README_HASH" > .buildcrew/last_readme_hash
                # Clear stale scenarios and harness
                rm -rf scenarios/* harness/*
                mkdir -p scenarios harness
                failing_scenarios=""
                uat_phase_stories || return 1
                uat_phase_scenarios || return 1
                uat_phase_harness || return 1
            fi
        fi

        # Phase 4.5: Set up artifact environment
        local artifact_context=""
        uat_phase_setup_env \
            "$__UAT_ARTIFACT_TYPE" \
            "$__UAT_ARTIFACT_PATH" \
            "$__UAT_RUN_COMMAND" \
            "$__UAT_INSTALL_COMMAND" \
            "$__UAT_HEALTH_CHECK" || {
            local setup_rc=$?
            # Install failure → write error verdict and loop back
            if [[ $setup_rc -eq 2 ]]; then
                local error_json
                error_json=$(jq -n '[{"scenario":"artifact_setup","status":"error","summary":"Artifact install or setup failed","expected":"Artifact installs successfully","actual":"Install command exited non-zero"}]')
                write_verdict "$signal_dir" "$error_json" "$build_iteration"
                write_last_tested_iteration ".buildcrew" "$build_iteration"
                print_warning "Artifact setup failed — waiting for new artifact"
                continue
            fi
            return 1
        }
        artifact_context="$__UAT_ARTIFACT_CONTEXT"

        # Clean up partial results from a previous crash at this iteration
        local results_dir="results/iteration-${build_iteration}"
        if [[ -d "$results_dir" ]] && [[ ! -f "${results_dir}/scenario-results.json" ]]; then
            print_info "Clearing partial results directory: $results_dir"
            rm -rf "$results_dir"
        fi
        mkdir -p "$results_dir"

        # Phase 5: Execute scenarios
        uat_phase_execute "$build_iteration" "$artifact_context" "$failing_scenarios" || {
            # Execution failed entirely — write error verdict
            local error_json
            error_json=$(jq -n '[{"scenario":"harness_execution","status":"error","summary":"Phase 5 execution failed","expected":"Test harness runs successfully","actual":"Claude agent crashed or timed out"}]')
            write_verdict "$signal_dir" "$error_json" "$build_iteration"
            write_last_tested_iteration ".buildcrew" "$build_iteration"
            # Stop server if running
            uat_stop_server
            retry_count=$((retry_count + 1))
            if [[ $retry_count -ge $UAT_MAX_RETRIES ]]; then
                print_error "UAT max retries ($UAT_MAX_RETRIES) exhausted"
                return 1
            fi
            continue
        }

        # Stop server after Phase 5 (for api type)
        uat_stop_server

        # Phase 6: Write verdict
        uat_phase_verdict "$signal_dir" "$build_iteration" || {
            # Phase 6 failed (e.g., no valid scenario results)
            retry_count=$((retry_count + 1))
            if [[ $retry_count -ge $UAT_MAX_RETRIES ]]; then
                print_error "UAT max retries ($UAT_MAX_RETRIES) exhausted"
                return 1
            fi
            continue
        }

        # Read the verdict we just wrote to determine next action
        read_verdict "$signal_dir" || {
            print_error "Failed to read verdict after writing"
            return 1
        }

        if [[ "$__VERDICT_STATUS" == "pass" ]]; then
            print_success "All scenarios passed!"
            return 0
        fi

        # Check for only disputes remaining (no failures or errors)
        if [[ "$__VERDICT_FAILED" -eq 0 ]] && [[ "$__VERDICT_ERRORED" -eq 0 ]] && [[ "$__VERDICT_DISPUTED" -gt 0 ]]; then
            # Only disputed scenarios remain
            if [[ "$auto_mode" == "true" ]]; then
                print_info "Only disputed scenarios remain (auto mode) — exiting with code 2"
                return 2
            else
                print_warning "Only disputed scenarios remain. Check disputes.md for details."
                return 2
            fi
        fi

        # Failures or errors exist — extract failing scenario names for retry
        failing_scenarios=$(echo "$__VERDICT_SCENARIOS_JSON" | jq -r '.[] | select(.status == "fail" or .status == "error") | .scenario' 2>/dev/null | tr '\n' '|')
        failing_scenarios="${failing_scenarios%|}"  # Strip trailing delimiter

        retry_count=$((retry_count + 1))
        if [[ $retry_count -ge $UAT_MAX_RETRIES ]]; then
            print_error "UAT max retries ($UAT_MAX_RETRIES) exhausted — $__VERDICT_FAILED failures, $__VERDICT_ERRORED errors remain"
            return 1
        fi

        print_info "Retry $retry_count/$UAT_MAX_RETRIES — waiting for new artifact (${__VERDICT_FAILED} failures, ${__VERDICT_ERRORED} errors)"
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# 3. uat_phase_stories — Phase 1: Extract User Stories (Claude agent)
# ═══════════════════════════════════════════════════════════════════════════════

uat_phase_stories() {
    print_header "UAT Phase 1: Extract User Stories"
    _uat_run_agent_phase "uat-stories" "Extract user stories from README" ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# 4. uat_phase_scenarios — Phase 2: Generate Scenarios (Claude agent)
# ═══════════════════════════════════════════════════════════════════════════════

uat_phase_scenarios() {
    print_header "UAT Phase 2: Generate Scenarios"
    _uat_run_agent_phase "uat-scenarios" "Generate test scenarios from user stories" ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# 5. uat_phase_harness — Phase 3: Build Test Harness (Claude agent)
# ═══════════════════════════════════════════════════════════════════════════════

uat_phase_harness() {
    print_header "UAT Phase 3: Build Test Harness"
    _uat_run_agent_phase "uat-harness" "Build executable test harness from scenarios" ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# _uat_run_agent_phase — Shared phase execution protocol for Claude agent phases
# ═══════════════════════════════════════════════════════════════════════════════
#
# Follows the same pattern as workflow.sh's __run_phase_group_impl:
# - Build prompt from SKILL.md content (strip YAML frontmatter)
# - Start file monitor for phase-result.json
# - Invoke claude -p with prompt
# - Validate phase-result.json
#
# Args:
#   phase_name   — e.g., "uat-stories", "uat-scenarios"
#   task         — task description for the prompt
#   extra_context — additional context to append to prompt

_uat_run_agent_phase() {
    local phase_name="$1"
    local task="$2"
    local extra_context="${3:-}"
    local max_turns=50

    rm -f "$UAT_PHASE_RESULT_FILE"

    # Build prompt: inline SKILL.md content (strip YAML frontmatter)
    local skill_dir
    if [[ -n "${BUILDCREW_HOME:-}" ]]; then
        skill_dir="$BUILDCREW_HOME/skills/buildcrew-${phase_name}"
    else
        skill_dir="$__UAT_LIB_DIR/../skills/buildcrew-${phase_name}"
    fi

    # Also check the .claude/skills symlink path (standard skill location)
    local skill_file=""
    if [[ -f "${skill_dir}/SKILL.md" ]]; then
        skill_file="${skill_dir}/SKILL.md"
    elif [[ -f ".claude/skills/buildcrew-${phase_name}/SKILL.md" ]]; then
        skill_file=".claude/skills/buildcrew-${phase_name}/SKILL.md"
    fi

    local phase_tag="buildcrew-${phase_name}"
    local prompt="Execute the $phase_tag skill: $task"

    if [[ -n "$extra_context" ]]; then
        prompt="$prompt. Context: $extra_context"
    fi

    # Extract allowed-tools from SKILL.md frontmatter before stripping it
    local allowed_tools=""
    if [[ -n "$skill_file" ]]; then
        allowed_tools=$(awk 'NR==1&&/^---/{f=1;next} f&&/^---/{f=0;next} f&&/^allowed-tools:/{sub(/^allowed-tools:[[:space:]]*/,"");print}' "$skill_file")
        # Strip YAML frontmatter (content between first and second --- delimiters)
        local skill_content
        skill_content=$(awk 'NR==1&&/^---/{f=1;next} f&&/^---/{f=0;next} !f' "$skill_file")
        prompt="$prompt"$'\n\n---\n\n'"$skill_content"
    fi

    # Build --allowedTools flag if declared
    local allowed_tools_flag=""
    if [[ -n "$allowed_tools" ]]; then
        allowed_tools_flag="--allowedTools $allowed_tools"
    fi

    # Inject project context (lessons, etc.)
    local project_context
    project_context=$(load_project_context)
    if [[ -n "$project_context" ]]; then
        prompt="$prompt"$'\n\nProject Context:\n'"$project_context"
    fi

    # Save terminal state
    local __saved_stty=""
    if [[ -t 0 ]]; then
        __saved_stty=$(stty -g 2>/dev/null) || __saved_stty=""
    fi

    # Start file monitor
    start_file_monitor "$UAT_PHASE_RESULT_FILE" "claude.*${phase_tag}"

    print_info "Phase: $phase_name (max $max_turns turns)"
    log_msg "=== UAT PHASE: $phase_name started (max_turns=$max_turns) ==="

    # Invoke Claude agent
    if [[ -n "${__LOG_FILE:-}" ]]; then
        log_msg "--- claude output start: $phase_name ---"
        claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag 2>&1 | tee -a "$__LOG_FILE" || true
        log_msg "--- claude output end: $phase_name ---"
    else
        claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag || true
    fi

    stop_file_monitor
    # Restore terminal state
    [[ -n "$__saved_stty" ]] && stty "$__saved_stty" 2>/dev/null || true

    # Validate result (with one retry on failure)
    if [[ ! -f "$UAT_PHASE_RESULT_FILE" ]] || ! jq -e . "$UAT_PHASE_RESULT_FILE" >/dev/null 2>&1; then
        print_warning "Phase $phase_name produced no valid result. Retrying..."
        rm -f "$UAT_PHASE_RESULT_FILE"

        start_file_monitor "$UAT_PHASE_RESULT_FILE" "claude.*${phase_tag}"

        log_msg "=== UAT PHASE: $phase_name retry ==="
        if [[ -n "${__LOG_FILE:-}" ]]; then
            log_msg "--- claude output start: $phase_name ---"
            claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag 2>&1 | tee -a "$__LOG_FILE" || true
            log_msg "--- claude output end: $phase_name ---"
        else
            claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag || true
        fi

        stop_file_monitor
        [[ -n "$__saved_stty" ]] && stty "$__saved_stty" 2>/dev/null || true

        if [[ ! -f "$UAT_PHASE_RESULT_FILE" ]] || ! jq -e . "$UAT_PHASE_RESULT_FILE" >/dev/null 2>&1; then
            print_error "Phase $phase_name failed after retry"
            return 1
        fi
    fi

    local verdict
    verdict=$(jq -r '.verdict // "unknown"' "$UAT_PHASE_RESULT_FILE")
    print_success "Phase $phase_name complete — verdict: $verdict"
    log_msg "=== UAT PHASE: $phase_name ended (verdict: $verdict) ==="

    if [[ "$verdict" == "fail" ]]; then
        local details
        details=$(jq -r '.details // "No details"' "$UAT_PHASE_RESULT_FILE")
        print_error "Phase $phase_name verdict: fail — $details"
        return 1
    fi

    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 6. uat_phase_wait_artifact — Phase 4: Wait for Artifact (Orchestrator only)
# ═══════════════════════════════════════════════════════════════════════════════

uat_phase_wait_artifact() {
    local project_name="$1"

    if [[ -z "$project_name" ]]; then
        print_error "uat_phase_wait_artifact: project_name is required"
        return 1
    fi

    print_header "UAT Phase 4: Wait for Artifact"

    local artifact_dir="${UAT_ARTIFACT_DIR:-${HOME}/.buildcrew/artifacts}/${project_name}"
    local manifest_path="${artifact_dir}/manifest.json"

    # Read last tested iteration
    local last_tested
    last_tested=$(read_last_tested_iteration ".buildcrew")

    local elapsed=0

    print_info "Polling for artifact manifest: $manifest_path (timeout: ${UAT_ARTIFACT_TIMEOUT}s)"

    while true; do
        if [[ $elapsed -ge $UAT_ARTIFACT_TIMEOUT ]]; then
            print_error "Artifact not published within timeout. Is \`buildcrew run --uat\` running?"
            return 1
        fi

        if [[ -f "$manifest_path" ]]; then
            # Read and validate manifest
            if _uat_read_manifest "$manifest_path"; then
                # Check if this is a new iteration
                if [[ "$__UAT_BUILD_ITERATION" -gt "$last_tested" ]]; then
                    print_success "Artifact found: type=$__UAT_ARTIFACT_TYPE iteration=$__UAT_BUILD_ITERATION"
                    return 0
                fi
            fi
        fi

        sleep "$UAT_POLL_INTERVAL"
        elapsed=$((elapsed + UAT_POLL_INTERVAL))
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# 7. uat_phase_setup_env — Phase 4.5: Set Up Artifact Environment
# ═══════════════════════════════════════════════════════════════════════════════
#
# Returns:
#   0 = success (sets __UAT_ARTIFACT_CONTEXT)
#   1 = fatal error
#   2 = install failure (caller should write error verdict and retry)

# Global set by uat_phase_setup_env for the Phase 5 prompt
__UAT_ARTIFACT_CONTEXT=""

uat_phase_setup_env() {
    local artifact_type="$1"
    local artifact_path="$2"
    local run_command="${3:-}"
    local install_command="${4:-}"
    local health_check="${5:-}"

    __UAT_ARTIFACT_CONTEXT=""

    if [[ -z "$artifact_type" || -z "$artifact_path" ]]; then
        print_error "uat_phase_setup_env: artifact_type and artifact_path are required"
        return 1
    fi

    print_header "UAT Phase 4.5: Set Up Artifact Environment"

    # Create artifact bin directory
    mkdir -p harness/.artifact-bin

    case "$artifact_type" in
        cli|tui)
            # Run install_command if provided
            if [[ -n "$install_command" ]]; then
                print_info "Running install command: $install_command"
                if ! (cd "$artifact_path" && eval "$install_command") 2>&1; then
                    print_error "Install command failed"
                    return 2
                fi
            fi

            # Create wrapper scripts based on run_command
            if [[ -n "$run_command" ]]; then
                local wrapper_name
                # Determine wrapper name from run_command
                # If it's a path to a binary (e.g., ./bin/myapp), use the basename
                # If it's an invocation pattern (e.g., cargo run), use the first word
                if [[ "$run_command" == ./* ]] || [[ "$run_command" == /* ]]; then
                    wrapper_name=$(basename "$run_command" | cut -d' ' -f1)
                else
                    wrapper_name=$(echo "$run_command" | cut -d' ' -f1)
                fi

                local wrapper_path="harness/.artifact-bin/${wrapper_name}"

                if [[ "$run_command" == ./* ]] || [[ "$run_command" == /* ]]; then
                    # Direct binary path — create exec wrapper
                    local abs_binary
                    if [[ "$run_command" == ./* ]]; then
                        abs_binary="${artifact_path}/${run_command#./}"
                    else
                        abs_binary="$run_command"
                    fi
                    cat > "$wrapper_path" << WRAPPER_EOF
#!/usr/bin/env bash
exec "$abs_binary" "\$@"
WRAPPER_EOF
                else
                    # Invocation pattern (e.g., cargo run, python -m myapp)
                    cat > "$wrapper_path" << WRAPPER_EOF
#!/usr/bin/env bash
cd "$artifact_path" && exec $run_command "\$@"
WRAPPER_EOF
                fi
                chmod +x "$wrapper_path"
            else
                # No run_command — scan artifact_path/bin/ as fallback
                if [[ -d "${artifact_path}/bin" ]]; then
                    local f
                    for f in "${artifact_path}/bin/"*; do
                        if [[ -f "$f" ]] && [[ -x "$f" ]]; then
                            local name
                            name=$(basename "$f")
                            cat > "harness/.artifact-bin/${name}" << WRAPPER_EOF
#!/usr/bin/env bash
exec "$f" "\$@"
WRAPPER_EOF
                            chmod +x "harness/.artifact-bin/${name}"
                        fi
                    done
                fi
            fi

            __UAT_ARTIFACT_CONTEXT="CLI commands are available in harness/.artifact-bin/. Use these to invoke the artifact."
            ;;

        api)
            # Run install_command if provided
            if [[ -n "$install_command" ]]; then
                print_info "Running install command: $install_command"
                local install_output
                install_output=$(cd "$artifact_path" && eval "$install_command" 2>&1) || {
                    print_error "Install command failed: $install_output"
                    return 2
                }
            fi

            # Check if health_check is already responding (port in use)
            if [[ -n "$health_check" ]]; then
                if eval "$health_check" >/dev/null 2>&1; then
                    # Port is in use — check if it's our stale process
                    local port
                    port=$(echo "$health_check" | grep -o ':[0-9]*' | head -1 | tr -d ':')
                    if [[ -n "$port" ]]; then
                        local existing_pid
                        existing_pid=$(lsof -ti :"$port" 2>/dev/null | head -1)
                        if [[ -n "$existing_pid" ]]; then
                            if [[ -f "harness/.artifact-pid" ]]; then
                                local recorded_pid
                                recorded_pid=$(cat "harness/.artifact-pid" 2>/dev/null)
                                if [[ "$existing_pid" == "$recorded_pid" ]]; then
                                    print_info "Killing stale UAT server (PID $existing_pid)"
                                    kill "$existing_pid" 2>/dev/null || true
                                    sleep 1
                                else
                                    print_error "Port $port is in use by PID $existing_pid. Stop the conflicting process or change the artifact port."
                                    return 1
                                fi
                            else
                                print_error "Port $port is in use by PID $existing_pid. Stop the conflicting process or change the artifact port."
                                return 1
                            fi
                        fi
                    fi
                fi
            fi

            # Start the server in a new process group
            if [[ -n "$run_command" ]]; then
                print_info "Starting artifact server: $run_command"
                (cd "$artifact_path" && exec setsid $run_command) > results/server-stdout.log 2> results/server-stderr.log &
                __UAT_SERVER_PID=$!
                echo "$__UAT_SERVER_PID" > harness/.artifact-pid
                print_info "Server started with PID $__UAT_SERVER_PID"

                # Poll health_check until ready
                if [[ -n "$health_check" ]]; then
                    local hc_elapsed=0
                    print_info "Waiting for health check: $health_check (timeout: ${UAT_HEALTH_CHECK_TIMEOUT}s)"
                    while true; do
                        if [[ $hc_elapsed -ge $UAT_HEALTH_CHECK_TIMEOUT ]]; then
                            print_error "Health check timed out after ${UAT_HEALTH_CHECK_TIMEOUT}s"
                            uat_stop_server
                            return 2
                        fi
                        if eval "$health_check" >/dev/null 2>&1; then
                            print_success "Health check passed"
                            break
                        fi
                        sleep 1
                        hc_elapsed=$((hc_elapsed + 1))
                    done
                fi
            fi

            # Determine URL from health_check for context
            local server_url="$health_check"
            if [[ -z "$server_url" ]]; then
                server_url="http://localhost:8080"
            fi
            __UAT_ARTIFACT_CONTEXT="The API server is running at $server_url. Make HTTP requests to test it."
            ;;

        library)
            # Run install_command if provided
            if [[ -n "$install_command" ]]; then
                print_info "Running install command: $install_command"
                local install_output
                install_output=$(cd "$artifact_path" && eval "$install_command" 2>&1) || {
                    print_error "Install command failed: $install_output"
                    return 2
                }
            fi

            # Create harness/.artifact-env with environment setup
            local env_file="harness/.artifact-env"
            {
                # Detect language and set appropriate path vars
                if [[ -f "${artifact_path}/setup.py" ]] || [[ -f "${artifact_path}/pyproject.toml" ]]; then
                    # Python library
                    if [[ -d "${artifact_path}/src" ]]; then
                        echo "export PYTHONPATH=\"${artifact_path}/src:\${PYTHONPATH:-}\""
                    else
                        echo "export PYTHONPATH=\"${artifact_path}:\${PYTHONPATH:-}\""
                    fi
                elif [[ -f "${artifact_path}/package.json" ]]; then
                    # Node library
                    echo "export NODE_PATH=\"${artifact_path}/node_modules:\${NODE_PATH:-}\""
                fi
            } > "$env_file"

            __UAT_ARTIFACT_CONTEXT="Source harness/.artifact-env before running tests (\`source harness/.artifact-env\`). The library is importable from the UAT directory."
            ;;

        other)
            __UAT_ARTIFACT_CONTEXT="No artifact environment could be set up. Mark all scenarios as error with message: 'Set UAT_ARTIFACT_TYPE and UAT_RUN_COMMAND in .buildcrew/config'."
            ;;

        *)
            print_warning "Unknown artifact type: $artifact_type"
            __UAT_ARTIFACT_CONTEXT="No artifact environment could be set up. Unknown artifact type: $artifact_type."
            ;;
    esac

    print_success "Artifact environment set up (type=$artifact_type)"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 8. uat_phase_execute — Phase 5: Execute Scenarios (Claude agent)
# ═══════════════════════════════════════════════════════════════════════════════

uat_phase_execute() {
    local iteration="$1"
    local artifact_context="${2:-}"
    local failing_scenarios="${3:-}"

    print_header "UAT Phase 5: Execute Scenarios (Iteration $iteration)"

    local extra_context="$artifact_context"

    # On retry, pass failing scenario names
    if [[ -n "$failing_scenarios" ]]; then
        extra_context="$extra_context. RETRY MODE: Only re-execute these failing scenarios: ${failing_scenarios}. Carry forward all previous pass/disputed results unchanged."
    fi

    # Add iteration context
    extra_context="$extra_context. Write results to results/iteration-${iteration}/scenario-results.json."

    # Compute max_turns from timeout (rough approximation — 1 turn ~= 10 seconds)
    local max_turns=$((UAT_EXECUTE_TIMEOUT / 10))
    if [[ $max_turns -lt 10 ]]; then
        max_turns=10
    fi
    if [[ $max_turns -gt 100 ]]; then
        max_turns=100
    fi

    _uat_run_agent_phase "uat-execute" "Execute test scenarios against the artifact" "$extra_context"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 9. uat_phase_verdict — Phase 6: Write Verdict (Orchestrator only)
# ═══════════════════════════════════════════════════════════════════════════════

uat_phase_verdict() {
    local signal_dir="$1"
    local build_iteration="$2"

    if [[ -z "$signal_dir" || -z "$build_iteration" ]]; then
        print_error "uat_phase_verdict: signal_dir and build_iteration are required"
        return 1
    fi

    print_header "UAT Phase 6: Write Verdict"

    # Find the scenario results file
    local results_file="results/iteration-${build_iteration}/scenario-results.json"

    if [[ ! -f "$results_file" ]]; then
        print_error "Scenario results not found: $results_file"
        # Write error verdict for harness failure
        local error_json
        error_json=$(jq -n '[{"scenario":"harness_failure","status":"error","summary":"scenario-results.json not found after Phase 5 execution","expected":"Valid scenario results file","actual":"File missing"}]')
        write_verdict "$signal_dir" "$error_json" "$build_iteration"
        write_last_tested_iteration ".buildcrew" "$build_iteration"
        return 1
    fi

    # Validate scenario results with jq
    if ! validate_scenario_results "$results_file"; then
        print_error "Invalid scenario results: $results_file"
        local error_json
        error_json=$(jq -n '[{"scenario":"harness_failure","status":"error","summary":"scenario-results.json is malformed or contains invalid entries","expected":"Valid JSON array with required fields","actual":"Validation failed"}]')
        write_verdict "$signal_dir" "$error_json" "$build_iteration"
        write_last_tested_iteration ".buildcrew" "$build_iteration"
        return 1
    fi

    # Read scenario results
    local scenarios_json
    scenarios_json=$(jq -c '.' "$results_file")

    # Log disputes if any
    local disputed_count
    disputed_count=$(echo "$scenarios_json" | jq '[.[] | select(.status == "disputed")] | length')
    if [[ "$disputed_count" -gt 0 ]]; then
        print_info "Logging $disputed_count disputed scenarios to disputes.md"
        local i=0
        while [[ $i -lt $disputed_count ]]; do
            local scenario expected actual
            scenario=$(echo "$scenarios_json" | jq -r --argjson i "$i" '[.[] | select(.status == "disputed")][$i].scenario')
            expected=$(echo "$scenarios_json" | jq -r --argjson i "$i" '[.[] | select(.status == "disputed")][$i].expected // "Not specified"')
            actual=$(echo "$scenarios_json" | jq -r --argjson i "$i" '[.[] | select(.status == "disputed")][$i].actual // "Not specified"')
            log_dispute "disputes.md" "$scenario" "$expected" "$actual" "Is the actual behavior acceptable?"
            i=$((i + 1))
        done
    fi

    # Write verdict via uat_signal.sh
    write_verdict "$signal_dir" "$scenarios_json" "$build_iteration" || {
        print_error "Failed to write verdict"
        return 1
    }

    # Update last_tested_iteration
    write_last_tested_iteration ".buildcrew" "$build_iteration" || {
        print_error "Failed to update last_tested_iteration"
        return 1
    }

    # Print summary
    local total passed failed errored disputed
    total=$(echo "$scenarios_json" | jq 'length')
    passed=$(echo "$scenarios_json" | jq '[.[] | select(.status == "pass")] | length')
    failed=$(echo "$scenarios_json" | jq '[.[] | select(.status == "fail")] | length')
    errored=$(echo "$scenarios_json" | jq '[.[] | select(.status == "error")] | length')
    disputed=$(echo "$scenarios_json" | jq '[.[] | select(.status == "disputed")] | length')

    print_info "Verdict: total=$total passed=$passed failed=$failed errored=$errored disputed=$disputed"
    print_success "Verdict written for build iteration $build_iteration"

    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 10. uat_stop_server — Stop API server if running
# ═══════════════════════════════════════════════════════════════════════════════

uat_stop_server() {
    local pid_file="harness/.artifact-pid"

    if [[ ! -f "$pid_file" ]]; then
        __UAT_SERVER_PID=""
        return 0
    fi

    local pid
    pid=$(cat "$pid_file" 2>/dev/null)

    if [[ -z "$pid" ]]; then
        rm -f "$pid_file"
        __UAT_SERVER_PID=""
        return 0
    fi

    # Check if process is still running
    if ! kill -0 "$pid" 2>/dev/null; then
        print_debug "Server PID $pid is no longer running"
        rm -f "$pid_file"
        __UAT_SERVER_PID=""
        return 0
    fi

    print_info "Stopping server (PID $pid)"

    # Use stop_command if available (with $PID substitution via parameter expansion)
    if [[ -n "${__UAT_STOP_COMMAND:-}" ]]; then
        local cmd="${__UAT_STOP_COMMAND}"
        # Replace $PID with actual PID using parameter expansion (NOT eval)
        cmd="${cmd//\$PID/$pid}"
        if eval "$cmd" 2>/dev/null; then
            print_success "Server stopped via stop_command"
            rm -f "$pid_file"
            __UAT_SERVER_PID=""
            return 0
        fi
        print_warning "stop_command failed — falling back to process group kill"
    fi

    # Fallback: process group kill
    local pgid
    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    if [[ -n "$pgid" ]] && [[ "$pgid" != "0" ]]; then
        kill -- -"$pgid" 2>/dev/null || true
    else
        kill "$pid" 2>/dev/null || true
    fi

    # Wait briefly for process to exit
    local waited=0
    while kill -0 "$pid" 2>/dev/null && [[ $waited -lt 5 ]]; do
        sleep 1
        waited=$((waited + 1))
    done

    if kill -0 "$pid" 2>/dev/null; then
        print_warning "Server PID $pid did not stop — sending SIGKILL"
        kill -9 "$pid" 2>/dev/null || true
    fi

    rm -f "$pid_file"
    __UAT_SERVER_PID=""
    print_success "Server stopped"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 11. uat_cleanup — Cleanup trap
# ═══════════════════════════════════════════════════════════════════════════════

uat_cleanup() {
    # Stop any running server
    uat_stop_server

    # Stop file monitor (in case it's still running)
    stop_file_monitor

    # Clear temp files
    rm -f "$UAT_PHASE_RESULT_FILE" 2>/dev/null || true
}
