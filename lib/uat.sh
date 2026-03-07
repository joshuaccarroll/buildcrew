#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BuildCrew - UAT Orchestrator
# https://github.com/joshuaccarroll/buildcrew
# ═══════════════════════════════════════════════════════════════════════════════
#
# Manages the UAT (User Acceptance Testing) phase pipeline. Handles:
#   - UAT directory initialization
#   - Server lifecycle management (start, health-check, stop)
#   - Individual phase functions (stories, scenarios, harness, setup, execute, verdict)
#   - Regress mode (single-pass execution via uat_run_regress)
#
# Actors:
#   - UAT orchestrator: directory init, server lifecycle, file monitoring, verdict writing
#   - Inline UAT (workflow.sh): phase sequencing, retry loop, restart recovery
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
# Note: artifact.sh is sourced by the caller (workflow.sh), not by uat.sh.
# In inline mode, workflow.sh handles artifact publishing directly.

# ─────────────────────────────────────────────────────────────────────────────────
# UAT Configuration defaults
# ─────────────────────────────────────────────────────────────────────────────────

UAT_POLL_INTERVAL="${UAT_POLL_INTERVAL:-5}"
UAT_ARTIFACT_TIMEOUT="${UAT_ARTIFACT_TIMEOUT:-7200}"
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

# sha256_hash and read_config_key are now in common.sh (sourced above)

# ─────────────────────────────────────────────────────────────────────────────────
# _uat_make_error_verdict — construct a synthetic error verdict JSON array
# ─────────────────────────────────────────────────────────────────────────────────
# Args: scenario, summary, expected, actual
# Outputs: JSON array with a single error entry

_uat_make_error_verdict() {
    local scenario="$1" summary="$2" expected="$3" actual="$4"
    jq -n --arg s "$scenario" --arg sum "$summary" --arg exp "$expected" --arg act "$actual" \
        '[{"scenario":$s,"status":"error","summary":$sum,"expected":$exp,"actual":$act}]'
}

# ─────────────────────────────────────────────────────────────────────────────────
# UAT Display Utilities
# ─────────────────────────────────────────────────────────────────────────────────

# _uat_format_duration — format seconds as human-readable duration
# Args: total_seconds
# Output: "Ys" for < 60, "Xm YYs" for 60-3599, "Xh YYm ZZs" for >= 3600
_uat_format_duration() {
    local total="$1"

    # Guard against non-numeric input
    if ! [[ "$total" =~ ^[0-9]+$ ]]; then
        echo "?"
        return 0
    fi

    if [[ $total -lt 60 ]]; then
        echo "${total}s"
    elif [[ $total -lt 3600 ]]; then
        local mins=$((total / 60))
        local secs=$((total % 60))
        printf '%dm %02ds\n' "$mins" "$secs"
    else
        local hours=$((total / 3600))
        local mins=$(( (total % 3600) / 60 ))
        local secs=$((total % 60))
        printf '%dh %02dm %02ds\n' "$hours" "$mins" "$secs"
    fi
}

# _uat_list_scenarios — list scenarios discovered from scenarios/*.md files
# Skips user-stories.md (input file). Handles Bash 3.2 nullglob.
_uat_list_scenarios() {
    # Collect scenario files (excluding user-stories.md)
    local files=()
    local f
    for f in scenarios/*.md; do
        [[ -f "$f" ]] || continue
        [[ "$(basename "$f")" == "user-stories.md" ]] && continue
        files+=("$f")
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        print_info "No scenarios found"
        return 0
    fi

    # Extract scenario names from ## Scenario: headers
    local names=()
    local line
    while IFS= read -r line; do
        names+=("$line")
    done < <(grep -h '^## Scenario: ' "${files[@]}" 2>/dev/null | sed 's/^## Scenario: //')

    if [[ ${#names[@]} -eq 0 ]]; then
        print_info "No scenarios found"
        return 0
    fi

    print_info "Scenarios discovered:"
    local i=1
    for line in "${names[@]}"; do
        echo "  ${i}. ${line}"
        i=$((i + 1))
    done
    print_info "Total: ${#names[@]} scenarios"
    return 0
}

# _uat_print_scenario_table — print color-coded scenario results table
# Args: scenarios_json (JSON array string)
_uat_print_scenario_table() {
    local scenarios_json="$1"

    # Guard against empty/null input
    if [[ -z "$scenarios_json" ]] || [[ "$scenarios_json" == "null" ]] || [[ "$scenarios_json" == "[]" ]]; then
        echo "  No scenario results"
        return 0
    fi

    echo "  Scenario Results:"
    echo "  ─────────────────────────────────────────────────────"

    local scenario status summary status_label
    while IFS=$'\t' read -r scenario status summary; do
        case "$status" in
            pass)     status_label="${GREEN}PASS${NC}" ;;
            fail)     status_label="${RED}FAIL${NC}" ;;
            error)    status_label="${RED}ERR ${NC}" ;;
            disputed) status_label="${YELLOW}DISP${NC}" ;;
            *)        status_label="????"; ;;
        esac
        printf '  %b  %s\n' "$status_label" "$scenario"
        if [[ "$status" != "pass" ]] && [[ -n "$summary" ]] && [[ "$summary" != "(no summary)" ]]; then
            # Truncate long summaries at 80 chars
            if [[ ${#summary} -gt 80 ]]; then
                summary="${summary:0:77}..."
            fi
            printf '        %s\n' "$summary"
        fi
    done < <(echo "$scenarios_json" | jq -r '.[] | [.scenario, .status, (.summary // "(no summary)")] | @tsv')

    return 0
}

# _uat_print_retry_context — print which scenarios failed/errored for retry
# Args: scenarios_json (JSON array string)
_uat_print_retry_context() {
    local scenarios_json="$1"

    # Guard against empty/null input
    if [[ -z "$scenarios_json" ]] || [[ "$scenarios_json" == "null" ]] || [[ "$scenarios_json" == "[]" ]]; then
        return 0
    fi

    # Filter to only fail/error entries
    local filtered
    filtered=$(echo "$scenarios_json" | jq -r '[.[] | select(.status == "fail" or .status == "error")] | .[] | [.scenario, .status, (.summary // "(no summary)")] | @tsv' 2>/dev/null)

    if [[ -z "$filtered" ]]; then
        return 0
    fi

    echo "  Scenarios to retry:"
    local scenario status summary status_label
    while IFS=$'\t' read -r scenario status summary; do
        case "$status" in
            fail)  status_label="${RED}FAIL${NC}" ;;
            error) status_label="${RED}ERR ${NC}" ;;
            *)     status_label="????"; ;;
        esac
        if [[ -n "$summary" ]] && [[ "$summary" != "(no summary)" ]]; then
            # Truncate long summaries
            if [[ ${#summary} -gt 80 ]]; then
                summary="${summary:0:77}..."
            fi
            printf '  %b  %s — %s\n' "$status_label" "$scenario" "$summary"
        else
            printf '  %b  %s\n' "$status_label" "$scenario"
        fi
    done <<< "$filtered"

    return 0
}

# _uat_print_report — print structured UAT post-run report
# Args: signal_dir, run_start_time
_uat_print_report() {
    local signal_dir="$1"
    local run_start_time="${2:-}"

    # Only read verdict from disk if globals are not already populated
    if [[ -z "${__VERDICT_STATUS:-}" ]]; then
        read_verdict "$signal_dir" || {
            print_warning "Could not read verdict for report"
            return 0
        }
    fi

    # Status label
    local status_label="$__VERDICT_STATUS"
    case "$__VERDICT_STATUS" in
        pass) status_label="${GREEN}PASS${NC}" ;;
        fail) status_label="${RED}FAIL${NC}" ;;
        error) status_label="${RED}ERROR${NC}" ;;
        disputed) status_label="${YELLOW}DISPUTED${NC}" ;;
    esac

    echo ""
    echo -e "═══════════════════════════════════════"
    echo -e "   ${BOLD}UAT Report${NC}"
    echo -e "═══════════════════════════════════════"
    printf '  Status:     %b\n' "$status_label"
    echo "  Iteration:  ${__VERDICT_BUILD_ITERATION:-?}"

    # Duration (only if run_start_time is set and numeric)
    if [[ -n "$run_start_time" ]] && [[ "$run_start_time" =~ ^[0-9]+$ ]]; then
        local run_end; run_end=$(date +%s)
        echo "  Duration:   $(_uat_format_duration $((run_end - run_start_time)))"
    fi

    echo ""
    echo "  Results:"
    echo "    Passed:   ${__VERDICT_PASSED:-0}"
    echo "    Failed:   ${__VERDICT_FAILED:-0}"
    echo "    Errored:  ${__VERDICT_ERRORED:-0}"
    echo "    Disputed: ${__VERDICT_DISPUTED:-0}"
    echo "    Total:    ${__VERDICT_TOTAL:-0}"
    echo ""

    _uat_print_scenario_table "$__VERDICT_SCENARIOS_JSON"

    if [[ "${__VERDICT_DISPUTED:-0}" -gt 0 ]]; then
        echo ""
        echo "  See disputes.md for disputed scenario details."
    fi
    echo ""
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
    readme_hash=$(sha256_hash README.md) || {
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
# _uat_regress_set_artifact — Set artifact globals from a local directory
# (used by regress mode to set artifact globals from a local directory)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Args:
#   regress_path — absolute path to the artifact directory
#   readme_path  — path to the README (for hash computation)
#
# Sets globals: __UAT_ARTIFACT_PATH, __UAT_ARTIFACT_TYPE, __UAT_RUN_COMMAND,
#   __UAT_INSTALL_COMMAND, __UAT_HEALTH_CHECK, __UAT_STOP_COMMAND,
#   __UAT_BUILD_ITERATION, __UAT_README_HASH

_uat_regress_set_artifact() {
    local regress_path="${1:-}"
    local readme_path="${2:-}"

    if [[ -z "$regress_path" ]]; then
        print_error "_uat_regress_set_artifact: regress_path is required"
        return 1
    fi

    # Reset globals
    __UAT_ARTIFACT_TYPE=""
    __UAT_ARTIFACT_PATH=""
    __UAT_RUN_COMMAND=""
    __UAT_INSTALL_COMMAND=""
    __UAT_HEALTH_CHECK=""
    __UAT_STOP_COMMAND=""
    __UAT_BUILD_ITERATION=""
    __UAT_README_HASH=""

    # Set artifact path
    __UAT_ARTIFACT_PATH="$regress_path"

    # Read config overrides from .buildcrew/config via read_config_key (common.sh)
    local v
    v=$(read_config_key "UAT_ARTIFACT_TYPE");   [[ -n "$v" ]] && __UAT_ARTIFACT_TYPE="$v"
    v=$(read_config_key "UAT_RUN_COMMAND");     [[ -n "$v" ]] && __UAT_RUN_COMMAND="$v"
    v=$(read_config_key "UAT_INSTALL_COMMAND"); [[ -n "$v" ]] && __UAT_INSTALL_COMMAND="$v"
    v=$(read_config_key "UAT_HEALTH_CHECK");    [[ -n "$v" ]] && __UAT_HEALTH_CHECK="$v"
    v=$(read_config_key "UAT_STOP_COMMAND");    [[ -n "$v" ]] && __UAT_STOP_COMMAND="$v"

    # Default artifact type to "cli" if not set
    if [[ -z "$__UAT_ARTIFACT_TYPE" ]]; then
        __UAT_ARTIFACT_TYPE="cli"
    fi

    # Compute iteration = last_tested + 1
    local last_tested
    last_tested=$(read_last_tested_iteration ".buildcrew")
    __UAT_BUILD_ITERATION=$((last_tested + 1))

    # Compute README hash
    if [[ -n "$readme_path" ]] && [[ -f "$readme_path" ]]; then
        __UAT_README_HASH=$(sha256_hash "$readme_path") || __UAT_README_HASH=""
    fi

    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2. uat_run_regress — Single-pass regression test against an existing artifact
# ═══════════════════════════════════════════════════════════════════════════════
#
# Args:
#   readme_path  — path to the project's README.md
#   project_name — project identifier (used for signal directory)
#   regress_path — absolute path to the artifact directory to test
#
# Returns:
#   0 = all scenarios passed
#   1 = failures/errors or fatal error
#   2 = only disputed scenarios (no failures/errors)

uat_run_regress() {
    local readme_path="$1"
    local project_name="$2"
    local regress_path="$3"

    if [[ -z "$readme_path" || -z "$project_name" ]]; then
        print_error "uat_run_regress: readme_path and project_name are required"
        return 1
    fi

    if [[ -z "$regress_path" ]]; then
        print_error "uat_run_regress: regress_path is required"
        return 1
    fi

    # Load config
    load_uat_config

    local run_start_time; run_start_time=$(date +%s)

    # Set up cleanup trap
    trap 'uat_cleanup; exit 130' INT TERM
    trap 'uat_cleanup' EXIT

    # Initialize logging
    log_init

    # ── Restart recovery ──────────────────────────────────────────────────────

    local need_phases_1_3=true
    local last_hash=""

    if [[ -f .buildcrew/last_readme_hash ]]; then
        last_hash=$(cat .buildcrew/last_readme_hash 2>/dev/null)
    fi

    local current_hash
    current_hash=$(sha256_hash "$readme_path") || {
        print_error "uat_run_regress: failed to compute README hash"
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
        _uat_list_scenarios
        uat_phase_harness || return 1
    else
        _uat_list_scenarios
    fi

    # ── Single-pass execution ─────────────────────────────────────────────────

    _uat_regress_set_artifact "$regress_path" "$readme_path" || return 1

    local build_iteration="$__UAT_BUILD_ITERATION"
    local signal_dir="${HOME}/.buildcrew/uat-signals/${project_name}"

    # Phase 4.5: Set up artifact environment
    uat_phase_setup_env \
        "$__UAT_ARTIFACT_TYPE" \
        "$__UAT_ARTIFACT_PATH" \
        "$__UAT_RUN_COMMAND" \
        "$__UAT_INSTALL_COMMAND" \
        "$__UAT_HEALTH_CHECK" || {
        local setup_rc=$?
        if [[ $setup_rc -eq 2 ]]; then
            uat_stop_server
            print_error "Artifact setup failed in regress mode"
            return 1
        fi
        return 1
    }
    local artifact_context="$__UAT_ARTIFACT_CONTEXT"

    # Clean up partial results from a previous crash at this iteration
    local results_dir="results/iteration-${build_iteration}"
    if [[ -d "$results_dir" ]] && [[ ! -f "${results_dir}/scenario-results.json" ]]; then
        print_info "Clearing partial results directory: $results_dir"
        rm -rf "$results_dir"
    fi
    mkdir -p "$results_dir"

    # Phase 5: Execute scenarios
    uat_phase_execute "$build_iteration" "$artifact_context" "" || {
        uat_stop_server
        print_error "Phase 5 execution failed in regress mode"
        return 1
    }

    # Stop server after execution (for api type)
    uat_stop_server

    # Phase 6: Write verdict
    uat_phase_verdict "$signal_dir" "$build_iteration" || {
        _uat_print_report "$signal_dir" "$run_start_time"
        return 1
    }

    # Read the verdict to determine return code
    read_verdict "$signal_dir" || {
        print_error "Failed to read verdict after writing"
        return 1
    }

    if [[ "$__VERDICT_STATUS" == "pass" ]]; then
        print_success "All scenarios passed!"
        _uat_print_report "$signal_dir" "$run_start_time"
        return 0
    fi

    # Check for only disputes remaining (no failures or errors)
    if [[ "$__VERDICT_FAILED" -eq 0 ]] && [[ "$__VERDICT_ERRORED" -eq 0 ]] && [[ "$__VERDICT_DISPUTED" -gt 0 ]]; then
        _uat_print_report "$signal_dir" "$run_start_time"
        return 2
    fi

    # Failures or errors
    print_error "Regress mode: ${__VERDICT_FAILED} failures, ${__VERDICT_ERRORED} errors"
    _uat_print_report "$signal_dir" "$run_start_time"
    return 1
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
    local phase_start; phase_start=$(date +%s)

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

    local resolved_model
    resolved_model=$(resolve_phase_model "$phase_name")
    local model_effort_flags=""
    model_effort_flags+=" --model $resolved_model"
    [[ -n "${CLAUDE_EFFORT:-}" ]] && model_effort_flags+=" --effort $CLAUDE_EFFORT"

    # Save terminal state
    local __saved_stty=""
    if [[ -t 0 ]]; then
        __saved_stty=$(stty -g 2>/dev/null) || __saved_stty=""
    fi

    # Start file monitor
    start_file_monitor "$UAT_PHASE_RESULT_FILE" "claude.*${phase_tag}"

    update_workflow_state "$phase_name" "running" "$resolved_model"
    print_info "Phase: $phase_name (max $max_turns turns)"
    log_msg "=== UAT PHASE: $phase_name started (max_turns=$max_turns) ==="

    # Invoke Claude agent
    if [[ -n "${__LOG_FILE:-}" ]]; then
        log_msg "--- claude output start: $phase_name ---"
        claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag $model_effort_flags 2>&1 | tee -a "$__LOG_FILE" || true
        log_msg "--- claude output end: $phase_name ---"
    else
        claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag $model_effort_flags || true
    fi

    stop_file_monitor
    # Restore terminal state
    [[ -n "$__saved_stty" ]] && stty "$__saved_stty" 2>/dev/null || true

    # Validate result (with one retry on failure)
    if [[ ! -f "$UAT_PHASE_RESULT_FILE" ]] || ! jq -e . "$UAT_PHASE_RESULT_FILE" >/dev/null 2>&1; then
        print_warning "Phase $phase_name produced no valid result. Retrying..."
        rm -f "$UAT_PHASE_RESULT_FILE"

        start_file_monitor "$UAT_PHASE_RESULT_FILE" "claude.*${phase_tag}"

        update_workflow_state "$phase_name" "running" "$resolved_model"
        log_msg "=== UAT PHASE: $phase_name retry ==="
        if [[ -n "${__LOG_FILE:-}" ]]; then
            log_msg "--- claude output start: $phase_name ---"
            claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag $model_effort_flags 2>&1 | tee -a "$__LOG_FILE" || true
            log_msg "--- claude output end: $phase_name ---"
        else
            claude -p "$prompt" --max-turns "$max_turns" $allowed_tools_flag $model_effort_flags || true
        fi

        stop_file_monitor
        [[ -n "$__saved_stty" ]] && stty "$__saved_stty" 2>/dev/null || true

        if [[ ! -f "$UAT_PHASE_RESULT_FILE" ]] || ! jq -e . "$UAT_PHASE_RESULT_FILE" >/dev/null 2>&1; then
            local phase_end; phase_end=$(date +%s)
            print_info "Phase $phase_name completed in $(_uat_format_duration $((phase_end - phase_start)))"
            print_error "Phase $phase_name failed after retry"
            update_workflow_state "$phase_name" "failed" "$resolved_model"
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
        local phase_end; phase_end=$(date +%s)
        print_info "Phase $phase_name completed in $(_uat_format_duration $((phase_end - phase_start)))"
        print_error "Phase $phase_name verdict: fail — $details"
        update_workflow_state "$phase_name" "failed" "$resolved_model"
        return 1
    fi

    local phase_end; phase_end=$(date +%s)
    print_info "Phase $phase_name completed in $(_uat_format_duration $((phase_end - phase_start)))"
    update_workflow_state "$phase_name" "complete" "$resolved_model"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 6. uat_phase_setup_env — Phase 4.5: Set Up Artifact Environment
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

            __UAT_ARTIFACT_CONTEXT="Artifact type: cli. CLI commands are available in harness/.artifact-bin/. Use these to invoke the artifact."
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
            __UAT_ARTIFACT_CONTEXT="Artifact type: api. The API server is running at $server_url. Make HTTP requests to test it."
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

            __UAT_ARTIFACT_CONTEXT="Artifact type: library. Source harness/.artifact-env before running tests (\`source harness/.artifact-env\`). The library is importable from the UAT directory."
            ;;

        other)
            __UAT_ARTIFACT_CONTEXT="Artifact type: other. No artifact environment could be set up. Mark all scenarios as error with message: 'Set UAT_ARTIFACT_TYPE and UAT_RUN_COMMAND in .buildcrew/config'."
            ;;

        *)
            print_warning "Unknown artifact type: $artifact_type"
            __UAT_ARTIFACT_CONTEXT="Artifact type: $artifact_type. No artifact environment could be set up. Unknown artifact type: $artifact_type."
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
    local verdict_start; verdict_start=$(date +%s)

    # Find the scenario results file
    local results_file="results/iteration-${build_iteration}/scenario-results.json"

    if [[ ! -f "$results_file" ]]; then
        print_error "Scenario results not found: $results_file"
        # Write error verdict for harness failure
        local error_json
        error_json=$(_uat_make_error_verdict "harness_failure" "scenario-results.json not found after Phase 5 execution" "Valid scenario results file" "File missing")
        write_verdict "$signal_dir" "$error_json" "$build_iteration"
        write_last_tested_iteration ".buildcrew" "$build_iteration"
        return 1
    fi

    # Validate scenario results with jq
    if ! validate_scenario_results "$results_file"; then
        print_error "Invalid scenario results: $results_file"
        local error_json
        error_json=$(_uat_make_error_verdict "harness_failure" "scenario-results.json is malformed or contains invalid entries" "Valid JSON array with required fields" "Validation failed")
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
    _uat_print_scenario_table "$scenarios_json"
    print_success "Verdict written for build iteration $build_iteration"

    local verdict_end; verdict_end=$(date +%s)
    print_info "Phase verdict completed in $(_uat_format_duration $((verdict_end - verdict_start)))"

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

__uat_cleaned=false
uat_cleanup() {
    [[ "$__uat_cleaned" == "true" ]] && return
    __uat_cleaned=true

    # Stop any running server
    uat_stop_server

    # Stop file monitor (in case it's still running)
    stop_file_monitor

    # Clear temp files
    rm -f "$UAT_PHASE_RESULT_FILE" 2>/dev/null || true

    # Remove stale artifact directory for this project
    if [[ -n "${UAT_PROJECT_NAME:-}" ]]; then
        local artifact_dir="${UAT_ARTIFACT_DIR:-${HOME}/.buildcrew/artifacts}/${UAT_PROJECT_NAME}"
        rm -rf "$artifact_dir" 2>/dev/null || true
    fi
}
