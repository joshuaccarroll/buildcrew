#!/usr/bin/env bats
# Unit tests for batch rebase-rebuild functions in lib/workflow.sh

load '../setup.bash'

setup() {
    setup_test_dir
    source_lib "workflow.sh"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# CLI flag tests
# ─────────────────────────────────────────────────────────────────────────────

@test "parse_args: --max-rebase-rounds sets variable" {
    parse_args --max-rebase-rounds 3
    [ "$MAX_REBASE_ROUNDS" = "3" ]
}

@test "parse_args: --max-rebase-rounds validates input" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --max-rebase-rounds abc"
    [ "$status" -eq 1 ]
}

@test "parse_args: --max-rebase-rounds rejects values above 10" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --max-rebase-rounds 11"
    [ "$status" -eq 1 ]
}

@test "parse_args: --max-rebase-rounds accepts zero" {
    parse_args --max-rebase-rounds 0
    [ "$MAX_REBASE_ROUNDS" = "0" ]
}

@test "parse_args: --no-rebase sets NO_REBASE=true" {
    parse_args --no-rebase
    [ "$NO_REBASE" = "true" ]
}

@test "parse_args: --merge-strategy sets variable" {
    parse_args --merge-strategy priority-first
    [ "$MERGE_STRATEGY" = "priority-first" ]
}

@test "parse_args: --merge-strategy accepts fifo" {
    parse_args --merge-strategy fifo
    [ "$MERGE_STRATEGY" = "fifo" ]
}

@test "parse_args: --merge-strategy rejects invalid values" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --merge-strategy random"
    [ "$status" -eq 1 ]
}

@test "parse_args: --help mentions --max-rebase-rounds" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --help"
    [[ "$output" == *"--max-rebase-rounds"* ]]
}

@test "parse_args: --help mentions --no-rebase" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --help"
    [[ "$output" == *"--no-rebase"* ]]
}

@test "parse_args: --help mentions --merge-strategy" {
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>/dev/null; parse_args --help"
    [[ "$output" == *"--merge-strategy"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Config defaults tests
# ─────────────────────────────────────────────────────────────────────────────

@test "MAX_REBASE_ROUNDS: defaults to 2" {
    [ "$MAX_REBASE_ROUNDS" = "2" ]
}

@test "MAX_REBASE_ROUNDS: loaded from .buildcrew/config" {
    mkdir -p .buildcrew
    echo "MAX_REBASE_ROUNDS=4" > .buildcrew/config
    unset MAX_REBASE_ROUNDS
    load_buildcrew_config
    MAX_REBASE_ROUNDS=${MAX_REBASE_ROUNDS:-2}
    [ "$MAX_REBASE_ROUNDS" = "4" ]
}

@test "NO_REBASE: defaults to false" {
    [ "$NO_REBASE" = "false" ]
}

@test "MERGE_STRATEGY: defaults to smallest-first" {
    [ "$MERGE_STRATEGY" = "smallest-first" ]
}

@test "MERGE_STRATEGY: loaded from .buildcrew/config" {
    mkdir -p .buildcrew
    echo "MERGE_STRATEGY=fifo" > .buildcrew/config
    unset MERGE_STRATEGY
    load_buildcrew_config
    MERGE_STRATEGY=${MERGE_STRATEGY:-smallest-first}
    [ "$MERGE_STRATEGY" = "fifo" ]
}

@test "MERGE_STRATEGY: rejects invalid in config" {
    mkdir -p .buildcrew
    echo "MERGE_STRATEGY=random" > .buildcrew/config
    unset MERGE_STRATEGY
    run bash -c "source '$BUILDCREW_ROOT/lib/workflow.sh' 2>&1; echo \$MERGE_STRATEGY"
    [[ "$output" == *"Warning"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# _batch_copy_phase_artifacts tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_copy_phase_artifacts: copies spec/plan/research files" {
    mkdir -p source_wt/.claude source_wt/.buildcrew
    echo "spec content" > source_wt/.claude/spec.md
    echo "plan content" > source_wt/.claude/current-plan.md
    echo "research content" > source_wt/.claude/research.md
    echo "config content" > source_wt/.buildcrew/config

    mkdir -p dest_wt
    _batch_copy_phase_artifacts "source_wt" "dest_wt"

    [ -f "dest_wt/.claude/spec.md" ]
    [ "$(cat dest_wt/.claude/spec.md)" = "spec content" ]
    [ -f "dest_wt/.claude/current-plan.md" ]
    [ -f "dest_wt/.claude/research.md" ]
    [ -f "dest_wt/.buildcrew/config" ]
}

@test "_batch_copy_phase_artifacts: copies TDD test files from manifest" {
    mkdir -p source_wt/.claude source_wt/tests
    echo '{"test_files": ["tests/foo.test.js", "tests/bar.test.js"]}' > source_wt/.claude/tdd-manifest.json
    echo "test foo" > source_wt/tests/foo.test.js
    echo "test bar" > source_wt/tests/bar.test.js

    mkdir -p dest_wt
    _batch_copy_phase_artifacts "source_wt" "dest_wt"

    [ -f "dest_wt/.claude/tdd-manifest.json" ]
    [ -f "dest_wt/tests/foo.test.js" ]
    [ -f "dest_wt/tests/bar.test.js" ]
}

@test "_batch_copy_phase_artifacts: skips missing files gracefully" {
    mkdir -p source_wt/.claude
    echo "spec content" > source_wt/.claude/spec.md
    # No current-plan.md, no research.md, no tdd-manifest.json

    mkdir -p dest_wt
    _batch_copy_phase_artifacts "source_wt" "dest_wt"

    [ -f "dest_wt/.claude/spec.md" ]
    [ ! -f "dest_wt/.claude/current-plan.md" ]
    [ ! -f "dest_wt/.claude/research.md" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# _batch_merge_tdd_manifests tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_merge_tdd_manifests: copies when dest has none" {
    mkdir -p source_wt/.claude dest_wt/.claude
    echo '{"test_files": ["a.test.js"], "test_count": 3}' > source_wt/.claude/tdd-manifest.json

    _batch_merge_tdd_manifests "source_wt" "dest_wt"

    [ -f "dest_wt/.claude/tdd-manifest.json" ]
    [ "$(jq '.test_count' dest_wt/.claude/tdd-manifest.json)" = "3" ]
}

@test "_batch_merge_tdd_manifests: merges test_files arrays and deduplicates" {
    mkdir -p source_wt/.claude dest_wt/.claude
    echo '{"test_files": ["a.test.js", "b.test.js"], "test_count": 2}' > dest_wt/.claude/tdd-manifest.json
    echo '{"test_files": ["b.test.js", "c.test.js"], "test_count": 3}' > source_wt/.claude/tdd-manifest.json

    _batch_merge_tdd_manifests "source_wt" "dest_wt"

    local count
    count=$(jq '.test_files | length' dest_wt/.claude/tdd-manifest.json)
    [ "$count" = "3" ]  # a, b, c (deduplicated)
    [ "$(jq '.test_count' dest_wt/.claude/tdd-manifest.json)" = "5" ]  # 2 + 3
}

@test "_batch_merge_tdd_manifests: no-op when source has no manifest" {
    mkdir -p source_wt/.claude dest_wt/.claude
    echo '{"test_files": ["a.test.js"], "test_count": 1}' > dest_wt/.claude/tdd-manifest.json

    _batch_merge_tdd_manifests "source_wt" "dest_wt"

    [ "$(jq '.test_count' dest_wt/.claude/tdd-manifest.json)" = "1" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# _batch_update_task_field tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_update_task_field: updates single field in manifest" {
    _batch_init_manifest "main" "abc123"
    _batch_add_task 1 "Test task" "test-task"

    _batch_update_task_field 1 "diff_size" "42"

    [ "$(jq '.tasks[0].diff_size' "$BATCH_MANIFEST")" = "42" ]
}

@test "_batch_update_task_field: updates merge_order field" {
    _batch_init_manifest "main" "abc123"
    _batch_add_task 1 "Test task" "test-task"

    _batch_update_task_field 1 "merge_order" "1"

    [ "$(jq '.tasks[0].merge_order' "$BATCH_MANIFEST")" = "1" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# _batch_rebase_rebuild guard tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_rebase_rebuild: skips when NO_REBASE=true" {
    NO_REBASE=true
    _batch_conflict_indices=(1 2)
    run _batch_rebase_rebuild "merge-branch" "main"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped"* ]]
}

@test "_batch_rebase_rebuild: skips when no conflicts" {
    NO_REBASE=false
    _batch_conflict_indices=()
    run _batch_rebase_rebuild "merge-branch" "main"
    [ "$status" -eq 0 ]
}

@test "_batch_rebase_rebuild: skips when MAX_REBASE_ROUNDS=0" {
    NO_REBASE=false
    MAX_REBASE_ROUNDS=0
    _batch_conflict_indices=(1)
    run _batch_rebase_rebuild "merge-branch" "main"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# _batch_conflict_indices population tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_conflict_indices: initialized empty" {
    [ "${#_batch_conflict_indices[@]}" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Manifest new fields tests
# ─────────────────────────────────────────────────────────────────────────────

@test "_batch_add_task: includes new rebase fields" {
    _batch_init_manifest "main" "abc123"
    _batch_add_task 1 "Task A" "task-a"

    [ "$(jq '.tasks[0].merge_order' "$BATCH_MANIFEST")" = "null" ]
    [ "$(jq '.tasks[0].merge_attempt' "$BATCH_MANIFEST")" = "0" ]
    [ "$(jq '.tasks[0].diff_size' "$BATCH_MANIFEST")" = "null" ]
    [ "$(jq -r '.tasks[0].original_branch' "$BATCH_MANIFEST")" = "buildcrew/task-a" ]
    [ "$(jq '.tasks[0].rebase_branch' "$BATCH_MANIFEST")" = "null" ]
}

@test "_batch_mark_task: handles rebase_rebuilding status" {
    _batch_init_manifest "main" "abc123"
    _batch_add_task 1 "Task A" "task-a"
    _batch_mark_task 1 "rebase_rebuilding"
    [ "$(jq -r '.tasks[0].status' "$BATCH_MANIFEST")" = "rebase_rebuilding" ]
}

@test "_batch_mark_task: handles rebase_merged status" {
    _batch_init_manifest "main" "abc123"
    _batch_add_task 1 "Task A" "task-a"
    _batch_mark_task 1 "rebase_merged"
    [ "$(jq -r '.tasks[0].status' "$BATCH_MANIFEST")" = "rebase_merged" ]
}

@test "_batch_mark_task: handles rebase_failed status" {
    _batch_init_manifest "main" "abc123"
    _batch_add_task 1 "Task A" "task-a"
    _batch_mark_task 1 "rebase_failed"
    [ "$(jq -r '.tasks[0].status' "$BATCH_MANIFEST")" = "rebase_failed" ]
}
