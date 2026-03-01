#!/usr/bin/env bats
# Unit tests for build_skill_catalog in lib/common.sh

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "common.sh"
    # Use a dedicated temp dir for BUILDCREW_HOME to avoid picking up real skills
    SAVED_BUILDCREW_HOME="$BUILDCREW_HOME"
    MOCK_HOME="$(mktemp -d)"
    export BUILDCREW_HOME="$MOCK_HOME"
}

teardown() {
    export BUILDCREW_HOME="$SAVED_BUILDCREW_HOME"
    rm -rf "$MOCK_HOME"
    teardown_test_dir
    __LOG_FILE=""
}

# Helper: create a SKILL.md with valid frontmatter
create_skill_md() {
    local dir="$1"
    local name="$2"
    local description="$3"
    mkdir -p "$dir"
    cat > "$dir/SKILL.md" << EOF
---
name: $name
description: $description
allowed-tools: Read, Write
---

# Skill Content
Some content here.
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# (a) valid SKILL.md with name+description produces expected line
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: valid SKILL.md produces expected catalog line" {
    create_skill_md "$BUILDCREW_HOME/skills/test-skill" "test-skill" "A test skill for unit testing"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"Available Skills:"* ]]
    [[ "$output" == *"- test-skill: A test skill for unit testing"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# (b) SKILL.md missing name field is skipped
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: SKILL.md missing name field is skipped" {
    mkdir -p "$BUILDCREW_HOME/skills/no-name"
    cat > "$BUILDCREW_HOME/skills/no-name/SKILL.md" << 'EOF'
---
description: This skill has no name field
allowed-tools: Read
---

# Content
EOF
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" != *"no name field"* ]]
    [[ "$output" != *"Available Skills:"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# (c) SKILL.md missing description field is skipped
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: SKILL.md missing description field is skipped" {
    mkdir -p "$BUILDCREW_HOME/skills/no-desc"
    cat > "$BUILDCREW_HOME/skills/no-desc/SKILL.md" << 'EOF'
---
name: no-desc-skill
allowed-tools: Read
---

# Content
EOF
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" != *"no-desc-skill"* ]]
    [[ "$output" != *"Available Skills:"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# (d) BUILDCREW_HOME unset returns empty string
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: BUILDCREW_HOME unset returns empty string" {
    unset BUILDCREW_HOME
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [ -z "$(echo "$output" | tr -d '[:space:]')" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# (e) project-local skill overrides source skill of same directory name
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: project-local skill overrides source skill" {
    # Create source skill
    create_skill_md "$BUILDCREW_HOME/skills/my-skill" "source-version" "Source description"
    # Create local override with same directory basename
    create_skill_md ".claude/skills/my-skill" "local-version" "Local description"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"local-version: Local description"* ]]
    [[ "$output" != *"source-version"* ]]
    [[ "$output" != *"Source description"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# (f) description longer than 120 characters is truncated at word boundary
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: long description is truncated at word boundary with ellipsis" {
    # Build a description > 120 chars with words
    local long_desc="This is a very long description that goes on and on with many words to exceed the one hundred and twenty character limit for skill catalog entries"
    create_skill_md "$BUILDCREW_HOME/skills/long-skill" "long-skill" "$long_desc"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"long-skill:"* ]]
    [[ "$output" == *"..."* ]]
    # Verify the full description is NOT present
    [[ "$output" != *"$long_desc"* ]]
    # Extract the description from the catalog line
    local catalog_line
    catalog_line=$(echo "$output" | grep "^- long-skill:")
    local desc_part="${catalog_line#- long-skill: }"
    # The truncated description (minus "...") should be <= 120 chars
    local without_ellipsis="${desc_part%...}"
    [ ${#without_ellipsis} -le 120 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# (g) SKILL.md with no frontmatter (no --- delimiters) is skipped silently
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: SKILL.md with no frontmatter is skipped silently" {
    mkdir -p "$BUILDCREW_HOME/skills/no-frontmatter"
    cat > "$BUILDCREW_HOME/skills/no-frontmatter/SKILL.md" << 'EOF'
# Just a Markdown File

No YAML frontmatter here at all.
EOF
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" != *"Just a Markdown"* ]]
    [[ "$output" != *"Available Skills:"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Additional: multiple skills are sorted alphabetically by name
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: skills are sorted alphabetically by name" {
    create_skill_md "$BUILDCREW_HOME/skills/z-skill" "z-skill" "Zulu skill"
    create_skill_md "$BUILDCREW_HOME/skills/a-skill" "a-skill" "Alpha skill"
    create_skill_md "$BUILDCREW_HOME/skills/m-skill" "m-skill" "Mike skill"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    # Extract skill lines and verify order
    local a_pos m_pos z_pos
    a_pos=$(echo "$output" | grep -n "a-skill" | head -1 | cut -d: -f1)
    m_pos=$(echo "$output" | grep -n "m-skill" | head -1 | cut -d: -f1)
    z_pos=$(echo "$output" | grep -n "z-skill" | head -1 | cut -d: -f1)
    [ "$a_pos" -lt "$m_pos" ]
    [ "$m_pos" -lt "$z_pos" ]
}
