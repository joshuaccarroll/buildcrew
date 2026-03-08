#!/bin/bash
# BuildCrew Test Runner
# Requires: bats-core (brew install bats-core)

set -e

# Prevent infinite recursion when TDD tests call ./test.sh
if [[ "${BUILDCREW_TEST_RUNNING:-}" == "1" ]]; then
    echo "test.sh: already running (recursion guard), skipping"
    exit 0
fi
export BUILDCREW_TEST_RUNNING=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure tests run from the buildcrew root (some tests use relative paths)
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check for bats
if ! command -v bats &> /dev/null; then
    echo -e "${RED}Error:${NC} bats-core not found."
    echo ""
    echo "Install with:"
    echo "  brew install bats-core"
    echo ""
    echo "Or:"
    echo "  git clone https://github.com/bats-core/bats-core.git"
    echo "  cd bats-core && sudo ./install.sh /usr/local"
    exit 1
fi

echo -e "${CYAN}Running BuildCrew Tests${NC}"
echo ""

# Parse arguments
RUN_E2E=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --e2e)
            RUN_E2E=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Build bats args
BATS_ARGS=""
if [ "$VERBOSE" = true ]; then
    BATS_ARGS="--verbose-run"
fi

# Run TDD tests (if they exist)
if [ -d "$SCRIPT_DIR/tests/tdd/" ] && ls "$SCRIPT_DIR/tests/tdd/"*.bats > /dev/null 2>&1; then
    echo -e "${GREEN}TDD Tests${NC}"
    bats $BATS_ARGS "$SCRIPT_DIR/tests/tdd/"*.bats
    echo ""
fi

# Run unit tests
echo -e "${GREEN}Unit Tests${NC}"
bats $BATS_ARGS "$SCRIPT_DIR/tests/unit/"*.bats

# Run integration tests
echo ""
echo -e "${GREEN}Integration Tests${NC}"
bats $BATS_ARGS "$SCRIPT_DIR/tests/integration/"*.bats

# Run E2E tests (optional)
if [ "$RUN_E2E" = true ]; then
    echo ""
    echo -e "${GREEN}E2E Tests${NC}"
    BUILDCREW_E2E=1 bats $BATS_ARGS "$SCRIPT_DIR/tests/e2e/"*.bats
fi

echo ""
echo -e "${GREEN}All tests passed!${NC}"
