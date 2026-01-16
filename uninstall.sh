#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BuildCrew Uninstaller
# https://github.com/joshuacarroll/buildcrew
# ═══════════════════════════════════════════════════════════════════════════════
#
# This script removes BuildCrew from your system.
# Project files (.claude/, BACKLOG.md, etc.) are NOT removed.
#
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
INSTALL_DIR="$HOME/.buildcrew"
BIN_DIR="$HOME/.local/bin"

echo -e "${BOLD}BuildCrew Uninstaller${NC}"
echo ""

# Check if BuildCrew is installed
if [[ ! -d "$INSTALL_DIR" ]] && [[ ! -L "$BIN_DIR/buildcrew" ]]; then
    echo -e "${YELLOW}BuildCrew doesn't appear to be installed.${NC}"
    exit 0
fi

echo "This will remove:"
echo "  - $INSTALL_DIR/"
echo "  - $BIN_DIR/buildcrew symlink"
echo ""
echo -e "${YELLOW}Note:${NC} Project files (.claude/, BACKLOG.md, PROJECT_*.md, DESIGN_*.md)"
echo "      will NOT be removed from your projects."
echo ""

read -p "Continue with uninstall? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""

# Remove symlink
if [[ -L "$BIN_DIR/buildcrew" ]]; then
    rm -f "$BIN_DIR/buildcrew"
    echo -e "${GREEN}✓${NC} Removed $BIN_DIR/buildcrew"
fi

# Also check /usr/local/bin (Homebrew installs)
if [[ -L "/usr/local/bin/buildcrew" ]]; then
    rm -f "/usr/local/bin/buildcrew" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Removed /usr/local/bin/buildcrew"
fi

# Remove install directory
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    echo -e "${GREEN}✓${NC} Removed $INSTALL_DIR/"
fi

echo ""
echo -e "${GREEN}${BOLD}BuildCrew has been uninstalled.${NC}"
echo ""
echo "To reinstall, run:"
echo -e "  ${CYAN}curl -fsSL https://raw.githubusercontent.com/joshuacarroll/buildcrew/main/install.sh | bash${NC}"
echo ""
