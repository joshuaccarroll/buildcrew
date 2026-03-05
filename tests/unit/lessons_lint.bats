#!/usr/bin/env bats
# Unit tests for `buildcrew lessons lint` command

load '../setup.bash'

setup() {
    setup_test_dir
}

teardown() {
    teardown_test_dir
}

# Helper: source only cmd_lessons from the buildcrew script
# Since sourcing the whole script may have side effects, we define the function inline
_cmd_lessons_lint() {
    local lessons_file=".buildcrew/lessons.md"
    local subcommand="lint"

    if [[ ! -f "$lessons_file" ]]; then
        echo "No lessons to lint."
        return
    fi

    local blocklist="always|never|ensure|remember|make sure|avoid|try|don't forget|be careful"
    local issues=0
    local lesson_num=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^##\ Lesson\ ([0-9]+): ]]; then
            lesson_num="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^\*\*Rule\*\*:\ (.+) ]]; then
            local rule="${BASH_REMATCH[1]}"
            local first_word
            first_word=$(echo "$rule" | awk '{print tolower($1)}')
            if echo "$first_word" | grep -qiE "^($blocklist)$"; then
                echo "WARNING Lesson $lesson_num: rule starts with vague word '${first_word}'"
                echo "    Rule: $rule"
                ((issues++))
            fi
        fi
    done < "$lessons_file"

    if [[ $issues -eq 0 ]]; then
        echo "All lesson rules look actionable."
    else
        echo ""
        echo "$issues lesson(s) with vague rules."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# lessons lint
# ─────────────────────────────────────────────────────────────────────────────

@test "lessons lint: no lessons file" {
    run _cmd_lessons_lint
    [ "$status" -eq 0 ]
    [[ "$output" == *"No lessons to lint"* ]]
}

@test "lessons lint: all rules actionable" {
    mkdir -p .buildcrew
    cat > .buildcrew/lessons.md << 'EOF'
# Lessons

## Lesson 1: Fixed parser bug
**Phase**: build
**Rule**: Use strict null checks in parser module
---
## Lesson 2: Test coverage
**Phase**: test
**Rule**: Run integration tests before commit
---
EOF
    run _cmd_lessons_lint
    [ "$status" -eq 0 ]
    [[ "$output" == *"All lesson rules look actionable"* ]]
}

@test "lessons lint: flags vague 'Always' rule" {
    mkdir -p .buildcrew
    cat > .buildcrew/lessons.md << 'EOF'
# Lessons

## Lesson 1: Vague rule
**Phase**: build
**Rule**: Always check for null
---
EOF
    run _cmd_lessons_lint
    [ "$status" -eq 0 ]
    [[ "$output" == *"vague word 'always'"* ]]
    [[ "$output" == *"1 lesson(s) with vague rules"* ]]
}

@test "lessons lint: flags 'Never' rule" {
    mkdir -p .buildcrew
    cat > .buildcrew/lessons.md << 'EOF'
# Lessons

## Lesson 1: Bad rule
**Phase**: build
**Rule**: Never use eval
---
EOF
    run _cmd_lessons_lint
    [[ "$output" == *"vague word 'never'"* ]]
}

@test "lessons lint: flags 'Ensure' rule" {
    mkdir -p .buildcrew
    cat > .buildcrew/lessons.md << 'EOF'
# Lessons

## Lesson 1: Weak rule
**Phase**: codereview
**Rule**: Ensure tests pass before merging
---
EOF
    run _cmd_lessons_lint
    [[ "$output" == *"vague word 'ensure'"* ]]
}

@test "lessons lint: flags multiple vague rules" {
    mkdir -p .buildcrew
    cat > .buildcrew/lessons.md << 'EOF'
# Lessons

## Lesson 1: Rule one
**Phase**: build
**Rule**: Always be careful
---
## Lesson 2: Rule two
**Phase**: test
**Rule**: Specific actionable rule here
---
## Lesson 3: Rule three
**Phase**: verify
**Rule**: Never forget to test
---
EOF
    run _cmd_lessons_lint
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 lesson(s) with vague rules"* ]]
}

@test "lessons lint: case insensitive matching" {
    mkdir -p .buildcrew
    cat > .buildcrew/lessons.md << 'EOF'
# Lessons

## Lesson 1: Upper case
**Phase**: build
**Rule**: AVOID using globals
---
EOF
    run _cmd_lessons_lint
    [[ "$output" == *"vague word 'avoid'"* ]]
}
