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
# Output: one recommendation per line (name|description|type|url)
get_recommendations() {
    local project_types=($1)
    local installed_skills=($(get_installed_skills))

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

        # Output one per line
        echo "$name|$description|$type|$url"
    done
}

# Interactive plugin installation prompts
# Called during first `buildcrew run`
prompt_plugin_installs() {
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

    # Read recommendations into array (one per line)
    local recommendations=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && recommendations+=("$line")
    done < <(get_recommendations "$project_types")

    if [[ ${#recommendations[@]} -eq 0 ]] || [[ -z "${recommendations[0]}" ]]; then
        echo -e "${GREEN}✓${NC} No additional plugins recommended for this project."
        mark_plugins_checked
        return 0
    fi

    echo -e "${BOLD}Recommended Plugins:${NC}"
    echo ""

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

        echo -e "  ${GREEN}$name${NC} $type_badge"
        echo -e "  $description"
        echo ""

        # Prompt for installation
        read -p "  Install $name? [y/N] " response

        if [[ "$response" =~ ^[Yy] ]]; then
            case "$type" in
                skill)
                    echo -e "  ${CYAN}→${NC} Skills are installed via Claude Code."
                    echo -e "  ${CYAN}→${NC} Visit: $url"
                    ;;
                mcp)
                    echo -e "  ${CYAN}→${NC} Add to your Claude Code MCP settings."
                    echo -e "  ${CYAN}→${NC} Visit: $url"
                    ;;
                lsp)
                    echo -e "  ${CYAN}→${NC} Install via Claude Code plugin manager:"
                    echo -e "  ${CYAN}→${NC}   claude mcp add $name"
                    echo -e "  ${CYAN}→${NC} Or visit: $url"
                    ;;
            esac
            echo ""
        fi
        echo ""
    done

    mark_plugins_checked
    echo -e "${GREEN}✓${NC} Plugin recommendations complete."
    echo ""
}

# Display recommendations (non-interactive, for `buildcrew plugins`)
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

# Main plugin check function (for `buildcrew plugins` command)
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

    # Read recommendations into array (one per line)
    local recommendations=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && recommendations+=("$line")
    done < <(get_recommendations "$project_types")

    if show_recommendations "${recommendations[@]}"; then
        echo -e "${BOLD}Installation:${NC}"
        echo ""
        echo -e "  • ${CYAN}Skills${NC}: Install via Claude Code"
        echo -e "  • ${CYAN}MCP Servers${NC}: Configure in Claude Code settings"
        echo -e "  • ${CYAN}LSP Plugins${NC}: Install via ${CYAN}claude mcp add <name>${NC}"
        echo ""
        echo -e "Visit ${CYAN}https://code.claude.com/docs/en/discover-plugins${NC} for setup guides."
    fi
}

# Mark plugins as checked (for first-run suppression)
mark_plugins_checked() {
    mkdir -p .buildcrew
    touch .buildcrew/.plugins-checked
}

# Check if plugins have been checked before
plugins_already_checked() {
    [[ -f ".buildcrew/.plugins-checked" ]]
}
