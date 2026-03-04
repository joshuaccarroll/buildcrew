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

**Discovery mode** (new projects) guides you through:
1. A **Product Manager** who challenges scope and finds the real problem
2. A **UX Designer** who creates intuitive, accessible interfaces *(Discovery only)*

**Execution mode** (backlog tasks) runs every task through:
1. A **Product Manager** who refines acceptance criteria before anything is planned
2. A **Feature Engineer** who ships pragmatic, user-focused code
3. A **Principal Engineer** who reviews plans and code for quality
4. A **QA Engineer** who writes tests that actually catch bugs
5. A **Security Engineer** who blocks vulnerabilities before they ship

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

That's it. BuildCrew has two modes:

- **Discovery mode** — if no `BACKLOG.md` exists (or all tasks are complete), the Product Manager launches and guides you through defining your project and creating a backlog. Discovery uses an interview technique that probes edge cases, technical tradeoffs, failure modes, and security considerations — not just the basics. Each generated task is automatically prefixed with a `[plan:PROJECT_*.md]` annotation that links it back to the source plan file.
- **Execution mode** — once tasks are in your `BACKLOG.md` (as `- [ ] task description`), `buildcrew run` processes each one through the full persona pipeline. Tasks with `[plan:]` annotations automatically inject the source plan's contents into the spec phase, giving the PM richer context for writing acceptance criteria.

If you're starting fresh, Discovery mode runs automatically. Once it creates your backlog, run `buildcrew run` again to enter Execution mode. You can also run `buildcrew plan` at any time to re-enter Discovery mode — useful for planning new features or expanding scope on an existing project.

**Ad-hoc usage:** Invoke any persona directly with `/buildcrew <persona>:<task>` (e.g., `/buildcrew security-engineer:audit the API endpoints`). Run `/buildcrew` alone to see available personas.

---

## The Expert Personas

### Product Manager
*"Users tell you what they want. Your job is to understand what they need."*

- Challenges scope and finds the real problem
- Pushes back on over-complication
- Creates phased implementation plans
- Reviews plans from the user's perspective during the Plan Review phase
- **Invoked via**: `/build` or `/buildcrew product-manager:<task>`

### UX Designer
*"Good design is invisible. Users shouldn't have to think."*

- Applies 7 core design principles
- Creates comprehensive design specs
- Generates HTML mockups and iterates with you through revision rounds until the visual design is right
- Champions accessibility from the start
- **Invoked via**: `/build` (optional) or `/buildcrew ux-designer:<task>`

### Feature Engineer
*"A feature in production is worth 10 features in planning."*

- Ships user-focused features pragmatically
- Follows existing codebase patterns
- Balances velocity with quality
- **Will avoid**: Scope creep, gold-plating, premature abstraction
- **Invoked via**: Build phase (automatic) or `/buildcrew feature-engineer:<task>`

### Principal Engineer
*"The best code is the code you don't have to write."*

- Reviews plans before implementation
- Reviews code for quality and patterns
- Blocks over-engineering and code smells
- **Will reject**: Functions > 20 lines, files > 300 lines, deep nesting, magic numbers
- **Invoked via**: Plan Review and Code Review phases (automatic) or `/buildcrew principal-engineer:<task>`

### QA Engineer
*"A test that can't fail is worthless."*

- Creates test plans with real coverage
- Writes tests that fail meaningfully
- Covers happy paths AND edge cases
- **Will catch**: Untested business logic, false positives, missing boundaries
- **Invoked via**: Test phase (automatic) or `/buildcrew qa-engineer:<task>`

### Security Engineer
*"Security is not a feature. It's a foundation."*

- Performs OWASP Top 10 audits
- Detects hardcoded secrets
- Validates input handling
- **Will block**: Any critical/high vulnerabilities before commit
- **Invoked via**: Verify phase (automatic) or `/buildcrew security-engineer:<task>`

---

## The Workflow

```
┌──────────────────────────────────────────────────────────────────────────┐
│                            BuildCrew Pipeline                            │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   SPEC ──► RESEARCH+PLAN ──► PLAN REVIEW ──► [TDD] ──► BUILD ──► SIMPLIFY│
│   (PM)     (Research Agent)   (3-Pass:       (optional)  (Feature) (non- │
│                               adversarial)                        block.) │
│                                                                          │
│   COMMIT ◄── VERIFY ◄── OUTCOME ◄── TEST ◄── CODE REVIEW                │
│              (Security   (Acceptance   (QA)   (adversarial               │
│               blocks!)    criteria)           + elegance)                │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

Each task runs through **up to 10 distinct phases** (each a separate, isolated Claude invocation), keeping context focused per phase. Total invocations are bounded by `MAX_INVOCATIONS` (default: 15) — retries, chunked builds, and re-plans all count toward this ceiling:

| # | Phase | Description |
|---|-------|-------------|
| 1 | Spec | PM converts raw backlog item to testable acceptance criteria; `[plan:]` context injected when present (skip with `--skip-spec`) |
| 2 | Research + Plan | Gather context, create implementation plan |
| 3 | Plan Review (3-pass) | Adversarial review: find the most serious flaw |
| 3.5 | TDD Scaffold | Write failing tests from spec+plan before implementation (enabled by default, standard complexity only; disable with `--no-tdd`) |
| 4 | Build | Feature Engineer implements the plan |
| 5 | Simplify | Non-blocking: review and apply targeted simplifications before formal review |
| 6 | Code Review | Adversarial review + elegance check; may request rebuild |
| 7 | Test | QA Engineer writes and runs tests |
| 8 | Outcome Verification | QA validates each acceptance criterion from the spec |
| 9 | Verify (incl. Security Audit) + Commit | Final gate; Security blocks commit |

**Key features:**
- **Specification first** - PM writes testable acceptance criteria before any code is planned; after each spec, BuildCrew pauses for you to review and approve (or edit) the acceptance criteria before proceeding — pass `--auto` to skip this pause
- **Adversarial reviews** - reviewers are asked to find flaws, not to approve quickly
- **Consolidated human review** (`--review`) - single pre-build gate with inline plan display; opens your `$EDITOR` to review or edit the plan; has no effect for `trivial`-complexity tasks
- **Complexity-aware phase skipping** - tag tasks in your `BACKLOG.md` with `{trivial}`, `{simple}`, or `{standard}` (e.g., `- [ ] Fix typo in footer {trivial}`). `{trivial}` skips most phases (only build and verify run); `{simple}` skips spec, review, codereview, and outcome — research, build, test, and verify still run; `{standard}` runs all phases. BuildCrew also auto-detects complexity from the task description when no tag is present. Use `--full-pipeline` to force all phases regardless
- **Outcome verification** - QA validates acceptance criteria directly, not just test suite pass
- **Circuit breaker** - if any phase fails twice consecutively, re-plan from scratch with failure context
- **Lessons system** - failures are automatically recorded and injected into future runs
- **Quality gates** at every phase
- **Automatic iteration** when reviews find issues
- **Blocking security** - no commit until vulnerabilities are fixed
- **Feature branches** (`--branch`) - create a branch per task with automatic PR creation
- **Activity logging** - full activity log always retained at `.buildcrew/logs/`
- **Auto mode** (`--auto`) - fully unattended; auto-approves all interactive pauses
- **Chunked phase execution** - large builds that hit max-turns are automatically split and retried
- **Interactive permission recovery** - if a phase is blocked by missing permissions, BuildCrew prompts for recovery before continuing
- **Status line integration** - wired in via `buildcrew init` for real-time progress in Claude Code
- **Iterative sub-agent review** - research documents and test plans are refined through up to 5 sub-agent improvement passes before proceeding (or until convergence)
- **TDD mode** (enabled by default) - write failing tests before implementation; tests are verified to fail first, then the build phase must make them pass. Tamper detection via SHA-256 checksums prevents modification of TDD test files during build. Only active for `standard` complexity tasks. Use `--no-tdd` to disable
  > **Behavior change (v3.7+):** TDD mode is now enabled by default for `standard` complexity tasks. The `--tdd` flag is deprecated (emits a warning). To disable TDD, use `--no-tdd` or set `TDD_MODE=false` in `.buildcrew/config`. When `--skip-spec` is used without an explicit TDD setting, TDD is auto-disabled with a note.
- **Plan context bridging** - tasks generated by Discovery mode carry `[plan:PROJECT_*.md]` annotations that automatically inject the source plan into the spec phase, bridging high-level project vision with per-task execution
- **Customizable** - modify phases or remove them entirely

---

## Customization

### Custom Workflow

Skip phases, add new ones, or change the flow:

```bash
# Requires buildcrew init to have been run first
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

`agent: none` means the orchestrator handles the phase directly — no persona is invoked.

### Project Rules

Add your team's standards:

```bash
# Requires buildcrew init to have been run first
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
# Requires buildcrew init to have been run first
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
buildcrew plan               # Launch Product Manager to plan a new project or add scope
buildcrew run --single       # Process one task and stop
buildcrew run --dry-run      # Preview without executing
buildcrew run --review       # Pause for human review before build — shows plan inline, opens editor
buildcrew run --branch       # Create a feature branch per task with PR
buildcrew run --skip-spec    # Skip the spec phase (task already has detailed spec)
buildcrew run --strict       # (default) Require ALL acceptance criteria to pass before commit
buildcrew run --no-strict    # Allow partial acceptance criteria pass — proceed with warnings
buildcrew run --resume       # Resume an interrupted task from where it left off
buildcrew run --task N       # Target a specific task by name or number
buildcrew run --auto         # Run fully unattended — auto-approve all interactive pauses
buildcrew run --full-pipeline  # Force all phases regardless of complexity assessment
buildcrew run --batch        # Run pending tasks in parallel using git worktrees
buildcrew run --max-parallel N   # Max concurrent tasks in batch mode (default: 5)
buildcrew run --no-tdd       # Disable TDD mode (TDD is enabled by default for standard complexity tasks)
buildcrew run --uat          # After build, enter watch mode for UAT verdicts (implies --auto)
buildcrew run --max-invocations N  # Set max Claude invocations per run (default: 15)
buildcrew run --verbose      # Show orchestrator decisions, phase verdicts, and invocation counts
buildcrew run --debug        # Alias for --verbose
buildcrew uat --readme <path>  # Run blind UAT against a project's README
buildcrew uat --readme <path> --auto  # Run UAT fully unattended
buildcrew uat --readme <path> --regress /path/to/artifact  # Run UAT standalone against existing artifact
buildcrew uat --preview      # List existing scenarios without running agents (read-only)
buildcrew status             # Show backlog stats and last workflow result
buildcrew stop               # Stop after current task completes
buildcrew reset              # Clear blocked tasks and clean up artifacts
buildcrew repair             # Check installation health
buildcrew repair --fix       # Check and auto-fix installation health
buildcrew lessons            # List recorded lessons from past failures
buildcrew lessons promote N  # Graduate lesson N to permanent project rules
buildcrew lessons prune      # Interactively remove stale lessons
buildcrew plugins            # Show recommended plugins
buildcrew dash               # Launch the terminal dashboard (installs if needed)
buildcrew dash install       # Install buildcrew-dash
buildcrew dash update        # Update buildcrew-dash
buildcrew dash uninstall     # Remove buildcrew-dash
buildcrew update             # Update BuildCrew
buildcrew version            # Show installed version
buildcrew uninstall          # Remove BuildCrew
```

### Run Options

| Flag | Description |
|------|-------------|
| `--single` | Process one task then exit |
| `--dry-run` | Preview what would happen without executing |
| `--review` | Single pre-build gate: displays the plan inline and opens `$EDITOR` for optional edits before proceeding. Has no effect for `trivial`-complexity tasks. For `simple` tasks, the gate still fires but no adversarial review will have run — the plan is unvetted. |
| `--branch` | Create a `buildcrew/<slug>` feature branch per task. Pushes to remote and creates a PR via `gh` if available. Each task branches independently from the base branch. |
| `--resume` | Resume an interrupted task from where it left off |
| `--task N` | Target a specific task by name or number |
| `--skip-spec` | Skip the spec phase. Use when the backlog item already contains a detailed spec with acceptance criteria. |
| `--strict` | (default) Require ALL acceptance criteria to pass during Outcome Verification before the commit is allowed. Has no effect whenever the outcome phase is skipped — e.g., for `{trivial}` or `{simple}` tasks. |
| `--no-strict` | Allow partial acceptance criteria pass — unmet criteria trigger a warning but don't block the commit. |
| `--full-pipeline` | Force all phases regardless of complexity assessment |
| `--auto` | Run fully unattended — auto-approve all interactive pauses |
| `--batch` | Run all pending BACKLOG.md tasks in parallel, each through the full phase pipeline in its own git worktree. Use `--resume` to pick up where an interrupted batch left off. Incompatible with `--single` and `--task`. |
| `--max-parallel N` | Max concurrent tasks in batch mode (default: 5). Also configurable via `MAX_PARALLEL` in `.buildcrew/config`. |
| `--tdd` | (deprecated) TDD is now enabled by default; this flag is a no-op. Emits a deprecation warning to stderr. |
| `--no-tdd` | Disable TDD mode: skip the `tdd-scaffold` phase between plan review and build. TDD is enabled by default for `standard` complexity tasks. Also configurable via `TDD_MODE=false` in `.buildcrew/config`. |
| `--uat` | After a successful build, publish the artifact and enter watch mode for UAT verdicts. Implies `--auto`. Use with `buildcrew uat` in a separate terminal. |
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
| `TDD_MODE` | `true` | Enable TDD mode: write failing tests before implementation. Set to `false` to disable (equivalent to `--no-tdd`). Only active for `standard` complexity tasks. |
| `MAX_PARALLEL` | `5` | Max concurrent tasks in batch mode. Equivalent to `--max-parallel N`. |
| `UAT_MAX_RETRIES` | `5` | Max build-fix-test iterations in UAT watch mode. |
| `UAT_ARTIFACT_TYPE` | (auto-detected) | Override artifact type detection (`cli`, `api`, `library`, `tui`). |
| `UAT_RUN_COMMAND` | (auto-detected) | Override how to run/start the artifact. |
| `BUILD_UAT_WATCH_TIMEOUT` | `600` | Seconds to wait for UAT verdict before exiting watch mode. |

Example `.buildcrew/config`:

```bash
MAX_INVOCATIONS=20
COMPLEXITY_AWARE=true
AUTO_MODE=false
```

---

## Task Annotations

Tasks in `BACKLOG.md` support optional prefix annotations that the orchestrator processes before execution:

```markdown
- [ ] [plan:PROJECT_webapp.md] [dir:frontend] Implement login page
```

| Annotation | Purpose |
|------------|---------|
| `[plan:FILE]` | Links to a discovery plan file. The file's contents are injected into the spec phase as starting context, bridging project vision with per-task execution. Added automatically by Discovery mode. |
| `[dir:DIR]` | Targets a specific subdirectory in multi-project setups. The task runs against that directory instead of the project root. |

Annotations are orchestrator metadata — they are stripped before the task text reaches personas. Order is `[plan:]` then `[dir:]` then task text, optionally followed by a `{complexity}` tag.

---

## The Lessons System

BuildCrew learns from its mistakes across runs. After any failed iteration (review rejection, test failure, circuit breaker trigger), it automatically records a structured lesson in `.buildcrew/lessons.md`.

Each lesson captures what went wrong, what fixed it, and a rule to prevent it next time. Lessons are **automatically injected into every phase's context** — just like `users.md` or `principles.md`.

```bash
buildcrew lessons              # List all recorded lessons
buildcrew lessons promote 3    # Graduate lesson 3 to .buildcrew/rules/project-rules.md
buildcrew lessons prune        # Interactively review and delete stale lessons
```

Lessons are capped at 25 entries. When exceeded, the oldest 10 are condensed into a summary "Patterns" section to keep context injection bounded. Duplicate rules are automatically skipped — if an identical rule already exists, the new lesson is silently dropped.

---

## Circuit Breaker

If any phase fails its quality gate **twice consecutively**, BuildCrew stops grinding and re-plans from scratch:

1. Logs what was tried and why it failed
2. Appends a lesson to `.buildcrew/lessons.md`
3. Restarts from Research + Planning with the failure as context
4. Outputs: `[CIRCUIT BREAKER] Approach failed twice at <phase>. Re-planning from scratch with failure context.`

The re-plan gets **one attempt**. If it hits the circuit breaker again, the task is blocked and reported to the user.

---

## Blind UAT (User Acceptance Testing)

BuildCrew includes a **blind UAT system** that tests your project against its README — without the test agent seeing the source code or the build agent seeing the tests.

### How it works

1. The **build side** writes code and publishes a runnable artifact
2. The **UAT side** reads only the README, generates test scenarios, and executes them against the artifact
3. If tests fail, a structured verdict (what failed, what was expected) is sent back to the build side — without revealing the test code
4. The build agent fixes the issues and the cycle repeats

This ensures the tests validate *documented behavior*, not implementation details.

### Quick Start (new project)

```bash
# Terminal A: build the project
cd my-project
buildcrew plan                           # create README + spec + plan
buildcrew run --uat                      # build code, then watch for UAT results

# Terminal B: run blind UAT (in a sibling directory)
mkdir ../my-project-uat && cd ../my-project-uat
buildcrew uat --readme ../my-project/README.md
```

### Adding UAT to an existing project

Any project with a README can use UAT — no setup needed in the project directory itself:

```bash
# From your existing project (already has README.md)
cd my-existing-project
buildcrew run --uat                      # builds normally, then enters watch mode

# In a new sibling directory
mkdir ../my-existing-project-uat && cd ../my-existing-project-uat
buildcrew uat --readme ../my-existing-project/README.md
```

The `--uat` flag on `buildcrew run` tells the build side to publish an artifact and watch for UAT verdicts after each successful build. The `buildcrew uat` command is fully standalone — it only needs a path to the README.

For projects that don't auto-detect correctly (e.g., artifact type or run command), add overrides to `.buildcrew/config`:

```bash
# In the build project's .buildcrew/config
UAT_ARTIFACT_TYPE=cli           # cli, api, library, tui
UAT_RUN_COMMAND=./bin/myapp     # how to run the artifact
```

### UAT Options

| Flag | Description |
|------|-------------|
| `--readme <path>` | (Required unless `--preview`) Path to the project's README.md |
| `--project <name>` | Project identifier (default: derived from README parent dir) |
| `--artifact-dir <path>` | Override artifact discovery path |
| `--signal-dir <path>` | Override signal file path |
| `--regress <path>` | Run UAT standalone against an existing artifact directory (implies `--auto`). Incompatible with `--artifact-dir` and `--preview`. |
| `--preview` | List existing scenarios without running agents (read-only). Incompatible with `--regress`. |
| `--auto` | Auto mode: log disputes without pausing |

### How UAT phases work

| Phase | Actor | Description |
|-------|-------|-------------|
| 1. Extract User Stories | Claude agent | Reads README, extracts user stories |
| 2. Generate Scenarios | Claude agent | Creates Given/When/Then test scenarios |
| 3. Build Test Harness | Claude agent | Writes executable test scripts |
| 4. Wait for Artifact | Orchestrator | Polls for build artifact (manifest.json) |
| 4.5. Set Up Environment | Orchestrator | Creates wrapper scripts so agent never touches source |
| 5. Execute Scenarios | Claude agent | Runs tests against artifact, collects results |
| 6. Write Verdict | Orchestrator | Assembles verdict, sends to build side |

On failure, the build side re-enters build-through-verify with the verdict as context, then republishes. UAT retries up to 5 times (configurable via `UAT_MAX_RETRIES`).

---

## Terminal Dashboard

BuildCrew ships with an optional terminal dashboard (`buildcrew-dash`) that gives you a live view of workflow progress.

```bash
buildcrew dash          # Launch (prompts to install if not present)
buildcrew dash install  # Install separately
```

The dashboard shows the current phase, agent activity (tool calls, turn counts), and workflow state in real time. It reads from `.buildcrew/.agent-activity`, which BuildCrew writes automatically during each phase when Python 3 is available. If Python 3 is not installed, activity tracking degrades gracefully — the pipeline runs normally, the dashboard just won't show per-tool detail.

---

## How It Works

1. **Install once** to `~/.buildcrew/` — contains all persona skill files, default rules, and the workflow orchestrator
2. **Link any project** with `buildcrew init` — creates `.buildcrew/` (your customizations), symlinks skills/commands into `.claude/`, and writes `.claude/settings.json` with autonomous operation permissions
3. **Rules merge** in order: global defaults → persona rules → your project rules (`.buildcrew/rules/project-rules.md`)
4. **Communication is file-based** — the orchestrator and each Claude invocation share state through files in `.buildcrew/` and `.claude/`. No pipes, no env vars between phases. Each phase writes a `phase-result.json` verdict that drives the next orchestrator decision
5. **Phases are isolated** — each phase is a fresh `claude -p` invocation with only the context it needs, preventing context bleed between roles

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

- **No auto-push** - Commits stay local until you review and push (unless `--branch` is used — feature branches are pushed automatically and a PR is created via `gh`)
- **Human review** (`--review`) - single pre-build gate: displays the plan inline and pauses for inspection before proceeding
- **Blocking gates** - Security issues must be fixed before commit
- **Deny-list protection** - System directories protected even when `rm` is allowed

---

## Requirements

- **Claude Code CLI** installed and authenticated
- **jq** for JSON parsing (`brew install jq`)
- **Python 3** in your `PATH` (optional — enables real-time activity tracking for `buildcrew-dash`; degrades gracefully if absent)
- **gh CLI** (optional — required for PR creation with `--branch`; `brew install gh`)

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
