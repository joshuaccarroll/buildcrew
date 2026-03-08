# BuildCrew

**AI-powered development with expert personas that review each other's work.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

BuildCrew is an autonomous development pipeline (dark factory) that uses a true [Ralph Loop](https://ghuntley.com/ralph/), smart subagent parallelization, and expert AI personas (Product Manager, Feature Engineer, Principal Engineer, QA Engineer, Security Engineer) that review each other's work to produce high-quality, working code autonomously.

---

## Quick Start

```bash
# 1. Install (once, globally)
curl -fsSL https://raw.githubusercontent.com/joshuaccarroll/buildcrew/main/install.sh | bash

# 2. Initialize your project
cd your-project
buildcrew init

# 3. Run
buildcrew run
```

BuildCrew has two modes:

- **Discovery mode** — when no `BACKLOG.md` exists (or all tasks are complete), a Product Manager guides you through defining your project and creating a backlog. Run `buildcrew plan` to re-enter Discovery mode at any time.
- **Execution mode** — processes each `- [ ] task` in your `BACKLOG.md` through the full persona pipeline.

**Ad-hoc usage:** Invoke any persona directly with `/buildcrew <persona>:<task>` (e.g., `/buildcrew security-engineer:audit the API endpoints`).

---

## How It Works <!-- mermaid -->

1. **Install once** to `~/.buildcrew/` — persona skill files, default rules, and the workflow orchestrator
2. **Link any project** with `buildcrew init` — creates `.buildcrew/` (your customizations), symlinks skills into `.claude/`, writes `.claude/settings.json` for autonomous operation
3. **Rules merge** in order: global defaults → persona rules → your project rules (`.buildcrew/rules/project-rules.md`) → per-persona project rules (`.buildcrew/rules/<slug>-rules.md`)
4. **Communication is file-based** — orchestrator and Claude invocations share state through files in `.buildcrew/` and `.claude/`. Each phase writes a `phase-result.json` verdict that drives the next decision
5. **Phases are isolated** — each phase is a fresh `claude -p` invocation with only the context it needs, preventing context bleed between roles

_Diagram: complete `buildcrew run` execution path_

```mermaid
flowchart TD
    START([buildcrew run]) --> PENDING{Pending tasks?}
    PENDING -- No --> DISCOVERY([Discovery mode\nPM planning])
    PENDING -- Yes --> PRECOMPUTE[Precompute]

    PRECOMPUTE -- trivial --> build_t[build (Haiku)]
    PRECOMPUTE -- simple --> research_s[research (Sonnet)]
    PRECOMPUTE -- standard --> spec[spec (Sonnet)]

    subgraph Trivial path
        build_t --> verify_t[verify (Sonnet)]
        verify_t -- blocked --> build_t
        verify_t -- "blocked ×2" --> REPLAN_T{Replan\navailable?}
    end
    verify_t -- complete --> TASK_DONE{More tasks?}
    REPLAN_T -- No --> BLOCKED_T([Task blocked])
    REPLAN_T -- Yes --> research_s

    subgraph Simple path
        research_s --> build_s[build (Sonnet)]
        build_s -- max-turns --> chunked_s[chunked build]
        chunked_s -- complete --> verify_s[verify (Sonnet)]
        chunked_s -- fail --> BLOCKED_SC([Task blocked])
        build_s --> verify_s[verify (Sonnet)]
        verify_s -- blocked --> build_s
        verify_s -- "blocked ×2" --> REPLAN_SV{Replan\navailable?}
    end
    verify_s -- complete --> TASK_DONE
    REPLAN_SV -- No --> BLOCKED_SV([Task blocked])
    REPLAN_SV -- Yes --> research_s

    subgraph Standard path
        spec --> research[research (Sonnet)]
        research --> review[review (Opus)]
        review -- "needs_revision (1st - retry)" --> review
        review -- "needs_revision (2nd consecutive)" --> REPLAN_R{Replan\navailable?}
        review -- rejected --> BLOCKED_REJ([Task blocked])
        REPLAN_R -- Yes --> research
        REPLAN_R -- No --> BLOCKED_R([Task blocked])
        review -- approved --> tdd[tdd-scaffold (Haiku)]
        tdd --> build[build (Sonnet)]
        build -- max-turns --> chunked[chunked build]
        chunked -- complete --> simplify[simplify (Haiku)]
        chunked -- fail --> BLOCKED_C([Task blocked])
        build --> simplify
        simplify --> codereview[codereview (Opus)]
        codereview -- needs_rebuild --> build
        codereview -- "needs_rebuild (2nd consecutive)" --> REPLAN_CR{Replan\navailable?}
        codereview -- "needs_rebuild (during verify rebuild)" --> BLOCKED_VCR([Task blocked])
        REPLAN_CR -- Yes --> research
        REPLAN_CR -- No --> BLOCKED_CR([Task blocked])
        codereview -- approved --> verify[verify (Opus)]
        verify -- blocked --> build
        verify -- "blocked ×2" --> REPLAN_V{Replan\navailable?}
        REPLAN_V -- Yes --> research
        REPLAN_V -- No --> BLOCKED_V([Task blocked])
    end
    verify -- complete --> TASK_DONE

    TASK_DONE -- Yes --> PRECOMPUTE
    TASK_DONE -- No --> UAT[UAT]
    UAT -- pass --> DONE([Done])
    UAT -- fail --> BUILD_FIX[build fix / retry]
    BUILD_FIX --> UAT
    UAT -- "fail, retries exhausted (up to 5x)\nnon-fatal" --> DONE_NF([Done])
```

---

## The Pipeline

Each task runs through the following phases (each a separate Claude invocation). Total invocations are bounded by `MAX_INVOCATIONS` (default: 15).

| # | Phase | Persona | What happens |
|---|-------|---------|--------------|
| 1 | Spec | PM | Converts backlog item to testable acceptance criteria |
| 2 | Research + Plan | Research Agent | Explores codebase, creates implementation plan |
| 3 | Plan Review | Principal Engineer | 3-pass adversarial review with cross-reference lint |
| 4 | TDD Scaffold | QA Engineer | Writes failing tests before implementation (standard complexity) |
| 5 | Build | Feature Engineer | Implements the plan; TDD test files are locked read-only |
| 6 | Simplify | Principal Engineer | Non-blocking targeted simplifications |
| 7 | Code Review | Principal Engineer | Adversarial review + elegance check; may request rebuild |
| 8 | Verify + Commit | Security Engineer | Security audit, acceptance criteria verification, commit |
| 9 | UAT | QA Engineer | Blind scenario-based acceptance testing against README after backlog completion (opt out: `--no-uat`) |

**Key behaviors:**
- **Adversarial reviews** — reviewers are asked to find flaws, not approve quickly
- **Complexity-aware skipping** — tag tasks `{trivial}`, `{simple}`, or `{standard}` to control which phases run. Auto-detected when no tag is present. Use `--full-pipeline` to force all phases.
- **Circuit breaker** — two consecutive failures at any phase trigger a full re-plan from scratch (one re-plan attempt per task)
- **TDD by default** — for standard-complexity tasks, failing tests are written before implementation and validated to actually fail; tamper detection via SHA-256 checksums
- **Post-completion UAT** — after all backlog tasks complete, the project is tested against its own README by a blind agent that never sees source code. On failure, triggers a rebuild loop and retries. UAT failure is non-fatal. Opt out with `--no-uat`. Run manually with `buildcrew uat`.
- **Build retry feedback** — on rebuild, code review findings are injected into the build context so the agent knows what to fix
- **Lessons system** — failures are automatically recorded in `.buildcrew/lessons.md` and injected into future runs
- **Chunked execution** — large builds that hit max-turns are automatically split and retried

---

## Personas

| Persona | Role | Invoked via |
|---------|------|-------------|
| **Product Manager** | Challenges scope, writes acceptance criteria, reviews plans from user perspective | Spec phase, `/buildcrew product-manager:<task>` |
| **UX Designer** | Design specs, HTML mockups, accessibility review | Discovery mode, `/buildcrew ux-designer:<task>` |
| **Feature Engineer** | Pragmatic implementation following codebase patterns | Build phase, `/buildcrew feature-engineer:<task>` |
| **Principal Engineer** | Plan review, code review, blocks over-engineering | Review phases, `/buildcrew principal-engineer:<task>` |
| **QA Engineer** | TDD scaffolding, acceptance criteria verification | TDD Scaffold + Verify phases, `/buildcrew qa-engineer:<task>` |
| **Security Engineer** | OWASP audits, secrets detection, blocks vulnerabilities | Verify phase, `/buildcrew security-engineer:<task>` |

---

## CLI Reference

### Core Commands

```bash
buildcrew init               # Link project to BuildCrew (--quick skips interactive prompts)
buildcrew plan               # Launch Product Manager for project planning
buildcrew run                # Run workflow on BACKLOG.md
buildcrew status             # Show backlog stats and last workflow result
buildcrew stop               # Stop after current task completes
buildcrew reset              # Clear blocked tasks and clean up artifacts
```

### Run Options

| Flag | Description |
|------|-------------|
| `--single` | Process one task then exit |
| `--dry-run` | Preview what would happen without executing |
| `--review` | Pre-build gate: displays plan inline, opens `$EDITOR`. No effect for `{trivial}` tasks |
| `--branch` | Create `buildcrew/<slug>` feature branch per task with PR via `gh` |
| `--resume` | Resume an interrupted task from where it left off. Invocation counts from the interrupted run are preserved and count against the `MAX_INVOCATIONS` ceiling. Use `--max-invocations N` on resume to increase the budget if needed |
| `--task N` | Target a specific task by name or number |
| `--skip-spec` | Skip spec phase (task already has acceptance criteria) |
| `--no-tdd` | Disable TDD mode (skip tdd-scaffold phase for standard tasks) |
| `--full-pipeline` | Force all phases regardless of complexity |
| `--interactive` | Restore interactive review pauses (spec, plan) |
| `--sequential` | **(deprecated)** Use `--single` instead |
| `--batch` | **(deprecated)** Batch mode is now the default |
| `--max-parallel N` | Max concurrent tasks in parallel mode (default: 5) |
| `--no-uat` | Skip UAT after backlog completion |
| `--max-invocations N` | Max Claude invocations per run (default: 15) |
| `--model M` | Claude model: `auto` (default, per-phase), `opus`, `sonnet`, `haiku`, or full model ID. In `auto` mode, each phase uses the optimal model for its cognitive requirements (e.g., opus for review/verify, sonnet for build/research, haiku for tdd-scaffold). Complexity downgrades apply automatically. |
| `--effort L` | Effort level: `low`, `medium`, `high` (default: medium) |
| `--skip-prereqs` | Skip the prerequisites check phase |
| `--max-rebase-rounds N` | Max rebase-rebuild attempts for merge conflicts (default: 2) |
| `--no-rebase` | Skip rebase-rebuild for merge conflicts |
| `--merge-strategy S` | Merge order: `smallest-first` (default), `priority-first`, `fifo` |
| `--verbose` / `--debug` | Show orchestrator decisions, phase verdicts, invocation counts |

Flags combine freely: `buildcrew run --single --review --branch`

### Other Commands

```bash
buildcrew repair [--fix]     # Check (and optionally fix) installation health
buildcrew lessons            # List recorded lessons
buildcrew lessons promote N  # Graduate lesson N to permanent project rules
buildcrew lessons prune      # Interactively remove stale lessons
buildcrew lessons lint       # Check lessons for vague or weak rules
buildcrew plugins            # Show recommended plugins
buildcrew dash               # Launch terminal dashboard (installs if needed)
buildcrew dash status        # Show buildcrew-dash installation status and version
buildcrew update             # Update BuildCrew
buildcrew version            # Show installed version
buildcrew uninstall          # Remove BuildCrew
```

---

## Configuration

Project-level config lives in `.buildcrew/config` (created by `buildcrew init`):

| Key | Default | Description |
|-----|---------|-------------|
| `MAX_INVOCATIONS` | `15` | Max Claude invocations per run |
| `COMPLEXITY_AWARE` | `true` | Auto-detect task complexity and skip phases. `false` = all phases |
| `AUTO_MODE` | `true` | Auto-approve interactive pauses. `false` = prompt for review |
| `MAX_PARALLEL` | `5` | Max concurrent tasks in parallel mode |
| `CLAUDE_MODEL` | `auto` | Default model: `auto`, `opus`, `sonnet`, `haiku`, or full model ID |
| `CLAUDE_EFFORT` | `medium` | Default effort level: `low`, `medium`, `high` |
| `TARGET_DIR` | (none) | Target subdirectory for multi-project setups |
| `MAX_REBASE_ROUNDS` | `2` | Max rebase-rebuild attempts for merge conflicts (0-10) |
| `NO_REBASE` | `false` | Skip rebase-rebuild for merge conflicts |
| `MERGE_STRATEGY` | `smallest-first` | Merge order: `smallest-first`, `priority-first`, `fifo` |

UAT-specific config keys (`UAT_MAX_RETRIES`, `UAT_ARTIFACT_TYPE`, `UAT_RUN_COMMAND`, `UAT_ARTIFACT_TIMEOUT`, `UAT_EXECUTE_TIMEOUT`) are documented in the [UAT section](#uat-configuration) below.

---

## Customization

### Custom Workflow

```bash
cp .buildcrew/workflow.md.example .buildcrew/workflow.md
```

```markdown
# Minimal workflow — just build and commit
## Phases

### BUILD
agent: feature-engineer

### VERIFY + COMMIT
agent: none
```

### Project Rules

```bash
cp .buildcrew/rules/project-rules.md.example .buildcrew/rules/project-rules.md
```

Add your team's linting, naming, and operational standards. See the example file for details.

Use `Override:` to replace a named rule section from the defaults, or `Disable:` to remove it entirely:

```markdown
## Override: Functions
- Keep functions under 30 lines (default is 20)

## Disable: YAGNI
```

**Per-persona rules:** Each persona also checks for `.buildcrew/rules/<slug>-rules.md`. These apply after project-wide rules, letting you customize behavior for individual personas. The supported files are: `product-manager-rules.md`, `ux-designer-rules.md`, `feature-engineer-rules.md`, `principal-engineer-rules.md`, `qa-engineer-rules.md`, `security-engineer-rules.md`.

### Project Context (Optional)

```bash
cp .buildcrew/context/users.md.example .buildcrew/context/users.md
cp .buildcrew/context/principles.md.example .buildcrew/context/principles.md
cp .buildcrew/context/domain.md.example .buildcrew/context/domain.md
cp .buildcrew/context/conventions.md.example .buildcrew/context/conventions.md
```

When present, these are injected into every phase's prompt automatically.

**Context truncation:** Combined project context (all three context files) is capped at 10KB per phase invocation. When the combined content exceeds 10KB, it is truncated at the nearest section boundary (`---` or `## ` header) and a `[truncated]` marker is appended. To stay under the limit, keep context files focused — each file should cover one domain clearly rather than exhaustively.

---

## Task Annotations

```markdown
- [ ] [plan:PROJECT_webapp.md] [dir:frontend] Implement login page {standard}
```

| Annotation | Purpose |
|------------|---------|
| `[plan:FILE]` | Injects discovery plan contents into the spec phase. Added automatically by Discovery mode. |
| `[dir:DIR]` | Targets a subdirectory in multi-project setups |
| `{complexity}` | `{trivial}`, `{simple}`, or `{standard}` — controls which phases run |

---

## Lessons System

BuildCrew learns from failures. After any failed iteration, it records a structured lesson in `.buildcrew/lessons.md` — what went wrong, what fixed it, and a rule to prevent it next time. Lessons are filtered by phase — each phase only receives lessons whose `Applies to` field matches, keeping context lean. After each completed task, a nudge notification shows how many new lessons were recorded. Capped at 25 entries; when exceeded, the oldest 10 are condensed into a "Patterns" summary.

---

## Bonus Tools

Standalone skills that work inside or outside the BuildCrew pipeline. Invoke them directly in Claude Code.

- **`/simplify-all [paths]`** — Review and clean up an entire codebase (or targeted paths) for reuse, quality, and efficiency. Spawns 3 parallel analysts and auto-fixes HIGH-severity findings.

---

## UAT (User Acceptance Testing)

After all backlog tasks complete, a blind UAT agent tests your project against its README — it never sees source code. The build agent never sees the tests. On failure, the build agent fixes and republishes; retries up to 5 times. UAT failure is non-fatal (backlog tasks are already committed).

UAT runs automatically after backlog completion. Use `--no-uat` to opt out, or run standalone:

```bash
buildcrew uat                                # Run full UAT against current project
buildcrew uat --regress /path/to/artifact    # Regression test an existing artifact
buildcrew uat --preview                      # List scenarios without running agents
```

### UAT Configuration

| Key | Default | Description |
|-----|---------|-------------|
| `UAT_MAX_RETRIES` | `5` | Max build-fix-test iterations |
| `UAT_ARTIFACT_TYPE` | (auto) | Override artifact type: `cli`, `api`, `library`, `tui` |
| `UAT_RUN_COMMAND` | (auto) | Override how to run/start the artifact |
| `UAT_INSTALL_COMMAND` | (none) | Shell command run once to install/set up the artifact before UAT test execution (e.g. `npm install`) |
| `UAT_HEALTH_CHECK` | (none) | Shell command polled after artifact start to confirm readiness before scenarios run (e.g. `curl -sf http://localhost:3000/health`). Times out after `UAT_HEALTH_CHECK_TIMEOUT` seconds (default: 30) |
| `UAT_HEALTH_CHECK_TIMEOUT` | `30` | Seconds to wait for `UAT_HEALTH_CHECK` to succeed before aborting |
| `UAT_ARTIFACT_TIMEOUT` | `7200` | Seconds to wait for artifact to publish |
| `UAT_EXECUTE_TIMEOUT` | `600` | Seconds per UAT execute phase |

---

## Terminal Dashboard

```bash
buildcrew dash          # Launch (prompts to install if not present)
buildcrew dash install  # Install separately
```

Shows current phase, agent activity, workflow state, and UAT progress in real time. UAT state is written to `.buildcrew/.uat-state.json` for dashboard consumption. Requires Python 3 for activity tracking (degrades gracefully without it).

---

## Permissions & Safety

> **Review before use:** These permissions enable autonomous operation. Review `.claude/settings.json` after `buildcrew init` and customize for your requirements.

**Allowed (no prompts):** File operations, package managers (npm/yarn/pip/cargo/etc.), build tools, git (except force-push/hard reset), shell utilities, project scripts.

**Blocked (always):** `sudo`/`su`, `rm -rf /`, `git push --force`, `git reset --hard`, `ssh`/`scp`, `shutdown`/`reboot`, secrets files (`.env`, `*.pem`, `*.key`).

**Customize** via `.claude/settings.local.json` — add project-specific allow/deny rules. Deny always wins.

**Safety features:**
- Commits stay local unless `--branch` is used (which pushes and creates a PR)
- `--review` provides a pre-build inspection gate
- Security must pass before any commit is allowed

---

## Requirements

- **Claude Code CLI** installed and authenticated
- **jq** for JSON parsing (`brew install jq`)
- **Python 3** (optional — enables dashboard activity tracking)
- **gh CLI** (optional — required for `--branch` PR creation)

---

## Acknowledgments

Inspired by [The Ralph Loop](https://ghuntley.com/ralph/) by Geoffrey Huntley. 🫡

## License

MIT

## Links

- [Repository](https://github.com/joshuaccarroll/buildcrew)
- [Issues](https://github.com/joshuaccarroll/buildcrew/issues)
- [Claude Code](https://claude.ai/code)
- [The Ralph Loop](https://ghuntley.com/ralph/)
