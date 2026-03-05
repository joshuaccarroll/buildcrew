# BuildCrew

**AI-powered development with expert personas that review each other's work.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

BuildCrew is an autonomous development pipeline where expert AI personas — Product Manager, Feature Engineer, Principal Engineer, QA Engineer, Security Engineer — review each other's work. No single agent has the final say. Each has expertise, standards, and veto power.

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

## How It Works

1. **Install once** to `~/.buildcrew/` — persona skill files, default rules, and the workflow orchestrator
2. **Link any project** with `buildcrew init` — creates `.buildcrew/` (your customizations), symlinks skills into `.claude/`, writes `.claude/settings.json` for autonomous operation
3. **Rules merge** in order: global defaults → persona rules → your project rules (`.buildcrew/rules/project-rules.md`)
4. **Communication is file-based** — orchestrator and Claude invocations share state through files in `.buildcrew/` and `.claude/`. Each phase writes a `phase-result.json` verdict that drives the next decision
5. **Phases are isolated** — each phase is a fresh `claude -p` invocation with only the context it needs, preventing context bleed between roles

---

## The Pipeline

Each task runs through up to 10 phases (each a separate Claude invocation). Total invocations are bounded by `MAX_INVOCATIONS` (default: 15).

| # | Phase | Persona | What happens |
|---|-------|---------|--------------|
| 1 | Spec | PM | Converts backlog item to testable acceptance criteria |
| 2 | Research + Plan | Research Agent | Explores codebase, creates implementation plan |
| 3 | Plan Review | Principal Engineer | 3-pass adversarial review with cross-reference lint |
| 3.5 | TDD Scaffold | QA Engineer | Writes failing tests before implementation (standard complexity only) |
| 4 | Build | Feature Engineer | Implements the plan; TDD test files are locked read-only |
| 5 | Simplify | Principal Engineer | Non-blocking targeted simplifications |
| 6 | Code Review | Principal Engineer | Adversarial review + elegance check; may request rebuild |
| 7 | Test | QA Engineer | Writes and runs tests |
| 8 | Outcome | QA Engineer | Validates each acceptance criterion from the spec |
| 9 | Verify + Commit | Security Engineer | Security audit; blocks commit on vulnerabilities |

**Key behaviors:**
- **Adversarial reviews** — reviewers are asked to find flaws, not approve quickly
- **Complexity-aware skipping** — tag tasks `{trivial}`, `{simple}`, or `{standard}` to control which phases run. Auto-detected when no tag is present. Use `--full-pipeline` to force all phases.
- **Circuit breaker** — two consecutive failures at any phase trigger a full re-plan from scratch (one re-plan attempt per task)
- **TDD by default** — failing tests are written before implementation and validated to actually fail; tamper detection via SHA-256 checksums. Disable with `--no-tdd`
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
| **QA Engineer** | Tests that fail meaningfully, outcome verification | Test phase, `/buildcrew qa-engineer:<task>` |
| **Security Engineer** | OWASP audits, secrets detection, blocks vulnerabilities | Verify phase, `/buildcrew security-engineer:<task>` |

---

## CLI Reference

### Core Commands

```bash
buildcrew init               # Link project to BuildCrew
buildcrew run                # Run workflow on BACKLOG.md
buildcrew plan               # Launch Product Manager for project planning
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
| `--resume` | Resume an interrupted task from where it left off |
| `--task N` | Target a specific task by name or number |
| `--skip-spec` | Skip spec phase (task already has acceptance criteria) |
| `--strict` | (default) Require ALL acceptance criteria to pass before commit |
| `--no-strict` | Allow partial pass — warnings but no block |
| `--full-pipeline` | Force all phases regardless of complexity |
| `--interactive` | Restore interactive review pauses (spec, plan). Incompatible with `--uat` |
| `--sequential` | Run tasks one at a time (default is parallel). Auto-forced by `--single`, `--task`, `--review`, `--uat` |
| `--max-parallel N` | Max concurrent tasks in parallel mode (default: 5) |
| `--no-tdd` | Disable TDD mode. Also configurable via `TDD_MODE=false` in `.buildcrew/config` |
| `--uat` | After build, enter watch mode for UAT verdicts. Implies auto mode |
| `--max-invocations N` | Max Claude invocations per run (default: 15) |
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
| `TDD_MODE` | `true` | Write failing tests before build (standard complexity only) |
| `MAX_PARALLEL` | `5` | Max concurrent tasks in parallel mode |
| `UAT_MAX_RETRIES` | `5` | Max build-fix-test iterations in UAT watch mode |
| `UAT_ARTIFACT_TYPE` | (auto) | Override artifact type: `cli`, `api`, `library`, `tui` |
| `UAT_RUN_COMMAND` | (auto) | Override how to run/start the artifact |
| `BUILD_UAT_WATCH_TIMEOUT` | `600` | Seconds to wait for UAT verdict |

---

## Customization

### Custom Workflow

```bash
cp .buildcrew/workflow.md.example .buildcrew/workflow.md
```

```markdown
# Minimal workflow - just build, test, commit
## Phases

### BUILD
agent: feature-engineer

### TEST
agent: qa-engineer

### VERIFY + COMMIT
agent: none
```

### Project Rules

```bash
cp .buildcrew/rules/project-rules.md.example .buildcrew/rules/project-rules.md
```

Add your team's linting, naming, and operational standards. See the example file for details.

### Project Context (Optional)

```bash
cp .buildcrew/context/users.md.example .buildcrew/context/users.md
cp .buildcrew/context/principles.md.example .buildcrew/context/principles.md
cp .buildcrew/context/domain.md.example .buildcrew/context/domain.md
```

When present, these are injected into every phase's prompt automatically.

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

BuildCrew learns from failures. After any failed iteration, it records a structured lesson in `.buildcrew/lessons.md` — what went wrong, what fixed it, and a rule to prevent it next time. Lessons are injected into every phase's context automatically.

```bash
buildcrew lessons              # List all recorded lessons
buildcrew lessons promote 3    # Graduate lesson 3 to permanent project rules
buildcrew lessons prune        # Interactively review and delete stale lessons
buildcrew lessons lint         # Flag vague rules (e.g., "Always...", "Never...")
```

Capped at 25 entries. When exceeded, the oldest 10 are condensed into a "Patterns" summary. Duplicate rules are automatically skipped.

---

## Blind UAT (User Acceptance Testing)

A blind UAT system tests your project against its README — the test agent never sees source code, the build agent never sees tests.

1. The **build side** publishes a runnable artifact
2. The **UAT side** reads only the README, generates Given/When/Then scenarios, and executes them
3. Failures are sent back as structured verdicts; the build agent fixes and republishes
4. Retries up to 5 times (configurable via `UAT_MAX_RETRIES`)

```bash
# Terminal A: build and watch
buildcrew run --uat

# Terminal B: run blind UAT
mkdir ../my-project-uat && cd ../my-project-uat
buildcrew uat --readme ../my-project/README.md
```

| Flag | Description |
|------|-------------|
| `--readme <path>` | Path to the project's README.md |
| `--project <name>` | Project identifier (default: derived from README parent dir) |
| `--regress <path>` | Run UAT standalone against an existing artifact |
| `--preview` | List existing scenarios without running agents |
| `--auto` | Log disputes without pausing |

For projects that don't auto-detect correctly, set `UAT_ARTIFACT_TYPE` and `UAT_RUN_COMMAND` in `.buildcrew/config`.

---

## Terminal Dashboard

```bash
buildcrew dash          # Launch (prompts to install if not present)
buildcrew dash install  # Install separately
```

Shows current phase, agent activity, and workflow state in real time. Requires Python 3 for activity tracking (degrades gracefully without it).

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

Inspired by [The Ralph Loop](https://ghuntley.com/ralph/) by Geoffrey Huntley.

## License

MIT

## Links

- [Repository](https://github.com/joshuaccarroll/buildcrew)
- [Issues](https://github.com/joshuaccarroll/buildcrew/issues)
- [Claude Code](https://claude.ai/code)
- [The Ralph Loop](https://ghuntley.com/ralph/)
