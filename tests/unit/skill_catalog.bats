#!/usr/bin/env bats
# Unit tests for build_skill_catalog in lib/common.sh

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "common.sh"
    # Isolate BUILDCREW_HOME to a temp dir so real skills don't interfere
    TEST_BH_DIR="$(mktemp -d)"
    export BUILDCREW_HOME="$TEST_BH_DIR"
}

teardown() {
    rm -rf "$TEST_BH_DIR"
    teardown_test_dir
}

# Helper: create a SKILL.md with given content in a directory
create_skill_file() {
    local dir="$1"
    local content="$2"
    mkdir -p "$dir"
    printf '%s\n' "$content" > "$dir/SKILL.md"
}

# ─────────────────────────────────────────────────────────────────────────────
# (a) Valid SKILL.md with name+description produces expected line
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: valid SKILL.md produces expected output line" {
    create_skill_file "$PWD/.claude/skills/alpha" "---
name: alpha
description: Does alpha things
---
# Body"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"- alpha: Does alpha things"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# (b) SKILL.md missing name field is skipped
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: SKILL.md missing name field is skipped" {
    create_skill_file "$PWD/.claude/skills/noname" "---
description: Has no name
---
# Body"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# (c) SKILL.md missing description field is skipped
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: SKILL.md missing description field is skipped" {
    create_skill_file "$PWD/.claude/skills/nodesc" "---
name: nodesc
---
# Body"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# (d) BUILDCREW_HOME unset with no project-local skills returns empty
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: BUILDCREW_HOME unset with no project-local skills returns empty" {
    unset BUILDCREW_HOME
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# (e) Project-local skill overrides source skill of same directory name
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: project-local overrides BUILDCREW_HOME skill with same dirname" {
    create_skill_file "$BUILDCREW_HOME/skills/my-skill" "---
name: my-skill
description: Source version
---"
    create_skill_file "$PWD/.claude/skills/my-skill" "---
name: my-skill
description: Local version
---"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"- my-skill: Local version"* ]]
    [[ "$output" != *"Source version"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# (f) Description > 120 chars truncated at word boundary with "..."
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: long description truncated at word boundary with ellipsis" {
    # 110 x's + space + 20 y's = 131 chars. Space at position 111.
    # Truncation: last space at or before 120 is at 111, cut before it → 110 x's + "..."
    local xs ys long_desc
    xs=$(printf 'x%.0s' $(seq 1 110))
    ys=$(printf 'y%.0s' $(seq 1 20))
    long_desc="${xs} ${ys}"
    create_skill_file "$PWD/.claude/skills/longdesc" "---
name: longdesc
description: ${long_desc}
---"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"- longdesc: ${xs}..."* ]]
    # Ensure the y's are NOT in the output (they were truncated)
    [[ "$output" != *"y"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# (g) SKILL.md with no frontmatter (first line not ---) is skipped
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: SKILL.md without frontmatter is skipped" {
    create_skill_file "$PWD/.claude/skills/nofm" "# No Frontmatter
name: fake
description: should not appear"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# (h) Empty (0-byte) SKILL.md is skipped
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: empty SKILL.md is skipped" {
    mkdir -p "$PWD/.claude/skills/empty"
    : > "$PWD/.claude/skills/empty/SKILL.md"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# (i) Output has Available Skills: header + sorted lines, no blank lines
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: output format has header and sorted lines without blank lines" {
    create_skill_file "$PWD/.claude/skills/charlie" "---
name: charlie
description: Third skill
---"
    create_skill_file "$PWD/.claude/skills/alpha" "---
name: alpha
description: First skill
---"
    create_skill_file "$PWD/.claude/skills/bravo" "---
name: bravo
description: Second skill
---"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    # Check header is first line
    local first_line
    first_line=$(echo "$output" | head -1)
    [ "$first_line" = "Available Skills:" ]
    # Check full output matches expected sorted format
    local expected
    expected="Available Skills:
- alpha: First skill
- bravo: Second skill
- charlie: Third skill"
    [ "$output" = "$expected" ]
    # No blank lines
    local blank_count
    blank_count=$(echo "$output" | grep -c '^$' || true)
    [ "$blank_count" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# (j) Multiple skills from different sources without collision both appear
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: skills from both sources appear when no name collision" {
    create_skill_file "$BUILDCREW_HOME/skills/source-skill" "---
name: source-skill
description: From source
---"
    create_skill_file "$PWD/.claude/skills/local-skill" "---
name: local-skill
description: From local
---"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"- source-skill: From source"* ]]
    [[ "$output" == *"- local-skill: From local"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: BUILDCREW_HOME set but skills/ dir missing — silently skipped
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: BUILDCREW_HOME set but skills dir missing skips silently" {
    # BUILDCREW_HOME points to a valid dir but has no skills/ subdirectory
    rm -rf "$BUILDCREW_HOME/skills"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: Subdirectory exists but has no SKILL.md — silently skipped
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: subdirectory without SKILL.md is silently skipped" {
    mkdir -p "$PWD/.claude/skills/orphan"
    # No SKILL.md in the orphan dir
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-10: Leading/trailing whitespace trimmed from name and description
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: whitespace trimmed from name and description values" {
    create_skill_file "$PWD/.claude/skills/trimtest" "---
name:  alpha
description:  Does things
---"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"- alpha: Does things"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-11: name: value is empty/whitespace-only — skipped
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: name with whitespace-only value is skipped" {
    create_skill_file "$PWD/.claude/skills/emptyname" "---
name:
description: Has desc but no name
---"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-12: Case-sensitive matching — only lowercase name:/description: recognized
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: uppercase Name: not recognized, skill skipped" {
    create_skill_file "$PWD/.claude/skills/casebad" "---
Name: casebad
description: Should not appear
---"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-12: name: in body after closing --- is ignored
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: name in body after frontmatter is ignored" {
    create_skill_file "$PWD/.claude/skills/bodyname" "---
name: real-name
description: Real description
---
name: fake-name
This is body content"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"- real-name: Real description"* ]]
    [[ "$output" != *"fake-name"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-15: Description exactly 120 chars — not truncated
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: description of exactly 120 chars is not truncated" {
    # Build exactly 120 chars: 24 groups of "abcde" = 120 chars
    local desc120
    desc120=$(printf 'abcde%.0s' $(seq 1 24))
    [ ${#desc120} -eq 120 ]  # sanity check
    create_skill_file "$PWD/.claude/skills/exact120" "---
name: exact120
description: ${desc120}
---"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"- exact120: ${desc120}"* ]]
    # No ellipsis
    [[ "$output" != *"..."* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-16 variant: Description >120 chars with no spaces — hard-cut at 120
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: long description with no spaces is hard-cut at 120 chars" {
    # 130 contiguous chars with no spaces
    local nospace
    nospace=$(printf 'x%.0s' $(seq 1 130))
    local expected_cut
    expected_cut=$(printf 'x%.0s' $(seq 1 120))
    create_skill_file "$PWD/.claude/skills/nospace" "---
name: nospace
description: ${nospace}
---"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"- nospace: ${expected_cut}..."* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-19: LC_ALL=C sort — uppercase before lowercase
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: LC_ALL=C sort puts uppercase before lowercase" {
    create_skill_file "$PWD/.claude/skills/lower" "---
name: beta
description: Lowercase
---"
    create_skill_file "$PWD/.claude/skills/upper" "---
name: Alpha
description: Uppercase
---"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    # In LC_ALL=C, uppercase 'A' (0x41) sorts before lowercase 'b' (0x62)
    local first_skill
    first_skill=$(echo "$output" | sed -n '2p')
    [[ "$first_skill" == "- Alpha: Uppercase" ]]
    local second_skill
    second_skill=$(echo "$output" | sed -n '3p')
    [[ "$second_skill" == "- beta: Lowercase" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# ERR-09: BUILDCREW_HOME empty string — treated same as unset
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: BUILDCREW_HOME empty string returns empty output" {
    export BUILDCREW_HOME=""
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# ERR-10: Valid skill coexists with invalid sibling — valid still appears
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: valid skill appears even when sibling skill is invalid" {
    create_skill_file "$PWD/.claude/skills/good" "---
name: good-skill
description: I am valid
---"
    create_skill_file "$PWD/.claude/skills/bad" "---
description: I have no name
---"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"- good-skill: I am valid"* ]]
    [[ "$output" != *"no name"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# EDGE-12: Description containing colons
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: description with colons is captured fully" {
    create_skill_file "$PWD/.claude/skills/colons" "---
name: colons
description: foo: bar: baz
---"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"- colons: foo: bar: baz"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# EDGE-15: Only BUILDCREW_HOME skills, no project-local dir
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: only BUILDCREW_HOME skills when no project-local dir" {
    # Ensure no project-local skills dir exists
    [ ! -d "$PWD/.claude/skills" ]
    create_skill_file "$BUILDCREW_HOME/skills/source-only" "---
name: source-only
description: From source only
---"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"- source-only: From source only"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# EDGE-18: Extra frontmatter fields are ignored
# ─────────────────────────────────────────────────────────────────────────────

@test "build_skill_catalog: extra frontmatter fields are ignored" {
    create_skill_file "$PWD/.claude/skills/extra" "---
name: extra
description: Has extra fields
version: 1.0
tags: build
allowed-tools: Read, Write
---"
    run build_skill_catalog
    [ "$status" -eq 0 ]
    [[ "$output" == *"- extra: Has extra fields"* ]]
    [[ "$output" != *"version"* ]]
    [[ "$output" != *"tags"* ]]
}
