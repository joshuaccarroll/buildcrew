#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BuildCrew Installer
# https://github.com/joshuaccarroll/buildcrew
# ═══════════════════════════════════════════════════════════════════════════════
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/joshuaccarroll/buildcrew/main/install.sh | bash
#
# Or manually:
#   git clone https://github.com/joshuaccarroll/buildcrew.git
#   cd buildcrew && ./install.sh
#
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
REPO="joshuaccarroll/buildcrew"
INSTALL_DIR="$HOME/.buildcrew"
BIN_DIR="$HOME/.local/bin"

# Check if this is an upgrade
UPGRADE_MODE=false
if [[ "${1:-}" == "--upgrade" ]]; then
    UPGRADE_MODE=true
fi

print_logo() {
    echo -e "${CYAN}"
    echo "  ____        _ _     _  ____                    "
    echo " | __ ) _   _(_) | __| |/ ___|_ __ _____      __ "
    echo " |  _ \\| | | | | |/ _\` | |   | '__/ _ \\ \\ /\\ / / "
    echo " | |_) | |_| | | | (_| | |___| | |  __/\\ V  V /  "
    echo " |____/ \\__,_|_|_|\\__,_|\\____|_|  \\___| \\_/\\_/   "
    echo -e "${NC}"
}

error() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

info() {
    echo -e "${CYAN}→${NC} $1"
}

warning() {
    echo -e "${YELLOW}!${NC} $1"
}

# Detect OS and architecture
detect_platform() {
    local os arch

    case "$(uname -s)" in
        Darwin)
            os="darwin"
            ;;
        Linux)
            os="linux"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            os="windows"
            ;;
        *)
            error "Unsupported operating system: $(uname -s)"
            ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)
            arch="amd64"
            ;;
        arm64|aarch64)
            arch="arm64"
            ;;
        *)
            error "Unsupported architecture: $(uname -m)"
            ;;
    esac

    echo "${os}-${arch}"
}

# Check for required dependencies
check_dependencies() {
    local missing=()

    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        missing+=("curl or wget")
    fi

    if ! command -v tar &> /dev/null; then
        missing+=("tar")
    fi

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if ! command -v claude &> /dev/null; then
        warning "Claude Code CLI not found. You'll need to install it before using BuildCrew."
        warning "Visit: https://claude.ai/code"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}"
    fi
}

# Download file using curl or wget
download() {
    local url="$1"
    local dest="$2"

    if command -v curl &> /dev/null; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget &> /dev/null; then
        wget -qO "$dest" "$url"
    else
        error "Neither curl nor wget found"
    fi
}

# Get the latest release version
get_latest_version() {
    local version
    if command -v curl &> /dev/null; then
        version=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    else
        version=$(wget -qO- "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    fi

    if [[ -z "$version" ]]; then
        # Fallback to main branch if no release exists yet
        echo "main"
    else
        echo "$version"
    fi
}

# Install from local directory (for manual installs)
install_local() {
    local source_dir="$1"

    info "Installing from local directory..."

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Copy all files
    cp -r "$source_dir/bin" "$INSTALL_DIR/"
    cp -r "$source_dir/lib" "$INSTALL_DIR/"
    cp -r "$source_dir/skills" "$INSTALL_DIR/"
    cp -r "$source_dir/commands" "$INSTALL_DIR/"
    cp -r "$source_dir/rules" "$INSTALL_DIR/"
    cp "$source_dir/VERSION" "$INSTALL_DIR/" 2>/dev/null || echo "1.0.0" > "$INSTALL_DIR/VERSION"

    # Ensure executables are executable
    chmod +x "$INSTALL_DIR/bin/buildcrew"
    chmod +x "$INSTALL_DIR/lib/workflow.sh"
}

# Install from GitHub release
install_remote() {
    local version="$1"
    local tmp_dir

    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    info "Downloading BuildCrew v$version..."

    local archive_url
    if [[ "$version" == "main" ]]; then
        archive_url="https://github.com/$REPO/archive/refs/heads/main.tar.gz"
    else
        archive_url="https://github.com/$REPO/archive/refs/tags/v$version.tar.gz"
    fi

    download "$archive_url" "$tmp_dir/buildcrew.tar.gz"

    info "Extracting..."
    tar -xzf "$tmp_dir/buildcrew.tar.gz" -C "$tmp_dir"

    # Find extracted directory
    local extracted_dir
    extracted_dir=$(find "$tmp_dir" -maxdepth 1 -type d -name "buildcrew*" | head -1)

    if [[ -z "$extracted_dir" ]]; then
        error "Failed to extract archive"
    fi

    install_local "$extracted_dir"
}

# Create symlink to bin directory
setup_path() {
    info "Setting up PATH..."

    # Create bin directory if it doesn't exist
    mkdir -p "$BIN_DIR"

    # Create symlink
    ln -sf "$INSTALL_DIR/bin/buildcrew" "$BIN_DIR/buildcrew"

    # Check if BIN_DIR is in PATH
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        warning "$BIN_DIR is not in your PATH"
        echo ""
        echo "Add this to your shell config (~/.bashrc, ~/.zshrc, etc.):"
        echo -e "  ${CYAN}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
        echo ""
    fi
}

# Main installation
main() {
    if [[ "$UPGRADE_MODE" != "true" ]]; then
        print_logo
        echo -e "${BOLD}BuildCrew Installer${NC}"
        echo ""
    fi

    # Check dependencies
    info "Checking dependencies..."
    check_dependencies
    success "Dependencies OK"

    # Detect platform
    local platform
    platform=$(detect_platform)
    info "Detected platform: $platform"

    # Determine installation source
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -f "$script_dir/bin/buildcrew" ]]; then
        # Installing from local clone
        info "Installing from local directory..."
        install_local "$script_dir"
    else
        # Installing from remote
        local version
        version=$(get_latest_version)
        info "Latest version: $version"
        install_remote "$version"
    fi

    success "Files installed to $INSTALL_DIR"

    # Setup PATH
    setup_path
    success "Symlink created at $BIN_DIR/buildcrew"

    # Verify installation
    if command -v buildcrew &> /dev/null || [[ -x "$BIN_DIR/buildcrew" ]]; then
        success "Installation complete!"
    else
        warning "Installation complete, but buildcrew not found in PATH"
        echo "You may need to restart your shell or add $BIN_DIR to your PATH"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}BuildCrew installed successfully!${NC}"
    echo ""
    echo -e "${BOLD}Getting started:${NC}"
    echo -e "  1. ${CYAN}cd your-project${NC}"
    echo -e "  2. ${CYAN}buildcrew init${NC}"
    echo -e "  3. ${CYAN}buildcrew run${NC}"
    echo -e "  (Auto-launches build mode if no backlog exists)"
    echo ""
    echo -e "${BOLD}Documentation:${NC} https://github.com/joshuaccarroll/buildcrew"
    echo ""
}

main "$@"
