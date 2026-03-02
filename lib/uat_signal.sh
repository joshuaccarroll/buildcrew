#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BuildCrew - UAT Signal File Management
# https://github.com/joshuaccarroll/buildcrew
# ═══════════════════════════════════════════════════════════════════════════════
#
# Manages signal files for cross-process communication between the build
# orchestrator and UAT orchestrator. Handles:
#   - Signal directory creation/cleanup
#   - Verdict writing (UAT side -> Build side)
#   - Verdict reading (Build side reads from UAT)
#   - Iteration tracking (last tested / last processed counters)
#   - Scenario results validation
#   - Dispute logging
#
# This file must NOT set shell options (set -e, set -u, etc.) because callers
# have different shell option requirements.
#
# ═══════════════════════════════════════════════════════════════════════════════

# Source guard — prevent double-sourcing
[[ -n "${__BUILDCREW_UAT_SIGNAL_LOADED:-}" ]] && return 0
__BUILDCREW_UAT_SIGNAL_LOADED=1

# Source common.sh for print helpers (resolve relative to this file's location)
__UAT_SIGNAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$__UAT_SIGNAL_DIR/common.sh"

# ─────────────────────────────────────────────────────────────────────────────────
# Globals set by read_verdict()
# ─────────────────────────────────────────────────────────────────────────────────

__VERDICT_STATUS=""
__VERDICT_BUILD_ITERATION=""
__VERDICT_TOTAL=""
__VERDICT_PASSED=""
__VERDICT_FAILED=""
__VERDICT_ERRORED=""
__VERDICT_DISPUTED=""
__VERDICT_SCENARIOS_JSON=""

# ─────────────────────────────────────────────────────────────────────────────────
# Signal Directory Management
# ─────────────────────────────────────────────────────────────────────────────────

# create_signal_dir — Create the UAT signal directory for a project.
# Args: project_name
# Creates ~/.buildcrew/uat-signals/<project>/
# Returns 0 on success, 1 on failure.
create_signal_dir() {
    local project_name="$1"

    if [[ -z "$project_name" ]]; then
        print_error "create_signal_dir: project_name is required"
        return 1
    fi

    local signal_dir="${HOME}/.buildcrew/uat-signals/${project_name}"
    if ! mkdir -p "$signal_dir"; then
        print_error "create_signal_dir: failed to create $signal_dir"
        return 1
    fi

    return 0
}

# signal_dir_exists — Check if the UAT signal directory exists for a project.
# Args: project_name
# Returns 0 if exists, 1 if not.
signal_dir_exists() {
    local project_name="$1"

    if [[ -z "$project_name" ]]; then
        return 1
    fi

    local signal_dir="${HOME}/.buildcrew/uat-signals/${project_name}"
    [[ -d "$signal_dir" ]]
}

# clean_signal_dir — Remove signal directory contents except verdict.json.
# Args: project_name
# Removes all files in the signal directory except verdict.json (which may
# still be needed by the build orchestrator).
# Returns 0 on success, 1 on failure.
clean_signal_dir() {
    local project_name="$1"

    if [[ -z "$project_name" ]]; then
        print_error "clean_signal_dir: project_name is required"
        return 1
    fi

    local signal_dir="${HOME}/.buildcrew/uat-signals/${project_name}"

    if [[ ! -d "$signal_dir" ]]; then
        print_warning "clean_signal_dir: directory does not exist: $signal_dir"
        return 0
    fi

    # Remove everything except verdict.json
    local item
    for item in "$signal_dir"/*; do
        # Handle empty directory (glob returns literal pattern)
        [[ -e "$item" ]] || continue
        local basename
        basename="$(basename "$item")"
        if [[ "$basename" != "verdict.json" ]]; then
            rm -rf "$item"
        fi
    done

    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────
# Verdict Writing (UAT side -> Build side)
# ─────────────────────────────────────────────────────────────────────────────────

# write_verdict — Assemble and write verdict.json from scenario results.
# Args: signal_dir scenarios_json build_iteration
#   signal_dir      — Path to the signal directory
#   scenarios_json  — JSON array string of scenario results
#   build_iteration — The build iteration number this verdict corresponds to
#
# Computes counts (total, passed, failed, errored, disputed), determines
# top-level status by precedence (fail > error > disputed > pass), includes
# UTC ISO 8601 timestamp. Writes atomically (write to .tmp, then mv).
#
# Returns 0 on success, 1 on failure.
write_verdict() {
    local signal_dir="$1"
    local scenarios_json="$2"
    local build_iteration="$3"

    if [[ -z "$signal_dir" || -z "$scenarios_json" || -z "$build_iteration" ]]; then
        print_error "write_verdict: signal_dir, scenarios_json, and build_iteration are required"
        return 1
    fi

    if [[ ! -d "$signal_dir" ]]; then
        print_error "write_verdict: signal directory does not exist: $signal_dir"
        return 1
    fi

    # Validate scenarios_json is a valid JSON array
    if ! echo "$scenarios_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        print_error "write_verdict: scenarios_json is not a valid JSON array"
        return 1
    fi

    # Compute counts using jq
    local total passed failed errored disputed
    total=$(echo "$scenarios_json" | jq 'length')
    passed=$(echo "$scenarios_json" | jq '[.[] | select(.status == "pass")] | length')
    failed=$(echo "$scenarios_json" | jq '[.[] | select(.status == "fail")] | length')
    errored=$(echo "$scenarios_json" | jq '[.[] | select(.status == "error")] | length')
    disputed=$(echo "$scenarios_json" | jq '[.[] | select(.status == "disputed")] | length')

    # Determine top-level status by precedence: fail > error > disputed > pass
    local status="pass"
    if [[ "$disputed" -gt 0 ]]; then
        status="disputed"
    fi
    if [[ "$errored" -gt 0 ]]; then
        status="error"
    fi
    if [[ "$failed" -gt 0 ]]; then
        status="fail"
    fi

    # Generate UTC ISO 8601 timestamp
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    # Assemble verdict JSON using jq
    local verdict_json
    verdict_json=$(jq -n \
        --arg timestamp "$timestamp" \
        --arg status "$status" \
        --argjson build_iteration "$build_iteration" \
        --argjson total "$total" \
        --argjson passed "$passed" \
        --argjson failed "$failed" \
        --argjson errored "$errored" \
        --argjson disputed "$disputed" \
        --argjson scenarios "$scenarios_json" \
        '{
            timestamp: $timestamp,
            status: $status,
            build_iteration: $build_iteration,
            total: $total,
            passed: $passed,
            failed: $failed,
            errored: $errored,
            disputed: $disputed,
            scenarios: $scenarios
        }')

    # Atomic write: write to .tmp, then mv
    local verdict_file="${signal_dir}/verdict.json"
    local tmp_file="${verdict_file}.tmp"

    if ! echo "$verdict_json" > "$tmp_file"; then
        print_error "write_verdict: failed to write temporary file: $tmp_file"
        return 1
    fi

    if ! mv "$tmp_file" "$verdict_file"; then
        print_error "write_verdict: failed to move $tmp_file to $verdict_file"
        rm -f "$tmp_file"
        return 1
    fi

    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────
# Verdict Reading (Build side reads from UAT)
# ─────────────────────────────────────────────────────────────────────────────────

# read_verdict — Read and validate verdict.json, setting global variables.
# Args: signal_dir
#
# Sets globals: __VERDICT_STATUS, __VERDICT_BUILD_ITERATION, __VERDICT_TOTAL,
#   __VERDICT_PASSED, __VERDICT_FAILED, __VERDICT_ERRORED, __VERDICT_DISPUTED,
#   __VERDICT_SCENARIOS_JSON
#
# Returns 0 on success, 1 on missing file or invalid JSON.
read_verdict() {
    local signal_dir="$1"

    # Clear globals
    __VERDICT_STATUS=""
    __VERDICT_BUILD_ITERATION=""
    __VERDICT_TOTAL=""
    __VERDICT_PASSED=""
    __VERDICT_FAILED=""
    __VERDICT_ERRORED=""
    __VERDICT_DISPUTED=""
    __VERDICT_SCENARIOS_JSON=""

    if [[ -z "$signal_dir" ]]; then
        print_error "read_verdict: signal_dir is required"
        return 1
    fi

    local verdict_file="${signal_dir}/verdict.json"

    if [[ ! -f "$verdict_file" ]]; then
        print_debug "read_verdict: verdict file not found: $verdict_file"
        return 1
    fi

    # Validate JSON with jq
    if ! jq -e . "$verdict_file" >/dev/null 2>&1; then
        print_error "read_verdict: invalid JSON in $verdict_file"
        return 1
    fi

    # Extract fields using jq
    __VERDICT_STATUS=$(jq -r '.status // ""' "$verdict_file")
    __VERDICT_BUILD_ITERATION=$(jq -r '.build_iteration // ""' "$verdict_file")
    __VERDICT_TOTAL=$(jq -r '.total // ""' "$verdict_file")
    __VERDICT_PASSED=$(jq -r '.passed // ""' "$verdict_file")
    __VERDICT_FAILED=$(jq -r '.failed // ""' "$verdict_file")
    __VERDICT_ERRORED=$(jq -r '.errored // ""' "$verdict_file")
    __VERDICT_DISPUTED=$(jq -r '.disputed // ""' "$verdict_file")
    __VERDICT_SCENARIOS_JSON=$(jq -c '.scenarios // []' "$verdict_file")

    # Validate required fields
    if [[ -z "$__VERDICT_STATUS" || -z "$__VERDICT_BUILD_ITERATION" ]]; then
        print_error "read_verdict: missing required fields (status, build_iteration)"
        return 1
    fi

    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────
# Iteration Tracking
# ─────────────────────────────────────────────────────────────────────────────────

# read_last_tested_iteration — Read the last tested iteration counter.
# Args: buildcrew_dir — Path to the .buildcrew directory
# Echoes the iteration number (defaults to 0 if file missing).
# Returns 0.
read_last_tested_iteration() {
    local buildcrew_dir="$1"
    local iter_file="${buildcrew_dir}/last_tested_iteration"

    if [[ -f "$iter_file" ]]; then
        local val
        val=$(cat "$iter_file" 2>/dev/null)
        if [[ "$val" =~ ^[0-9]+$ ]]; then
            echo "$val"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
    return 0
}

# write_last_tested_iteration — Write the last tested iteration counter.
# Args: buildcrew_dir iteration
# Writes atomically (write to .tmp, then mv).
# Returns 0 on success, 1 on failure.
write_last_tested_iteration() {
    local buildcrew_dir="$1"
    local iteration="$2"

    if [[ -z "$buildcrew_dir" || -z "$iteration" ]]; then
        print_error "write_last_tested_iteration: buildcrew_dir and iteration are required"
        return 1
    fi

    local iter_file="${buildcrew_dir}/last_tested_iteration"
    local tmp_file="${iter_file}.tmp"

    if ! echo "$iteration" > "$tmp_file"; then
        print_error "write_last_tested_iteration: failed to write $tmp_file"
        return 1
    fi

    if ! mv "$tmp_file" "$iter_file"; then
        print_error "write_last_tested_iteration: failed to move $tmp_file to $iter_file"
        rm -f "$tmp_file"
        return 1
    fi

    return 0
}

# read_last_processed_iteration — Read the last processed UAT iteration counter.
# Args: buildcrew_dir — Path to the .buildcrew directory
# Echoes the iteration number (defaults to 0 if file missing).
# Returns 0.
read_last_processed_iteration() {
    local buildcrew_dir="$1"
    local iter_file="${buildcrew_dir}/last_processed_uat_iteration"

    if [[ -f "$iter_file" ]]; then
        local val
        val=$(cat "$iter_file" 2>/dev/null)
        if [[ "$val" =~ ^[0-9]+$ ]]; then
            echo "$val"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
    return 0
}

# write_last_processed_iteration — Write the last processed UAT iteration counter.
# Args: buildcrew_dir iteration
# Writes atomically (write to .tmp, then mv).
# Returns 0 on success, 1 on failure.
write_last_processed_iteration() {
    local buildcrew_dir="$1"
    local iteration="$2"

    if [[ -z "$buildcrew_dir" || -z "$iteration" ]]; then
        print_error "write_last_processed_iteration: buildcrew_dir and iteration are required"
        return 1
    fi

    local iter_file="${buildcrew_dir}/last_processed_uat_iteration"
    local tmp_file="${iter_file}.tmp"

    if ! echo "$iteration" > "$tmp_file"; then
        print_error "write_last_processed_iteration: failed to write $tmp_file"
        return 1
    fi

    if ! mv "$tmp_file" "$iter_file"; then
        print_error "write_last_processed_iteration: failed to move $tmp_file to $iter_file"
        rm -f "$tmp_file"
        return 1
    fi

    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────
# Scenario Results Validation
# ─────────────────────────────────────────────────────────────────────────────────

# validate_scenario_results — Validate scenario-results.json file.
# Args: results_file — Path to scenario-results.json
#
# Validates:
#   - Must be a JSON array
#   - Each element must have: scenario (string), status (one of pass/fail/error/disputed), summary (string)
#
# Returns 0 on valid, 1 on invalid.
validate_scenario_results() {
    local results_file="$1"

    if [[ -z "$results_file" ]]; then
        print_error "validate_scenario_results: results_file is required"
        return 1
    fi

    if [[ ! -f "$results_file" ]]; then
        print_error "validate_scenario_results: file not found: $results_file"
        return 1
    fi

    # Validate it is a JSON array
    if ! jq -e 'type == "array"' "$results_file" >/dev/null 2>&1; then
        print_error "validate_scenario_results: not a JSON array: $results_file"
        return 1
    fi

    # Validate each element has required fields with correct types/values
    # Returns "true" if all elements are valid, "false" otherwise
    local valid
    valid=$(jq '
        if length == 0 then true
        else
            all(
                (.scenario | type) == "string"
                and (.status | type) == "string"
                and (.status | . == "pass" or . == "fail" or . == "error" or . == "disputed")
                and (.summary | type) == "string"
            )
        end
    ' "$results_file" 2>/dev/null)

    if [[ "$valid" != "true" ]]; then
        print_error "validate_scenario_results: invalid scenario entries in $results_file"
        return 1
    fi

    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────
# Dispute Logging
# ─────────────────────────────────────────────────────────────────────────────────

# log_dispute — Append a dispute entry to disputes.md in structured format.
# Args: disputes_file scenario expected actual question
#   disputes_file — Path to disputes.md
#   scenario      — Name of the disputed scenario
#   expected      — What was expected (from the README)
#   actual        — What actually happened
#   question      — The ambiguity question for the user
#
# Appends in the format:
#   ## Dispute: <scenario>
#
#   **Scenario:** <scenario>
#   **Expected (from README):** <expected>
#   **Actual:** <actual>
#   **Question:** <question>
#
# Returns 0 on success, 1 on failure.
log_dispute() {
    local disputes_file="$1"
    local scenario="$2"
    local expected="$3"
    local actual="$4"
    local question="$5"

    if [[ -z "$disputes_file" || -z "$scenario" || -z "$expected" || -z "$actual" || -z "$question" ]]; then
        print_error "log_dispute: all arguments are required (disputes_file, scenario, expected, actual, question)"
        return 1
    fi

    # Ensure parent directory exists
    local parent_dir
    parent_dir="$(dirname "$disputes_file")"
    if [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir" || {
            print_error "log_dispute: failed to create directory: $parent_dir"
            return 1
        }
    fi

    # Append dispute entry
    {
        echo ""
        echo "## Dispute: ${scenario}"
        echo ""
        echo "**Scenario:** ${scenario}"
        echo "**Expected (from README):** ${expected}"
        echo "**Actual:** ${actual}"
        echo "**Question:** ${question}"
    } >> "$disputes_file"

    return 0
}
