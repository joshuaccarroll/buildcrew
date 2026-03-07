#!/usr/bin/env bats
# AC-01: buildcrew-docs/SKILL.md exists with correct structure

load '../setup.bash'

setup() {
    setup_test_dir
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: Skill file structure validation
# Expected: SKILL.md exists at correct path with YAML frontmatter and phase header
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-01a: skills/buildcrew-docs/SKILL.md file exists" {
    [ -f "$BUILDCREW_ROOT/skills/buildcrew-docs/SKILL.md" ]
}

@test "AC-01b: SKILL.md has YAML frontmatter with name field" {
    grep -E "^name: buildcrew-docs" "$BUILDCREW_ROOT/skills/buildcrew-docs/SKILL.md"
}

@test "AC-01c: SKILL.md has description field in frontmatter" {
    grep -E "^description:" "$BUILDCREW_ROOT/skills/buildcrew-docs/SKILL.md"
}

@test "AC-01d: SKILL.md has allowed-tools field in frontmatter" {
    grep -E "^allowed-tools:" "$BUILDCREW_ROOT/skills/buildcrew-docs/SKILL.md"
}

@test "AC-01e: SKILL.md contains phase header with 'docs' phase name" {
    grep "Phase: docs" "$BUILDCREW_ROOT/skills/buildcrew-docs/SKILL.md"
}

@test "AC-01f: SKILL.md contains phase result section mentioning complete verdict" {
    grep -i "complete" "$BUILDCREW_ROOT/skills/buildcrew-docs/SKILL.md"
}
