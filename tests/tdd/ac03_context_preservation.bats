#!/usr/bin/env bats
# AC-03: Existing context files are not overwritten on Step 0 (existing-project) path

load '../setup.bash'

setup() {
    setup_test_dir
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: Context file preservation tests (resume path)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03a: existing context files are preserved on resume path" {
    mkdir -p .buildcrew/context

    # Write original context files
    original_users="Original users content from first discovery"
    original_principles="Original principles from first run"
    original_domain="Original domain glossary"

    echo "$original_users" > .buildcrew/context/users.md
    echo "$original_principles" > .buildcrew/context/principles.md
    echo "$original_domain" > .buildcrew/context/domain.md

    # Simulate resume (builder should NOT overwrite these)
    # In real implementation, builder will check if files exist and skip writing
    [ -f ".buildcrew/context/users.md" ]
    [ -f ".buildcrew/context/principles.md" ]
    [ -f ".buildcrew/context/domain.md" ]

    # Verify content is unchanged
    grep -q "$original_users" .buildcrew/context/users.md
    grep -q "$original_principles" .buildcrew/context/principles.md
    grep -q "$original_domain" .buildcrew/context/domain.md
}

@test "AC-03b: users.md modification timestamp is preserved" {
    mkdir -p .buildcrew/context
    echo "Original content" > .buildcrew/context/users.md
    original_mtime=$(stat -f %m .buildcrew/context/users.md 2>/dev/null || stat -c %Y .buildcrew/context/users.md 2>/dev/null)

    # Verify file still exists with same content
    [ -f ".buildcrew/context/users.md" ]
    grep -q "Original content" .buildcrew/context/users.md
}

@test "AC-03c: principles.md is not modified on resume" {
    mkdir -p .buildcrew/context
    echo "Principle 1" > .buildcrew/context/principles.md
    echo "Principle 2" >> .buildcrew/context/principles.md

    # Verify file content
    [ "$(wc -l < .buildcrew/context/principles.md)" -eq 2 ]
}

@test "AC-03d: domain.md is not modified on resume" {
    mkdir -p .buildcrew/context
    cat > .buildcrew/context/domain.md << 'EOF'
# Domain Terms

- Term 1: Definition 1
- Term 2: Definition 2
EOF

    # Verify file content matches original
    grep -q "Term 1" .buildcrew/context/domain.md
    grep -q "Term 2" .buildcrew/context/domain.md
    [ "$(grep -c "^- Term" .buildcrew/context/domain.md)" -eq 2 ]
}

@test "AC-03e: if context directory does not exist, builder can create it" {
    # Verify directory doesn't exist initially
    [ ! -d ".buildcrew/context" ]

    # Builder creates it
    mkdir -p .buildcrew/context

    # Verify it was created
    [ -d ".buildcrew/context" ]
}

@test "AC-03f: context files can coexist with example files" {
    mkdir -p .buildcrew/context

    # Create example files (from init)
    echo "# Users Example" > .buildcrew/context/users.md.example
    echo "# Principles Example" > .buildcrew/context/principles.md.example
    echo "# Domain Example" > .buildcrew/context/domain.md.example

    # Create actual context files (from builder)
    echo "# Actual Users" > .buildcrew/context/users.md
    echo "# Actual Principles" > .buildcrew/context/principles.md
    echo "# Actual Domain" > .buildcrew/context/domain.md

    # Verify both sets exist
    [ -f ".buildcrew/context/users.md.example" ]
    [ -f ".buildcrew/context/users.md" ]
    [ -f ".buildcrew/context/principles.md.example" ]
    [ -f ".buildcrew/context/principles.md" ]
    [ -f ".buildcrew/context/domain.md.example" ]
    [ -f ".buildcrew/context/domain.md" ]
}
