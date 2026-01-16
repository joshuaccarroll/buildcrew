#!/bin/bash
# BuildCrew Plugin Recommendation System
# https://github.com/joshuaccarroll/buildcrew

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Plugin registry
# Format: name|description|detection|type|install_url
PLUGIN_REGISTRY=(
    "frontend-design|Create distinctive, production-grade frontend interfaces|frontend|skill|https://github.com/anthropics/claude-code-skills"
    "playwright-mcp|Browser automation and E2E testing with Playwright|frontend|mcp|https://github.com/anthropics/claude-code/tree/main/mcp-servers"
    "github-mcp|GitHub API integration for PRs, issues, and repositories|git|mcp|https://github.com/anthropics/claude-code/tree/main/mcp-servers"
    "filesystem-mcp|Enhanced file system operations|any|mcp|https://github.com/anthropics/claude-code/tree/main/mcp-servers"
    "typescript-lsp|TypeScript/JavaScript language intelligence|typescript|lsp|https://code.claude.com/docs/en/discover-plugins"
    "python-lsp|Python language intelligence with Pyright|python|lsp|https://code.claude.com/docs/en/discover-plugins"
    "go-lsp|Go language intelligence with gopls|go|lsp|https://code.claude.com/docs/en/discover-plugins"
    "rust-lsp|Rust language intelligence with rust-analyzer|rust|lsp|https://code.claude.com/docs/en/discover-plugins"
)

# Detect project characteristics
detect_project_type() {
    local types=()

    # Frontend framework detection
    if [[ -f "package.json" ]]; then
        if grep -qE '"(react|next|vue|nuxt|svelte|angular)"' package.json 2>/dev/null; then
            types+=("frontend")
        fi
        if grep -qE '"(express|fastify|koa|hapi|nest)"' package.json 2>/dev/null; then
            types+=("backend")
        fi
    fi

    # Language detection
    if [[ -f "tsconfig.json" ]] || ls *.ts *.tsx 2>/dev/null | head -1 >/dev/null; then
        types+=("typescript")
    fi

    if [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]] || [[ -f "setup.py" ]]; then
        types+=("python")
    fi

    if [[ -f "go.mod" ]] || ls *.go 2>/dev/null | head -1 >/dev/null; then
        types+=("go")
    fi

    if [[ -f "Cargo.toml" ]] || ls *.rs 2>/dev/null | head -1 >/dev/null; then
        types+=("rust")
    fi

    # Git detection
    if [[ -d ".git" ]]; then
        types+=("git")
    fi

    # Always include "any" for universal plugins
    types+=("any")

    echo "${types[@]}"
}

# Get installed skills
get_installed_skills() {
    local installed=()

    if [[ -d ".claude/skills" ]]; then
        for skill_dir in .claude/skills/*/; do
            if [[ -d "$skill_dir" ]]; then
                installed+=("$(basename "$skill_dir")")
            fi
        done
    fi

    echo "${installed[@]}"
}

# Check if a plugin is installed
is_plugin_installed() {
    local plugin_name="$1"
    local plugin_type="$2"
    local installed_skills=("${@:3}")

    case "$plugin_type" in
        skill)
            for skill in "${installed_skills[@]}"; do
                if [[ "$skill" == "$plugin_name" ]]; then
                    return 0
                fi
            done
            ;;
        mcp|lsp)
            # MCP and LSP plugins are configured at Claude Code level
            # We can't easily detect them, so always recommend
            return 1
            ;;
    esac

    return 1
}

# Get plugin recommendations based on project type
get_recommendations() {
    local project_types=($1)
    local installed_skills=($(get_installed_skills))
    local recommendations=()

    for entry in "${PLUGIN_REGISTRY[@]}"; do
        IFS='|' read -r name description detection type url <<< "$entry"

        # Check if plugin matches any detected project type
        local matches=false
        for ptype in "${project_types[@]}"; do
            if [[ "$detection" == "$ptype" ]]; then
                matches=true
                break
            fi
        done

        if [[ "$matches" == "false" ]]; then
            continue
        fi

        # Check if already installed (for skills)
        if is_plugin_installed "$name" "$type" "${installed_skills[@]}"; then
            continue
        fi

        recommendations+=("$name|$description|$type|$url")
    done

    echo "${recommendations[@]}"
}

# Display recommendations
show_recommendations() {
    local recommendations=("$@")

    if [[ ${#recommendations[@]} -eq 0 ]] || [[ -z "${recommendations[0]}" ]]; then
        echo -e "${GREEN}✓${NC} No additional plugins recommended for this project."
        return 1
    fi

    echo -e "${BOLD}Recommended Plugins for Your Project:${NC}"
    echo ""

    local i=1
    for rec in "${recommendations[@]}"; do
        if [[ -z "$rec" ]]; then
            continue
        fi

        IFS='|' read -r name description type url <<< "$rec"

        local type_badge=""
        case "$type" in
            skill) type_badge="${CYAN}[skill]${NC}" ;;
            mcp)   type_badge="${YELLOW}[mcp]${NC}" ;;
            lsp)   type_badge="${BLUE}[lsp]${NC}" ;;
        esac

        echo -e "  ${BOLD}$i.${NC} ${GREEN}$name${NC} $type_badge"
        echo -e "     $description"
        echo -e "     ${CYAN}→${NC} $url"
        echo ""
        ((i++))
    done

    return 0
}

# Show brief tip (for buildcrew run)
show_plugin_tip() {
    local project_types=$(detect_project_type)
    local recommendations=($(get_recommendations "$project_types"))

    if [[ ${#recommendations[@]} -gt 0 ]] && [[ -n "${recommendations[0]}" ]]; then
        local count=0
        for rec in "${recommendations[@]}"; do
            if [[ -n "$rec" ]]; then
                ((count++))
            fi
        done

        if [[ $count -gt 0 ]]; then
            echo -e "${YELLOW}Tip:${NC} $count recommended plugin(s) available. Run ${CYAN}buildcrew plugins${NC} to see them."
        fi
    fi
}

# Main plugin check function
check_plugins() {
    echo -e "${BOLD}Analyzing project...${NC}"
    echo ""

    local project_types=$(detect_project_type)

    echo -e "${CYAN}Detected:${NC}"
    for ptype in $project_types; do
        if [[ "$ptype" != "any" ]]; then
            echo "  • $ptype"
        fi
    done
    echo ""

    local recommendations=($(get_recommendations "$project_types"))

    if show_recommendations "${recommendations[@]}"; then
        echo -e "${BOLD}Installation:${NC}"
        echo ""
        echo "  • ${CYAN}Skills${NC}: Copy to .claude/skills/ in your project"
        echo "  • ${CYAN}MCP Servers${NC}: Configure in Claude Code settings"
        echo "  • ${CYAN}LSP Plugins${NC}: Install via Claude Code plugin manager"
        echo ""
        echo "Visit ${CYAN}https://code.claude.com/docs/en/discover-plugins${NC} for setup guides."
    fi
}

# Mark plugins as checked (for first-run tip suppression)
mark_plugins_checked() {
    mkdir -p .claude
    touch .claude/.plugins-checked
}

# Check if plugins have been checked before
plugins_already_checked() {
    [[ -f ".claude/.plugins-checked" ]]
}
