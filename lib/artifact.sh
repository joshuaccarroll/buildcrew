#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BuildCrew - Artifact Publishing and Management
# https://github.com/joshuaccarroll/buildcrew
# ═══════════════════════════════════════════════════════════════════════════════
#
# Library for artifact publishing, type detection, manifest management, and
# verdict context generation for the UAT system.
#
# Functions set global variables prefixed with __ for return values.
# All JSON operations use jq. Atomic writes use .tmp + mv.
# Bash 3.2 compatible (no associative arrays, no declare -n, no mapfile).
#
# This file must NOT set shell options (set -e, set -u, etc.) because callers
# have different shell option requirements.
#
# ═══════════════════════════════════════════════════════════════════════════════

# Source guard — prevent double-sourcing
[[ -n "${__BUILDCREW_ARTIFACT_LOADED:-}" ]] && return 0
__BUILDCREW_ARTIFACT_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────────
# Source shared utilities
# ─────────────────────────────────────────────────────────────────────────────────

__ARTIFACT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$__ARTIFACT_DIR/common.sh"

# ─────────────────────────────────────────────────────────────────────────────────
# Global return variables (set by functions, read by callers)
# ─────────────────────────────────────────────────────────────────────────────────

__ARTIFACT_TYPE=""
__RUN_COMMAND=""
__INSTALL_COMMAND=""
__HEALTH_CHECK=""
__STOP_COMMAND=""
__MANIFEST_PROJECT=""
__MANIFEST_ARTIFACT_TYPE=""
__MANIFEST_ARTIFACT_PATH=""
__MANIFEST_RUN_COMMAND=""
__MANIFEST_INSTALL_COMMAND=""
__MANIFEST_HEALTH_CHECK=""
__MANIFEST_STOP_COMMAND=""
__MANIFEST_BUILD_TIMESTAMP=""
__MANIFEST_BUILD_ITERATION=""
__MANIFEST_README_HASH=""

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
# read_artifact_hints — read .buildcrew/artifact-hints.json
# ─────────────────────────────────────────────────────────────────────────────────
# Reads and validates artifact-hints.json. Sets globals:
#   __RUN_COMMAND, __INSTALL_COMMAND, __HEALTH_CHECK, __STOP_COMMAND
# Empty string values are treated as absent (cleared).
# Logs warning and falls through on malformed JSON or missing file.
read_artifact_hints() {
    local hints_file=".buildcrew/artifact-hints.json"

    # Reset globals
    __RUN_COMMAND=""
    __INSTALL_COMMAND=""
    __HEALTH_CHECK=""
    __STOP_COMMAND=""

    if [[ ! -f "$hints_file" ]]; then
        print_debug "No artifact-hints.json found"
        return 0
    fi

    # Validate JSON
    if ! jq -e . "$hints_file" >/dev/null 2>&1; then
        print_warning "Malformed artifact-hints.json — ignoring"
        return 0
    fi

    local val

    val=$(jq -r '.run_command // ""' "$hints_file")
    [[ -n "$val" ]] && __RUN_COMMAND="$val"

    val=$(jq -r '.install_command // ""' "$hints_file")
    [[ -n "$val" ]] && __INSTALL_COMMAND="$val"

    val=$(jq -r '.health_check // ""' "$hints_file")
    [[ -n "$val" ]] && __HEALTH_CHECK="$val"

    val=$(jq -r '.stop_command // ""' "$hints_file")
    [[ -n "$val" ]] && __STOP_COMMAND="$val"

    print_debug "Loaded artifact hints: type=hints run_command=$__RUN_COMMAND"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────
# detect_artifact_type — determine artifact type using ordered priority list
# ─────────────────────────────────────────────────────────────────────────────────
# Sets __ARTIFACT_TYPE. First match wins:
#   1. UAT_ARTIFACT_TYPE config override
#   2. Dockerfile / docker-compose.yml -> api
#   3. Textual/curses imports in Python -> tui
#   4. Cargo.toml or go.mod with main.go -> cli
#   5. Makefile or binary in bin/ -> cli
#   6. setup.py/pyproject.toml/package.json with no binary -> library
#   7. Otherwise -> other (prints warning)
detect_artifact_type() {
    __ARTIFACT_TYPE=""

    # 1. Config override
    local config_type
    config_type=$(read_config_key "UAT_ARTIFACT_TYPE")
    if [[ -n "$config_type" ]]; then
        __ARTIFACT_TYPE="$config_type"
        print_debug "Artifact type from config: $__ARTIFACT_TYPE"
        return 0
    fi

    # 2. Dockerfile or docker-compose.yml -> api
    if [[ -f "Dockerfile" ]] || [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
        __ARTIFACT_TYPE="api"
        print_debug "Artifact type detected: api (Docker)"
        return 0
    fi

    # 3. Textual/curses imports in Python -> tui
    local py_files_exist=false
    local f
    for f in *.py; do
        [[ -f "$f" ]] && { py_files_exist=true; break; }
    done
    if [[ "$py_files_exist" == "false" ]]; then
        # Check subdirectories (one level)
        for f in */*.py; do
            [[ -f "$f" ]] && { py_files_exist=true; break; }
        done
    fi
    if [[ "$py_files_exist" == "true" ]]; then
        # Search for textual or curses imports
        local tui_match
        tui_match=$(grep -rl 'import textual\|from textual\|import curses\|import urwid\|from urwid' *.py */*.py 2>/dev/null | head -1) || true
        if [[ -n "$tui_match" ]]; then
            __ARTIFACT_TYPE="tui"
            print_debug "Artifact type detected: tui (Textual/curses)"
            return 0
        fi
    fi

    # 4. Cargo.toml or go.mod with main.go -> cli
    if [[ -f "Cargo.toml" ]]; then
        __ARTIFACT_TYPE="cli"
        print_debug "Artifact type detected: cli (Cargo.toml)"
        return 0
    fi
    if [[ -f "go.mod" ]]; then
        local has_main_go=false
        for f in main.go cmd/*/main.go; do
            [[ -f "$f" ]] && { has_main_go=true; break; }
        done
        if [[ "$has_main_go" == "true" ]]; then
            __ARTIFACT_TYPE="cli"
            print_debug "Artifact type detected: cli (go.mod + main.go)"
            return 0
        fi
    fi

    # 5. Makefile or binary in bin/ -> cli
    if [[ -f "Makefile" ]]; then
        __ARTIFACT_TYPE="cli"
        print_debug "Artifact type detected: cli (Makefile)"
        return 0
    fi
    if [[ -d "bin" ]]; then
        local has_bin=false
        for f in bin/*; do
            [[ -f "$f" ]] && [[ -x "$f" ]] && { has_bin=true; break; }
        done
        if [[ "$has_bin" == "true" ]]; then
            __ARTIFACT_TYPE="cli"
            print_debug "Artifact type detected: cli (binary in bin/)"
            return 0
        fi
    fi

    # 6. setup.py/pyproject.toml/package.json with no binary -> library
    if [[ -f "setup.py" ]] || [[ -f "pyproject.toml" ]] || [[ -f "package.json" ]]; then
        __ARTIFACT_TYPE="library"
        print_debug "Artifact type detected: library"
        return 0
    fi

    # 7. Otherwise -> other
    __ARTIFACT_TYPE="other"
    print_warning "Could not detect artifact type. Set UAT_ARTIFACT_TYPE and UAT_RUN_COMMAND in .buildcrew/config."
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────
# detect_run_command — determine run command using fallback chain
# ─────────────────────────────────────────────────────────────────────────────────
# Takes artifact_type as argument. Sets __RUN_COMMAND.
# Fallback chain:
#   1. UAT_RUN_COMMAND config override
#   2. run_command from artifact-hints.json (already loaded in __RUN_COMMAND)
#   3. Auto-detect by type
detect_run_command() {
    local artifact_type="$1"

    # 1. Config override
    local config_cmd
    config_cmd=$(read_config_key "UAT_RUN_COMMAND")
    if [[ -n "$config_cmd" ]]; then
        __RUN_COMMAND="$config_cmd"
        print_debug "Run command from config: $__RUN_COMMAND"
        return 0
    fi

    # 2. Hints (already loaded via read_artifact_hints)
    if [[ -n "$__RUN_COMMAND" ]]; then
        print_debug "Run command from hints: $__RUN_COMMAND"
        return 0
    fi

    # 3. Auto-detect by type
    case "$artifact_type" in
        api)
            if [[ -f "Dockerfile" ]] || [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
                __RUN_COMMAND="docker compose up"
            else
                # Look for common entrypoints
                local f
                for f in app.py server.py main.py server.js app.js index.js main.go; do
                    if [[ -f "$f" ]]; then
                        case "$f" in
                            *.py) __RUN_COMMAND="python $f" ;;
                            *.js) __RUN_COMMAND="node $f" ;;
                            *.go) __RUN_COMMAND="go run $f" ;;
                        esac
                        break
                    fi
                done
            fi
            ;;
        cli|tui)
            # Single binary in bin/
            if [[ -d "bin" ]]; then
                local bin_count=0
                local last_bin=""
                local f
                for f in bin/*; do
                    if [[ -f "$f" ]] && [[ -x "$f" ]]; then
                        bin_count=$((bin_count + 1))
                        last_bin="$f"
                    fi
                done
                if [[ "$bin_count" -eq 1 ]]; then
                    __RUN_COMMAND="./$last_bin"
                fi
            fi
            # Makefile with run target
            if [[ -z "$__RUN_COMMAND" ]] && [[ -f "Makefile" ]]; then
                if grep -q '^run:' Makefile 2>/dev/null; then
                    __RUN_COMMAND="make run"
                fi
            fi
            ;;
        library)
            __RUN_COMMAND='echo "Library artifact -- use import in tests"'
            ;;
        other)
            # No run command for 'other' type
            __RUN_COMMAND=""
            ;;
    esac

    if [[ -n "$__RUN_COMMAND" ]]; then
        print_debug "Run command auto-detected: $__RUN_COMMAND"
    else
        print_debug "No run command detected for type: $artifact_type"
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────
# publish_artifact — publish artifact manifest after successful verify phase
# ─────────────────────────────────────────────────────────────────────────────────
# Publishes manifest.json to ~/.buildcrew/artifacts/<project>/.
# Reads hints, detects type, detects run command, computes readme hash,
# tracks build iteration, and writes manifest atomically.
#
# Arguments:
#   project_name — the project identifier
publish_artifact() {
    local project_name="$1"

    if [[ -z "$project_name" ]]; then
        print_error "publish_artifact: project_name is required"
        return 1
    fi

    local artifact_dir
    artifact_dir="$HOME/.buildcrew/artifacts/$project_name"
    mkdir -p "$artifact_dir"

    local manifest_path="$artifact_dir/manifest.json"

    # Read artifact hints (sets __RUN_COMMAND, __INSTALL_COMMAND, etc.)
    read_artifact_hints

    # Save hints values before detect functions may overwrite __RUN_COMMAND
    local hints_install="$__INSTALL_COMMAND"
    local hints_health="$__HEALTH_CHECK"
    local hints_stop="$__STOP_COMMAND"

    # Detect artifact type (sets __ARTIFACT_TYPE)
    detect_artifact_type

    # Detect run command (sets __RUN_COMMAND, respects hints fallback)
    detect_run_command "$__ARTIFACT_TYPE"

    # Compute artifact_path (original project directory)
    local artifact_path
    artifact_path="$(pwd)"

    # Compute readme_hash
    local readme_hash=""
    if [[ -f "README.md" ]]; then
        readme_hash=$(sha256_hash "README.md") || {
            print_warning "Could not compute README.md hash"
            readme_hash=""
        }
    else
        print_warning "No README.md found — readme_hash will be empty"
    fi

    # Track build_iteration (read from existing manifest or start at 1)
    local build_iteration=1
    if [[ -f "$manifest_path" ]]; then
        local prev_iteration
        prev_iteration=$(jq -r '.build_iteration // 0' "$manifest_path" 2>/dev/null) || prev_iteration=0
        if [[ "$prev_iteration" =~ ^[0-9]+$ ]]; then
            build_iteration=$((prev_iteration + 1))
        fi
    fi

    # Build timestamp
    local build_timestamp
    build_timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    # Write manifest.json atomically (write to .tmp, then mv)
    local tmp_path="$manifest_path.tmp"

    jq -n \
        --arg project "$project_name" \
        --arg artifact_type "$__ARTIFACT_TYPE" \
        --arg artifact_path "$artifact_path" \
        --arg run_command "$__RUN_COMMAND" \
        --arg install_command "$hints_install" \
        --arg health_check "$hints_health" \
        --arg stop_command "$hints_stop" \
        --arg build_timestamp "$build_timestamp" \
        --argjson build_iteration "$build_iteration" \
        --arg readme_hash "$readme_hash" \
        '{
          project: $project,
          artifact_type: $artifact_type,
          artifact_path: $artifact_path,
          run_command: $run_command,
          install_command: $install_command,
          health_check: $health_check,
          stop_command: $stop_command,
          build_timestamp: $build_timestamp,
          build_iteration: $build_iteration,
          readme_hash: $readme_hash
        }' > "$tmp_path"

    mv "$tmp_path" "$manifest_path"

    print_info "Artifact published: $manifest_path (iteration $build_iteration, type=$__ARTIFACT_TYPE)"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────
# read_manifest — read and validate manifest.json
# ─────────────────────────────────────────────────────────────────────────────────
# Sets globals for all manifest fields:
#   __MANIFEST_PROJECT, __MANIFEST_ARTIFACT_TYPE, __MANIFEST_ARTIFACT_PATH,
#   __MANIFEST_RUN_COMMAND, __MANIFEST_INSTALL_COMMAND, __MANIFEST_HEALTH_CHECK,
#   __MANIFEST_STOP_COMMAND, __MANIFEST_BUILD_TIMESTAMP, __MANIFEST_BUILD_ITERATION,
#   __MANIFEST_README_HASH
# Returns 0 on success, 1 on missing file or invalid JSON.
read_manifest() {
    local manifest_path="$1"

    # Reset all manifest globals
    __MANIFEST_PROJECT=""
    __MANIFEST_ARTIFACT_TYPE=""
    __MANIFEST_ARTIFACT_PATH=""
    __MANIFEST_RUN_COMMAND=""
    __MANIFEST_INSTALL_COMMAND=""
    __MANIFEST_HEALTH_CHECK=""
    __MANIFEST_STOP_COMMAND=""
    __MANIFEST_BUILD_TIMESTAMP=""
    __MANIFEST_BUILD_ITERATION=""
    __MANIFEST_README_HASH=""

    if [[ ! -f "$manifest_path" ]]; then
        print_debug "Manifest not found: $manifest_path"
        return 1
    fi

    # Validate JSON
    if ! jq -e . "$manifest_path" >/dev/null 2>&1; then
        print_warning "Invalid JSON in manifest: $manifest_path"
        return 1
    fi

    __MANIFEST_PROJECT=$(jq -r '.project // ""' "$manifest_path")
    __MANIFEST_ARTIFACT_TYPE=$(jq -r '.artifact_type // ""' "$manifest_path")
    __MANIFEST_ARTIFACT_PATH=$(jq -r '.artifact_path // ""' "$manifest_path")
    __MANIFEST_RUN_COMMAND=$(jq -r '.run_command // ""' "$manifest_path")
    __MANIFEST_INSTALL_COMMAND=$(jq -r '.install_command // ""' "$manifest_path")
    __MANIFEST_HEALTH_CHECK=$(jq -r '.health_check // ""' "$manifest_path")
    __MANIFEST_STOP_COMMAND=$(jq -r '.stop_command // ""' "$manifest_path")
    __MANIFEST_BUILD_TIMESTAMP=$(jq -r '.build_timestamp // ""' "$manifest_path")
    __MANIFEST_BUILD_ITERATION=$(jq -r '.build_iteration // 0' "$manifest_path")
    __MANIFEST_README_HASH=$(jq -r '.readme_hash // ""' "$manifest_path")

    # Validate required fields
    if [[ -z "$__MANIFEST_PROJECT" ]] || [[ -z "$__MANIFEST_ARTIFACT_TYPE" ]] || [[ -z "$__MANIFEST_ARTIFACT_PATH" ]]; then
        print_warning "Manifest missing required fields: $manifest_path"
        return 1
    fi

    print_debug "Manifest loaded: project=$__MANIFEST_PROJECT type=$__MANIFEST_ARTIFACT_TYPE iteration=$__MANIFEST_BUILD_ITERATION"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────
# write_uat_context — write .buildcrew/uat-context.md from a verdict
# ─────────────────────────────────────────────────────────────────────────────────
# Writes verdict context for the build agent. Separates failures from errors
# with distinct labels.
#
# Arguments:
#   verdict_json — path to the verdict.json file
#   iteration    — current iteration number
#   max_retries  — maximum retry count
write_uat_context() {
    local verdict_json="$1"
    local iteration="$2"
    local max_retries="$3"

    if [[ ! -f "$verdict_json" ]]; then
        print_error "write_uat_context: verdict file not found: $verdict_json"
        return 1
    fi

    if ! jq -e . "$verdict_json" >/dev/null 2>&1; then
        print_error "write_uat_context: invalid JSON in verdict: $verdict_json"
        return 1
    fi

    local output_file=".buildcrew/uat-context.md"
    mkdir -p .buildcrew

    # Count failures and errors from the verdict
    local fail_count error_count
    fail_count=$(jq '[.scenarios[] | select(.status == "fail")] | length' "$verdict_json")
    error_count=$(jq '[.scenarios[] | select(.status == "error")] | length' "$verdict_json")

    # Build header line
    local header="UAT Iteration ${iteration}/${max_retries}"
    local parts=""
    if [[ "$fail_count" -gt 0 ]]; then
        if [[ "$fail_count" -eq 1 ]]; then
            parts="${fail_count} scenario failed"
        else
            parts="${fail_count} scenarios failed"
        fi
    fi
    if [[ "$error_count" -gt 0 ]]; then
        if [[ -n "$parts" ]]; then
            parts="$parts, "
        fi
        if [[ "$error_count" -eq 1 ]]; then
            parts="${parts}${error_count} error"
        else
            parts="${parts}${error_count} errors"
        fi
    fi
    header="$header -- $parts:"

    local tmp_file="${output_file}.tmp"
    {
        echo "$header"
        echo ""

        # Write failures section
        if [[ "$fail_count" -gt 0 ]]; then
            echo "Failures (code bugs):"
            jq -r '.scenarios[] | select(.status == "fail") |
                "- \"" + .scenario + "\": " + .summary + "\n  Expected: " + .expected + ".\n  Actual: " + .actual + "."' \
                "$verdict_json"
            echo ""
        fi

        # Write errors section
        if [[ "$error_count" -gt 0 ]]; then
            echo "Errors (environmental -- may not be code issues):"
            jq -r '.scenarios[] | select(.status == "error") |
                "- \"" + .scenario + "\": " + .summary + "."' \
                "$verdict_json"
            echo ""
        fi

        echo "Fix the failures above. For errors, check if the build environment is correctly set up."
        echo "Do NOT access the UAT directory or scenarios."
    } > "$tmp_file"

    mv "$tmp_file" "$output_file"

    print_info "UAT context written to $output_file"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────
# cleanup_artifact — remove manifest.json if no UAT signal directory exists
# ─────────────────────────────────────────────────────────────────────────────────
# Removes ~/.buildcrew/artifacts/<project>/manifest.json only if no UAT signal
# directory exists at ~/.buildcrew/uat-signals/<project>/. This prevents
# removing a manifest that a resuming UAT process might need.
#
# Arguments:
#   project_name — the project identifier
cleanup_artifact() {
    local project_name="$1"

    if [[ -z "$project_name" ]]; then
        print_error "cleanup_artifact: project_name is required"
        return 1
    fi

    local signal_dir="$HOME/.buildcrew/uat-signals/$project_name"
    local artifact_dir="$HOME/.buildcrew/artifacts/$project_name"
    local manifest_path="$artifact_dir/manifest.json"

    # Only clean up if no signal directory exists
    if [[ -d "$signal_dir" ]]; then
        print_debug "Signal directory exists ($signal_dir) — preserving manifest"
        return 0
    fi

    if [[ -f "$manifest_path" ]]; then
        rm -f "$manifest_path"
        print_info "Cleaned up artifact manifest: $manifest_path"
    else
        print_debug "No manifest to clean up: $manifest_path"
    fi

    return 0
}
