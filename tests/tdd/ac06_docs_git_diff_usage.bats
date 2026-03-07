#!/usr/bin/env bats
# AC-06: SKILL.md instructs use of git diff for change detection

load '../setup.bash'

setup() {
    setup_test_dir
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-06: Skill explicitly mentions git diff in instructions
# Expected: SKILL.md contains clear instructions to run git diff --name-only HEAD
# This test ensures the skill implements change detection as specified
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-06a: SKILL.md mentions 'git diff' explicitly" {
    grep -i "git diff" "$BUILDCREW_ROOT/skills/buildcrew-docs/SKILL.md"
}

@test "AC-06b: SKILL.md specifies correct git diff command format" {
    grep "git diff --name-only HEAD" "$BUILDCREW_ROOT/skills/buildcrew-docs/SKILL.md"
}

@test "AC-06c: SKILL.md mentions classifying changes as user-facing" {
    grep -i "user-facing\|user facing" "$BUILDCREW_ROOT/skills/buildcrew-docs/SKILL.md"
}

@test "AC-06d: SKILL.md mentions file pattern classification" {
    grep -i "bin/\|package.json\|config" "$BUILDCREW_ROOT/skills/buildcrew-docs/SKILL.md"
}

@test "AC-06e: SKILL.md instructs README.md update" {
    grep -i "readme\|README" "$BUILDCREW_ROOT/skills/buildcrew-docs/SKILL.md"
}

@test "AC-06f: SKILL.md specifies write to .claude/phase-result.json" {
    grep "\.claude/phase-result\.json" "$BUILDCREW_ROOT/skills/buildcrew-docs/SKILL.md"
}
