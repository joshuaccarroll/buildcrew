# BuildCrew Improvement Plan (v4)

## Bug Fixes

### 1. Global invocation ceiling
**Category**: Safety
**Priority**: High
**Files**: `lib/workflow.sh`

Add a global counter across all phase invocations in `process_task_isolated()`. Cap at ~15 total invocations per task. Currently the worst case is 17+ invocations (build loop max 4 + verify loop max 9 + research 1 + review 3) with no global brake. The ceiling prevents runaway API cost from compounding retry loops.

- [x] Done

### 2. Fix plan review skill — 1 internal cycle only
**Category**: Bug fix
**Priority**: High
**Files**: `skills/buildcrew-review/SKILL.md`

The skill instructs Claude to do up to 3 internal revision cycles (line 146), but the orchestrator ALSO loops up to 3 times externally (workflow.sh:488-516), creating a potential 9-cycle compound. Fix: update the skill to perform exactly 1 review+revise cycle and report its verdict. Let the orchestrator handle retries.

- [x] Done

### 3. Fix dry-run side effect
**Category**: Bug fix
**Priority**: High
**Files**: `lib/workflow.sh` (line 783)

`mark_task_complete "$task"` is called during `--dry-run`, which mutates BACKLOG.md. Dry run should not modify state. Replace with a no-op or print statement.

- [x] Done

### 4. Task recovery / resume
**Category**: Feature
**Priority**: Medium
**Files**: `lib/workflow.sh`, `bin/buildcrew`

Track completed phases in `.buildcrew/task-progress.json`. Add `--resume` flag to pick up where a failed/interrupted task left off instead of restarting from scratch. Saves API cost when a task fails at phase 4+ and phases 1-3 were fine.

- [x] Done

### 5. Treat `test_failure` like `needs_rebuild` in build loop
**Category**: Improvement
**Priority**: Medium
**Files**: `lib/workflow.sh` (lines 542-544)

Currently `test_failure` immediately blocks the task in the build loop, while `needs_rebuild` gets a retry. The verify loop already rebuilds on test failures (lines 569-571), so the tool acknowledges rebuilds can fix test issues — just not in the build loop. Give `test_failure` one more build attempt before blocking.

- [x] Done

### 6. Remove README update from research/plan phase
**Category**: Token savings
**Priority**: Medium
**Files**: `skills/buildcrew-research/SKILL.md` (lines 185-189)

The research skill updates README speculatively (before code exists), then the build skill overwrites it with the actual implementation. The speculative update wastes tokens — especially the Rule of Five self-revision on a document that gets replaced. Remove README instructions from the research skill; keep them only in the build skill.

- [x] Done

### 7. Archive artifacts for blocked tasks
**Category**: Feature
**Priority**: Low
**Files**: `lib/workflow.sh` (lines 466-469)

Artifacts are deleted at the start of each task. If a task was blocked, the debugging artifacts (research.md, plan-review.md, test-report.md, etc.) are gone when the next task starts. Save them to `.buildcrew/history/<task-slug>/<timestamp>/` before cleanup.

- [x] Done

### 8. Richer context on verify-failure rebuilds
**Category**: Quality
**Priority**: Low
**Files**: `lib/workflow.sh` (line 570), `skills/buildcrew-build/SKILL.md`

When verify fails and triggers a rebuild, the context passed is thin: `"Verify failed: $failing. Fix and rebuild."` The build skill doesn't know to read `.claude/security-audit.md` or `.claude/test-report.md`. Fix: (a) pass structured failure details in the orchestrator's extra_context, and (b) add conditional instructions to the build skill to read failure artifacts when rebuilding.

- [ ] Pending

### 9. Add `--task` targeting
**Category**: QoL
**Priority**: Low
**Files**: `lib/workflow.sh`, `bin/buildcrew`

Add `buildcrew run --task "task name"` or `--task 3` to process a specific task from the backlog instead of always processing in order.

- [ ] Pending

### 10. Add `buildcrew reset` command
**Category**: QoL
**Priority**: Low
**Files**: `bin/buildcrew`

Clear blocked tasks back to pending (`[!]` → `[ ]`), clean `.claude/` artifacts, and remove stale lockfile. Currently requires manual BACKLOG.md editing.

- [ ] Pending
