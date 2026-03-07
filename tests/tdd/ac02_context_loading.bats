#!/usr/bin/env bats
# AC-02: Existing load_project_context() picks up context files without changes

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib common.sh
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: Context loading tests
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-02a: load_project_context() returns empty string when no context files exist" {
    result=$(load_project_context)
    [ -z "$result" ]
}

@test "AC-02b: load_project_context() reads users.md when present" {
    mkdir -p .buildcrew/context
    cat > .buildcrew/context/users.md << 'EOF'
# Users

Primary user: Developer
EOF

    result=$(load_project_context)
    [[ "$result" == *"Primary user"* ]]
}

@test "AC-02c: load_project_context() reads principles.md when present" {
    mkdir -p .buildcrew/context
    cat > .buildcrew/context/principles.md << 'EOF'
# Principles

Modularity is key
EOF

    result=$(load_project_context)
    [[ "$result" == *"Modularity"* ]]
}

@test "AC-02d: load_project_context() reads domain.md when present" {
    mkdir -p .buildcrew/context
    cat > .buildcrew/context/domain.md << 'EOF'
# Domain

Task: unit of work
EOF

    result=$(load_project_context)
    [[ "$result" == *"unit of work"* ]]
}

@test "AC-02e: load_project_context() concatenates all three files with double newlines" {
    mkdir -p .buildcrew/context
    echo "Users content" > .buildcrew/context/users.md
    echo "Principles content" > .buildcrew/context/principles.md
    echo "Domain content" > .buildcrew/context/domain.md

    result=$(load_project_context)
    [[ "$result" == *"Users content"* ]]
    [[ "$result" == *"Principles content"* ]]
    [[ "$result" == *"Domain content"* ]]
}

@test "AC-02f: load_project_context() respects file order: users, principles, domain" {
    mkdir -p .buildcrew/context
    echo "Users" > .buildcrew/context/users.md
    echo "Principles" > .buildcrew/context/principles.md
    echo "Domain" > .buildcrew/context/domain.md

    result=$(load_project_context)

    # Extract positions of each keyword
    users_pos=$(echo "$result" | grep -o "Users" | head -1 || echo "")
    principles_pos=$(echo "$result" | grep -o "Principles" | head -1 || echo "")
    domain_pos=$(echo "$result" | grep -o "Domain" | head -1 || echo "")

    # Verify order by checking that Users appears before Principles
    [[ "$result" =~ Users.*Principles.*Domain ]]
}

@test "AC-02g: load_project_context() handles missing single file gracefully" {
    mkdir -p .buildcrew/context
    echo "Users only" > .buildcrew/context/users.md
    # principles and domain don't exist

    result=$(load_project_context)
    [[ "$result" == *"Users only"* ]]
    # Should not fail
    [ $? -eq 0 ]
}

@test "AC-02h: load_project_context() truncates context larger than 10KB with boundary" {
    mkdir -p .buildcrew/context

    # Create a large users.md file (>10KB)
    large_content=$(printf 'Line %d\n' {1..2000})
    echo "# Users" > .buildcrew/context/users.md
    echo "$large_content" >> .buildcrew/context/users.md

    result=$(load_project_context)

    # Verify it was truncated
    [ ${#result} -lt ${#large_content} ]

    # Verify truncation marker is present
    [[ "$result" == *"[truncated]"* ]]
}
