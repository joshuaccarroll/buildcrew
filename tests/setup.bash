# Shared test setup for BuildCrew
# Sourced by all .bats files

# Get the absolute path to the project root
BUILDCREW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BUILDCREW_HOME="$BUILDCREW_ROOT"

# Source library files for unit testing
source_lib() {
    local lib="$1"
    # Disable set -e temporarily for sourcing
    set +e
    source "$BUILDCREW_ROOT/lib/$lib" 2>/dev/null
    set -e
}

# Create a temporary test directory
setup_test_dir() {
    TEST_DIR="$(mktemp -d)"
    ORIGINAL_DIR="$(pwd)"
    cd "$TEST_DIR"

    # Set up minimal BuildCrew environment
    export BACKLOG_FILE="BACKLOG.md"
    export STATUS_FILE=".claude/workflow-status.json"
}

# Clean up temporary test directory
teardown_test_dir() {
    cd "$ORIGINAL_DIR"
    rm -rf "$TEST_DIR"
}

# Create a mock claude command
create_mock_claude() {
    local status="${1:-complete}"
    local summary="${2:-Test completed}"

    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" << EOF
#!/bin/bash
mkdir -p .claude
echo '{"status": "$status", "summary": "$summary"}' > .claude/workflow-status.json
EOF
    chmod +x "$TEST_DIR/bin/claude"
    export PATH="$TEST_DIR/bin:$PATH"
}

# Create a mock jq command (for systems without jq)
create_mock_jq() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/jq" << 'EOF'
#!/bin/bash
# Simple mock jq for testing
cat
EOF
    chmod +x "$TEST_DIR/bin/jq"
    export PATH="$TEST_DIR/bin:$PATH"
}

# Helper to create a test backlog
create_backlog() {
    local content="$1"
    echo "$content" > "$TEST_DIR/BACKLOG.md"
}

# Helper to create template backlog
create_template_backlog() {
    cat > "$TEST_DIR/BACKLOG.md" << 'EOF'
# Backlog

*Add your tasks here, then run `buildcrew run` to process them.*

## High Priority

- [ ] Your first task here

## Medium Priority

- [ ] Another task

## Low Priority

- [ ] Future task
EOF
}
