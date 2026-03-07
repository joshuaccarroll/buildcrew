#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BuildCrew - Phase Precomputation
# ═══════════════════════════════════════════════════════════════════════════════
#
# Detects project metadata once at task start and writes results to
# .claude/precompute/ for downstream skill prompts to consume. This avoids
# each phase re-discovering the same information (test runner, project stack,
# codebase structure, artifact type).
#
# ═══════════════════════════════════════════════════════════════════════════════

# Source guard
[[ -n "${__BUILDCREW_PRECOMPUTE_LOADED:-}" ]] && return 0
__BUILDCREW_PRECOMPUTE_LOADED=1

__PRECOMPUTE_DIR=".claude/precompute"

# ─────────────────────────────────────────────────────────────────────────────
# detect_test_runner — write .claude/precompute/test-runner.md
# Priority-ordered: first match wins.
# ─────────────────────────────────────────────────────────────────────────────
detect_test_runner() {
    local outfile="$__PRECOMPUTE_DIR/test-runner.md"
    local framework="" command="" detected_via=""

    if [[ -x "test.sh" ]]; then
        framework="test.sh" command="./test.sh" detected_via="test.sh (executable)"
    elif [[ -f "Makefile" ]] && grep -q '^test[: 	]' Makefile 2>/dev/null; then
        framework="Make" command="make test" detected_via="Makefile test target"
    elif [[ -f "package.json" ]] && grep -q '"test"' package.json 2>/dev/null; then
        framework="npm" command="npm test" detected_via="package.json test script"
    elif [[ -f "pyproject.toml" ]]; then
        framework="Pytest" command="pytest" detected_via="pyproject.toml"
    elif [[ -f "Cargo.toml" ]]; then
        framework="Cargo" command="cargo test" detected_via="Cargo.toml"
    else
        # Search for bats files
        local bats_file
        bats_file=$(find . -name '*.bats' -maxdepth 3 -not -path './.git/*' -not -path './.claude/*' 2>/dev/null | head -1)
        if [[ -n "$bats_file" ]]; then
            local bats_dir
            bats_dir=$(dirname "$bats_file")
            framework="Bats" command="bats $bats_dir" detected_via="$bats_file"
        else
            # Search for Go test files
            local go_file
            go_file=$(find . -name '*_test.go' -maxdepth 3 -not -path './.git/*' -not -path './.claude/*' 2>/dev/null | head -1)
            if [[ -n "$go_file" ]]; then
                framework="Go" command="go test ./..." detected_via="$go_file"
            fi
        fi
    fi

    if [[ -n "$framework" ]]; then
        cat > "$outfile" <<EOF
# Test Runner

## Framework: $framework
## Command: $command
## Detected via: $detected_via
EOF
        print_debug "Precompute: test runner=$framework ($command)"
    else
        cat > "$outfile" <<EOF
# Test Runner

No test runner detected. Choose one appropriate for the project's language.
EOF
        print_debug "Precompute: no test runner detected"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# detect_project_stack — write .claude/precompute/project-stack.md
# ─────────────────────────────────────────────────────────────────────────────
detect_project_stack() {
    local outfile="$__PRECOMPUTE_DIR/project-stack.md"
    local languages="" pkg_file="" src_dirs=""

    # Detect languages and package files
    if [[ -f "package.json" ]]; then
        languages="${languages:+$languages, }JavaScript/TypeScript"
        pkg_file="${pkg_file:+$pkg_file, }package.json"
    fi
    if [[ -f "tsconfig.json" ]]; then
        languages="${languages:+$languages, }TypeScript"
    fi
    if [[ -f "pyproject.toml" ]]; then
        languages="${languages:+$languages, }Python"
        pkg_file="${pkg_file:+$pkg_file, }pyproject.toml"
    elif [[ -f "setup.py" ]]; then
        languages="${languages:+$languages, }Python"
        pkg_file="${pkg_file:+$pkg_file, }setup.py"
    fi
    if [[ -f "go.mod" ]]; then
        languages="${languages:+$languages, }Go"
        pkg_file="${pkg_file:+$pkg_file, }go.mod"
    fi
    if [[ -f "Cargo.toml" ]]; then
        languages="${languages:+$languages, }Rust"
        pkg_file="${pkg_file:+$pkg_file, }Cargo.toml"
    fi

    # Detect shell projects
    local sh_count=0
    sh_count=$(find . -maxdepth 3 -name '*.sh' -not -path './.git/*' -not -path './.claude/*' -not -path './node_modules/*' 2>/dev/null | wc -l | tr -d ' ')
    if (( sh_count > 3 )); then
        languages="${languages:+$languages, }Shell/Bash"
    fi

    # Detect source directories
    local dir
    for dir in src lib app cmd pkg internal; do
        [[ -d "$dir" ]] && src_dirs="${src_dirs:+$src_dirs, }$dir/"
    done

    # Extract key dependencies (first 10)
    local deps=""
    if [[ -f "package.json" ]]; then
        deps=$(grep -o '"[^"]*":' package.json | grep -v '"name"\|"version"\|"description"\|"main"\|"scripts"\|"devDependencies"\|"dependencies"\|"test"\|"build"\|"start"\|"dev"' | head -10 | sed 's/"//g; s/://' | tr '\n' ', ' | sed 's/, $//')
    elif [[ -f "pyproject.toml" ]]; then
        deps=$(sed -n '/\[.*dependencies\]/,/\[/p' pyproject.toml 2>/dev/null | grep -v '^\[' | grep -v '^$' | head -10 | sed 's/[[:space:]]*=.*//' | tr '\n' ', ' | sed 's/, $//')
    elif [[ -f "go.mod" ]]; then
        deps=$(grep -v '^module\|^go\|^$\|^)' go.mod 2>/dev/null | sed 's/^[[:space:]]*//' | head -10 | tr '\n' ', ' | sed 's/, $//')
    fi

    cat > "$outfile" <<EOF
# Project Stack

## Languages: ${languages:-Unknown}
## Package files: ${pkg_file:-None detected}
## Source directories: ${src_dirs:-None detected}
## Key dependencies: ${deps:-None detected}
EOF
    print_debug "Precompute: stack=${languages:-unknown}"
}

# ─────────────────────────────────────────────────────────────────────────────
# compute_codebase_structure — write .claude/precompute/codebase-structure.md
# ─────────────────────────────────────────────────────────────────────────────
compute_codebase_structure() {
    local outfile="$__PRECOMPUTE_DIR/codebase-structure.md"

    # Directory tree (depth 3, excluding common noise)
    local tree
    tree=$(find . -maxdepth 3 -type d \
        -not -path './.git*' \
        -not -path './node_modules*' \
        -not -path './__pycache__*' \
        -not -path './.claude*' \
        -not -path './.buildcrew*' \
        -not -path './target*' \
        -not -path './.venv*' \
        -not -path './venv*' \
        -not -path './dist*' \
        -not -path './build*' \
        2>/dev/null | sort)

    # File count by extension (top 10)
    local ext_stats
    ext_stats=$(find . -maxdepth 4 -type f \
        -not -path './.git/*' \
        -not -path './node_modules/*' \
        -not -path './__pycache__/*' \
        -not -path './.claude/*' \
        -not -path './.buildcrew/*' \
        2>/dev/null | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -10)

    local total_files
    total_files=$(find . -maxdepth 4 -type f \
        -not -path './.git/*' \
        -not -path './node_modules/*' \
        -not -path './__pycache__/*' \
        -not -path './.claude/*' \
        -not -path './.buildcrew/*' \
        2>/dev/null | wc -l | tr -d ' ')

    cat > "$outfile" <<EOF
# Codebase Structure

## Total files: $total_files

## Directory tree
\`\`\`
$tree
\`\`\`

## Files by extension (top 10)
\`\`\`
$ext_stats
\`\`\`
EOF
    print_debug "Precompute: codebase structure ($total_files files)"
}

# ─────────────────────────────────────────────────────────────────────────────
# precompute_uat — write .claude/precompute/artifact-type.md
# Requires artifact.sh to be sourced (detect_artifact_type, detect_run_command)
# ─────────────────────────────────────────────────────────────────────────────
precompute_uat() {
    local outfile="$__PRECOMPUTE_DIR/artifact-type.md"

    # detect_artifact_type sets __ARTIFACT_TYPE
    detect_artifact_type 2>/dev/null || true
    local art_type="${__ARTIFACT_TYPE:-unknown}"

    # detect_run_command sets __RUN_COMMAND
    detect_run_command "$art_type" 2>/dev/null || true
    local run_cmd="${__RUN_COMMAND:-}"

    # read_artifact_hints sets __INSTALL_COMMAND etc.
    read_artifact_hints 2>/dev/null || true
    local install_cmd="${__INSTALL_COMMAND:-}"

    cat > "$outfile" <<EOF
# Artifact Type

## Type: $art_type
## Run command: ${run_cmd:-Not detected}
## Install command: ${install_cmd:-Not detected}
EOF
    print_debug "Precompute: artifact type=$art_type"
}

# ─────────────────────────────────────────────────────────────────────────────
# run_precompute — orchestrate all precomputation
# ─────────────────────────────────────────────────────────────────────────────
run_precompute() {
    local start_time
    start_time=$(date +%s 2>/dev/null || echo 0)

    mkdir -p "$__PRECOMPUTE_DIR"

    detect_test_runner
    detect_project_stack
    compute_codebase_structure

    local end_time
    end_time=$(date +%s 2>/dev/null || echo 0)
    local elapsed=$(( end_time - start_time ))
    print_info "Precompute complete (${elapsed}s)"
}
