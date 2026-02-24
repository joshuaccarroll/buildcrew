# BuildCrew

**AI-powered development with expert personas that review each other's work.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## The Problem

AI can write code fast. But fast code without review becomes technical debt.

When you let AI code without guardrails, you get:
- Over-engineered abstractions nobody asked for
- Security vulnerabilities hiding in plain sight
- Tests that pass but don't test anything meaningful
- Features that ship but don't solve the actual problem

**BuildCrew fixes this by giving AI the same quality gates your human team uses.**

---

## The Solution

BuildCrew is an autonomous development pipeline where **expert AI personas review each other's work**.

Every feature goes through:
1. A **Product Manager** who challenges scope and finds the real problem
2. A **UX Designer** who creates intuitive, accessible interfaces
3. A **Feature Engineer** who ships pragmatic, user-focused code
4. A **Principal Engineer** who reviews plans and code for quality
5. A **QA Engineer** who writes tests that actually catch bugs
6. A **Security Engineer** who blocks vulnerabilities before they ship

**No single AI agent has the final say.** Each persona has expertise, standards, and veto power.

| Without BuildCrew | With BuildCrew |
|-------------------|----------------|
| AI writes code fast, you review later | Expert personas review in real-time |
| Security issues slip through | Security blocks deployment |
| Tests for coverage, not correctness | Tests that catch real bugs |
| Over-engineered for hypothetical futures | Pragmatic code for today's needs |

---

## Quick Start

### 1. Install (once, globally)

```bash
curl -fsSL https://raw.githubusercontent.com/joshuaccarroll/buildcrew/main/install.sh | bash
```

### 2. Initialize your project

```bash
cd your-project
buildcrew init
```

### 3. Run

```bash
buildcrew run
```

That's it. BuildCrew has two modes: **Discovery mode** launches the Product Manager to help you define your project when no backlog exists. **Execution mode** processes each task through the full persona pipeline.

**Ad-hoc usage:** Invoke any persona directly with `/buildcrew <persona-name>` (e.g., `/buildcrew security-engineer` for a security audit).

---

## The Expert Personas

### Product Manager
*"Users tell you what they want. Your job is to understand what they need."*

- Challenges scope and finds the real problem
- Pushes back on over-complication
- Creates phased implementation plans
- Reviews plans from the user's perspective (plan-review phase, Pass 2)
- **Invoked via**: `/build` or `/buildcrew product-manager`

### UX Designer
*"Good design is invisible. Users shouldn't have to think."*

- Applies 7 core design principles
- Creates comprehensive design specs
- Generates HTML mockups and iterates with you until the visual design is right
- Champions accessibility from the start
- **Invoked via**: `/build` (optional) or `/buildcrew ux-designer`

### Feature Engineer
*"A feature in production is worth 10 features in planning."*

- Ships user-focused features pragmatically
- Follows existing codebase patterns
- Balances velocity with quality
- **Will avoid**: Scope creep, gold-plating, premature abstraction

### Principal Engineer
*"The best code is the code you don't have to write."*

- Reviews plans before implementation
- Reviews code for quality and patterns
- Blocks over-engineering and code smells
- **Will reject**: Functions > 20 lines, files > 300 lines, deep nesting, magic numbers

### QA Engineer
*"A test that can't fail is worthless."*

- Creates test plans with real coverage
- Writes tests that fail meaningfully
- Covers happy paths AND edge cases
- **Will catch**: Untested business logic, false positives, missing boundaries

### Security Engineer
*"Security is not a feature. It's a foundation."*

- Performs OWASP Top 10 audits
- Detects hardcoded secrets
- Validates input handling
- **Will block**: Any critical/high vulnerabilities before commit

---

## The Workflow

```
┌───────────────────────────────────────────────────────────────────┐
│                         BuildCrew Pipeline                         │
├───────────────────────────────────────────────────────────────────┤
│                                                                    │
│   SPEC ──► RESEARCH ──► PLAN ──► PLAN REVIEW ──► BUILD            │
│   (PM)                            (3-Pass:        (Feature)        │
│                                   adversarial)                     │
│                                                                    │
│   COMMIT ◄── VERIFY ◄── OUTCOME ◄── TEST ◄── CODE REVIEW          │
│              (Security   (Acceptance   (QA)   (adversarial         │
│               blocks!)    criteria)           + elegance)          │
│                                                                    │
└───────────────────────────────────────────────────────────────────┘
```

Each task runs through **up to 8 isolated Claude invocations** (phase-isolated mode), keeping context focused per phase:

| # | Phase | Description |
|---|-------|-------------|
| 1 | Spec | PM converts raw backlog item to testable acceptance criteria (skip with `--skip-spec`) |
| 2 | Research + Plan | Gather context, create implementation plan |
| 3 | Plan Review (3-pass) | Adversarial review: find the most serious flaw |
| 4 | Build | Feature Engineer implements the plan |
| 5 | Code Review | Adversarial review + elegance check; may request rebuild |
| 6 | Test | QA Engineer writes and runs tests |
| 7 | Outcome Verification | QA validates each acceptance criterion from the spec |
| 8 | Verify (incl. Security Audit) + Commit | Final gate; Security blocks commit |

**Key features:**
- **Specification first** - PM writes testable acceptance criteria before any code is planned
- **Adversarial reviews** - reviewers are asked to find flaws, not to approve quickly
- **Consolidated human review** (`--review`) - single pre-build gate with inline plan display; press Enter to proceed, `s` to skip, `q` to quit
- **Complexity-aware phase skipping** - simple tasks automatically skip unnecessary phases; use `--full-pipeline` to force all phases
- **Outcome verification** - QA validates acceptance criteria directly, not just test suite pass
- **Circuit breaker** - if any phase fails twice consecutively, re-plan from scratch with failure context
- **Lessons system** - failures are automatically recorded and injected into future runs
- **Quality gates** at every phase
- **Automatic iteration** when reviews find issues
- **Blocking security** - no commit until vulnerabilities are fixed
- **Feature branches** (`--branch`) - create a branch per task with automatic PR creation
- **Activity logging** - full activity log kept on failure; use `--keep-logs` to retain after success
- **Auto mode** (`--auto`) - fully unattended; auto-approves all interactive pauses
- **Chunked phase execution** - large builds that hit max-turns are automatically split and retried
- **Interactive permission recovery** - if a phase is blocked by missing permissions, BuildCrew prompts for recovery before continuing
- **Status line integration** - wired in via `buildcrew init` for real-time progress in Claude Code
- **Document Review Protocol** - sub-agent iterative review on all plans (up to 5 iterations or convergence)
- **Customizable** - modify phases or remove them entirely

---

## Customization

### Custom Workflow

Skip phases, add new ones, or change the flow:

```bash
# Copy the example and edit
cp .buildcrew/workflow.md.example .buildcrew/workflow.md
```

```markdown
# Minimal workflow - just build, test, commit
## Phases

### BUILD
agent: feature-engineer

### TEST
agent: qa-engineer

### COMMIT
agent: none
```

### Project Rules

Add your team's standards:

```bash
# Copy the example and edit
cp .buildcrew/rules/project-rules.md.example .buildcrew/rules/project-rules.md
```

```markdown
## Extend: Custom Rules

### Linting
- Run `npm run lint` before committing

### Naming Conventions
- Components: PascalCase, utilities: camelCase

### Operational
- Use exponential backoff for API calls
- Batch updates to prevent thundering herd
```

See `.buildcrew/rules/project-rules.md.example` for more examples.

### Project Context (Optional)

Give BuildCrew context about your users, principles, and domain:

```bash
# Copy the examples you want and edit
cp .buildcrew/context/users.md.example .buildcrew/context/users.md
cp .buildcrew/context/principles.md.example .buildcrew/context/principles.md
cp .buildcrew/context/domain.md.example .buildcrew/context/domain.md
```

These files are optional. When present, the orchestrator automatically injects their contents into every phase's prompt, so all personas benefit from your project context.

---

## CLI Commands

```bash
buildcrew                    # Show help
buildcrew init               # Link project to BuildCrew
buildcrew run                # Run workflow on BACKLOG.md
buildcrew run --single       # Process one task and stop
buildcrew run --dry-run      # Preview without executing
buildcrew run --review       # Pause for human review (single pre-build gate, shows plan inline)
buildcrew run --branch       # Create a feature branch per task with PR
buildcrew run --skip-spec    # Skip the spec phase (task already has detailed spec)
buildcrew run --strict       # (default) Require ALL acceptance criteria to pass before commit
buildcrew run --no-strict    # Allow partial acceptance criteria pass — proceed with warnings
buildcrew run --resume       # Resume an interrupted task from where it left off
buildcrew run --task N       # Target a specific task by name or number
buildcrew run --auto         # Run fully unattended — auto-approve all interactive pauses
buildcrew run --full-pipeline  # Force all phases regardless of complexity assessment
buildcrew run --keep-logs    # Retain the activity log after a successful run
buildcrew run --max-invocations N  # Set max Claude invocations per run (default: 15)
buildcrew run --verbose      # Show orchestrator decisions, phase verdicts, and invocation counts
buildcrew status             # Show backlog stats and last workflow result
buildcrew stop               # Stop after current task completes
buildcrew reset              # Clear blocked tasks and clean up artifacts
buildcrew repair             # Check installation health
buildcrew repair --fix       # Check and auto-fix installation health
buildcrew lessons            # List recorded lessons from past failures
buildcrew lessons promote N  # Graduate lesson N to permanent project rules
buildcrew lessons prune      # Interactively remove stale lessons
buildcrew plugins            # Show recommended plugins
buildcrew update             # Update BuildCrew
buildcrew version            # Show installed version
buildcrew uninstall          # Remove BuildCrew
```

### Run Options

| Flag | Description |
|------|-------------|
| `--single` | Process one task then exit |
| `--dry-run` | Preview what would happen without executing |
| `--review` | Single pre-build gate: shows the plan inline and pauses for human inspection. Press Enter to continue, `s` to skip, `q` to quit. |
| `--branch` | Create a `buildcrew/<slug>` feature branch per task. Pushes to remote and creates a PR via `gh` if available. Each task branches independently from the base branch. |
| `--resume` | Resume an interrupted task from where it left off |
| `--task N` | Target a specific task by name or number |
| `--skip-spec` | Skip the spec phase. Use when the backlog item already contains a detailed spec with acceptance criteria. |
| `--strict` | (default) Require ALL acceptance criteria to pass during Outcome Verification before the commit is allowed. |
| `--no-strict` | Allow partial acceptance criteria pass — unmet criteria trigger a warning but don't block the commit. |
| `--full-pipeline` | Force all phases regardless of complexity assessment |
| `--auto` | Run fully unattended — auto-approve all interactive pauses |
| `--keep-logs` | Retain the activity log after a successful run (the log is always kept on failure) |
| `--max-invocations N` | Set max Claude invocations per run (default: 15) |
| `--verbose` / `--debug` | Show orchestrator decisions, phase verdicts, and invocation counts |

Flags can be combined: `buildcrew run --single --review --branch`

---

## Configuration

Project-level configuration lives in `.buildcrew/config` (created from `.buildcrew/config.example` by `buildcrew init`). Each key is a shell variable that overrides the default:

| Key | Default | Description |
|-----|---------|-------------|
| `MAX_INVOCATIONS` | `15` | Maximum Claude invocations per `buildcrew run`. Equivalent to `--max-invocations N`. |
| `COMPLEXITY_AWARE` | `true` | Auto-detect task complexity and skip unnecessary phases. Set to `false` to always run all phases (equivalent to `--full-pipeline`). |
| `AUTO_MODE` | `false` | Run fully unattended — auto-approve all interactive pauses. Equivalent to `--auto`. |
| `KEEP_LOGS` | `false` | Retain the activity log after a successful run. Equivalent to `--keep-logs`. |

Example `.buildcrew/config`:

```bash
MAX_INVOCATIONS=20
COMPLEXITY_AWARE=true
AUTO_MODE=false
KEEP_LOGS=true
```

---

## The Lessons System

BuildCrew learns from its mistakes across runs. After any failed iteration (review rejection, test failure, circuit breaker trigger), it automatically records a structured lesson in `.buildcrew/lessons.md`.

Each lesson captures what went wrong, what fixed it, and a rule to prevent it next time. Lessons are **automatically injected into every phase's context** — just like `users.md` or `principles.md`.

```bash
buildcrew lessons              # List all recorded lessons
buildcrew lessons promote 3    # Graduate lesson 3 to .buildcrew/rules/project-rules.md
buildcrew lessons prune        # Interactively review and delete stale lessons
```

Lessons are capped at 100 entries. When exceeded, the oldest 50 are condensed into a summary "Patterns" section to keep context injection bounded.

---

## Circuit Breaker

If any phase fails its quality gate **twice consecutively**, BuildCrew stops grinding and re-plans from scratch:

1. Logs what was tried and why it failed
2. Appends a lesson to `.buildcrew/lessons.md`
3. Restarts from Research + Planning with the failure as context
4. Outputs: `[CIRCUIT BREAKER] Approach failed twice at <phase>. Re-planning from scratch with failure context.`

The re-plan gets **one attempt**. If it hits the circuit breaker again, the task is blocked and reported to the user.

---

## How It Works

1. **Install once** to `~/.buildcrew/` with all personas, rules, and workflows
2. **Link any project** with `buildcrew init` (creates `.buildcrew/` for your customizations)
3. **Rules merge** in order: global defaults → persona rules → your project rules

---

## Permissions & Safety

> **⚠️ Review before use:** These permissions enable autonomous operation. Review `.claude/settings.json` after `buildcrew init` and customize for your security requirements. See [Customize Permissions](#customize-permissions) below.

BuildCrew configures Claude Code with comprehensive permissions for **autonomous operation** while blocking genuinely dangerous commands.

### What's Allowed (No Prompts)

| Category | Commands |
|----------|----------|
| **File Operations** | Read, Write, Edit, Glob, Grep |
| **Package Managers** | npm, yarn, pnpm, bun, pip, poetry, cargo, go, gem, composer |
| **Build Tools** | make, cmake, gcc, docker, kubectl, terraform |
| **Git Operations** | All except force-push and hard reset |
| **Shell Utilities** | ls, cat, grep, find, sed, awk, curl, jq, tar, etc. |
| **File Management** | mkdir, cp, mv, rm, chmod, ln |
| **Project Scripts** | ./test.sh, ./build.sh, ./scripts/* |

### What's Blocked (Always)

| Category | Why |
|----------|-----|
| **Privilege escalation** | `sudo`, `su`, `doas` |
| **System destruction** | `rm -rf /`, `rm -rf ~`, system directories |
| **Git destruction** | `git push --force`, `git reset --hard`, `git clean -fd` |
| **Remote access** | `ssh`, `scp`, `rsync` |
| **System control** | `shutdown`, `reboot`, `systemctl`, `launchctl` |
| **Secrets files** | `.env`, `*.pem`, `*.key`, `.aws/*`, credentials |

### Customize Permissions

Add project-specific permissions in `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(ssh deploy@staging:*)"
    ],
    "deny": [
      "Bash(npm publish:*)"
    ]
  }
}
```

The local file merges with the global settings. Deny rules always win.

### Safety Features

- **No auto-push** - Commits stay local until you review and push (unless `--branch` is used, which pushes feature branches only)
- **Human review** (`--review`) - single pre-build gate: displays the plan inline and pauses for inspection before proceeding
- **Blocking gates** - Security issues must be fixed before commit
- **Deny-list protection** - System directories protected even when `rm` is allowed

---

## Requirements

- **Claude Code CLI** installed and authenticated
- **jq** for JSON parsing (`brew install jq`)

---

## Acknowledgments

BuildCrew was inspired by [The Ralph Loop](https://ghuntley.com/ralph/) by Geoffrey Huntley.

---

## License

MIT

---

## Links

- **Repository**: [github.com/joshuaccarroll/buildcrew](https://github.com/joshuaccarroll/buildcrew)
- **Issues**: [GitHub Issues](https://github.com/joshuaccarroll/buildcrew/issues)
- **Claude Code**: [claude.ai/code](https://claude.ai/code)
- **The Ralph Loop**: [ghuntley.com/ralph](https://ghuntley.com/ralph/)
