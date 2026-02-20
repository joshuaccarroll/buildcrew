# BuildCrew

## Architecture

- The shell orchestrator (`lib/workflow.sh`) launches `claude -p` once per phase in **phase-isolated mode**.
- Each phase is a separate skill: `skills/buildcrew-*/SKILL.md` (spec, research, review, build, test, outcome, verify).
- All orchestrator↔Claude communication is **file-based only** — no pipes, no env vars, no return values.

## Signal Flow

The file monitor (`lib/common.sh:start_file_monitor`) polls for `.claude/phase-result.json` every second. When the file appears, it **sleeps 2 seconds** then sends `pkill -INT` to terminate the Claude process. The `|| true` after every `claude -p` call suppresses the resulting non-zero exit — this is intentional, not a mistake.

## Phase Result Contract

Every phase must write `.claude/phase-result.json` with these required fields:

```json
{ "phase": "<name>", "verdict": "<verdict>", "details": "<summary>" }
```

An unknown verdict hits the catch-all and marks the task blocked:

| Phase    | Valid verdicts                               |
|----------|----------------------------------------------|
| spec     | `complete`, `vague`                          |
| research | `complete`                                   |
| review   | `approved`, `needs_revision`, `rejected`     |
| build    | `complete`                                   |
| test     | `approved`, `needs_rebuild`, `test_failure`  |
| outcome  | `passed`, `partial`, `failed`                |
| verify   | `complete`, `blocked`                        |

## Key Files

| File | Purpose |
|------|---------|
| `lib/workflow.sh` | Phase orchestrator — reads verdicts, drives retry/circuit breaker logic |
| `lib/common.sh` | Shared utilities, file monitor, print helpers |
| `skills/buildcrew-*/SKILL.md` | Per-phase skill prompts |
| `BACKLOG.md` | Task queue (`- [ ]` pending, `- [x]` done, `- [!]` blocked) |
| `.buildcrew/lessons.md` | Failure lessons — injected into every phase's context |
| `.buildcrew/config` | Optional project config (key=value) — overrides defaults for `MAX_INVOCATIONS` etc. |
| `.buildcrew/` | Runtime state directory (created by workflow, not in git) — lock files, task progress, lessons, norms |

## Hard Rules

**IMPORTANT: Never remove `|| true` after `claude -p`.** The `pkill -INT` signal always causes a non-zero exit; `|| true` is required to prevent `set -e` from aborting the orchestrator.

**YOU MUST NOT set shell options** (`set -e`, `set -u`, `set -o pipefail`) in `lib/common.sh` — callers have conflicting requirements.

- **Norms never auto-trigger from skills.** The norms skill runs once at workflow startup only.
- **No branch operations in skills.** Git branching is orchestrated by `workflow.sh`; skills only commit.
- **Run `./test.sh`** after modifying `lib/`, `bin/`, or `tests/`.
- **Bash 3.2 compatibility** (macOS default): avoid `declare -A`, `declare -n`, `mapfile`.
- **Circuit breaker threshold = 2.** Consecutive failures at any phase trigger a full re-plan from research (max 1 re-plan per task).
- **`MAX_INVOCATIONS` ceiling defaults to 15.** Configurable via `.buildcrew/config`, env var, or `--max-invocations N` flag. Phases abort once this count is reached.

## Testing

```
./test.sh                      # unit + integration suite
bats tests/unit/<file>.bats    # single test file
```

**Requires:** `bats-core`, `claude` CLI, `jq`, `gh` (for releases).

## Compaction

When context is compacted, always preserve:
- The signal flow (`pkill -INT` + `|| true` pattern) and why it exists
- The phase result contract (valid verdicts per phase)
- File-based communication constraint (no pipes, no env vars, no return values)
- The list of files modified in the current session

## Phase Sequence

0. **norms** — Analyze codebase conventions (runs once at startup, not per-task)
1. **spec** — Refine task into acceptance criteria (skipped with `--skip-spec`)
2. **research** — Explore codebase, write implementation plan
3. **review** — 3-pass adversarial plan review
4. **build** — Implement per plan
5. **test** — Code review + refactor + run tests
6. **outcome** — Verify implementation against spec acceptance criteria
7. **verify** — Security audit + commit
