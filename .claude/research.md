# Research: Task Recovery / Resume

## Research Topics
- No external APIs, libraries, or patterns to research

## Local Codebase Context

### Phase execution model
`process_task_isolated()` in `lib/workflow.sh` (line 476) runs 5 phase groups sequentially:
1. `research` — produces `.claude/research.md`, `.claude/current-plan.md`, phase-result.json
2. `review` — produces `.claude/plan-review.md`, phase-result.json (verdict: approved/needs_revision/rejected)
3. `build` — produces code changes, phase-result.json (verdict: complete)
4. `test` — produces `.claude/code-review.md`, `.claude/test-report.md`, phase-result.json (verdict: approved/needs_rebuild/test_failure)
5. `verify` — produces `.claude/security-audit.md`, `.claude/verify-report.md`, commits, phase-result.json (verdict: complete/blocked)

### Artifact cleanup
Line 484-488: All artifacts from previous task are `rm -f`'d at start of `process_task_isolated()`. This means if a task fails mid-flight, artifacts are destroyed when restarted.

### Phase group looping
- `review`: up to 3 external cycles (lines 506-535)
- `build+test`: up to 2 attempts (lines 538-567)
- `verify`: up to 3 attempts with rebuild fallback (lines 570-603)

### Invocation ceiling
`__INVOCATION_COUNT` reset to 0 per task (line 480). Max 15 invocations (configurable via `MAX_INVOCATIONS`).

### CLI entry point
`bin/buildcrew` dispatches `run` to `lib/workflow.sh` via `exec` (line 698). Args parsed by `parse_args()` (lines 82-123).

### Current flags
`--dry-run`, `--single`, `--review`, `--branch`, `--teams`

### Test framework
BATS (Bash Automated Testing System). Tests in `tests/unit/workflow.bats`, `tests/integration/run.bats`, etc. Setup in `tests/setup.bash`.

### `.buildcrew/` directory
Already exists as project workspace (`.buildcrew/.stop-workflow`, `.buildcrew/.workflow-lock`). Progress file fits naturally at `.buildcrew/task-progress.json`.

## Key Findings
- This task is internal to the codebase; no external research required.
- The main complexity is tracking which phase completed successfully and skipping to the next incomplete phase on resume.
- Artifacts must be preserved (not cleaned up) when resuming — cleanup should only happen for a fresh start.
- The `--resume` flag needs to be threaded from `bin/buildcrew` → `parse_args()` → `process_task_isolated()`.
- The invocation counter needs to also be persisted/restored on resume to preserve the safety ceiling.

<!-- Self-revision: 3/5 passes -->
