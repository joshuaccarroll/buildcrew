# Josh Workflow

An autonomous development pipeline for Claude Code that processes backlog tasks through a rigorous 8-phase workflow with built-in expert personas.

## Overview

Josh Workflow automates the software development lifecycle by:
1. Reading tasks from a markdown backlog
2. Processing each task through plan, review, build, test, and commit phases
3. Using expert personas (Principal Engineer, QA Engineer) for quality gates
4. Clearing context between tasks for reliability

```
┌─────────┐   ┌─────────────┐   ┌─────────┐   ┌─────────────┐
│ 1.PLAN  │──▶│2.PLAN REVIEW│──▶│ 3.BUILD │──▶│4.CODE REVIEW│
└─────────┘   │ (Principal) │   └─────────┘   │ (Principal) │
              └─────────────┘                 └─────────────┘
                                                    │
┌──────────┐   ┌──────────┐   ┌───────────────┐     │
│ 8.SIGNAL │◀──│ 7.COMMIT │◀──│ 6.TEST        │◀────┘
└──────────┘   └──────────┘   │ (QA Engineer) │
                              └───────────────┘
                                    ▲
                              ┌─────────────┐
                              │ 5.REFACTOR  │
                              │ (if needed) │
                              └─────────────┘
```

## Quick Start

### 1. Add Tasks to Your Backlog

Edit `BACKLOG.md`:

```markdown
## High Priority
- [ ] Implement user authentication with JWT
- [ ] Add dark mode toggle to settings page

## Medium Priority
- [ ] Refactor API error handling
```

### 2. Run the Workflow

```bash
./workflow.sh              # Process all tasks
./workflow.sh --single     # Process just one task
./workflow.sh --dry-run    # Preview without executing
```

### 3. Watch It Work

The workflow runs in your terminal, showing progress through each phase.

## The 8 Phases

| Phase | Description | Persona |
|-------|-------------|---------|
| **1. PLAN** | Analyze task, explore codebase, create implementation plan | - |
| **2. PLAN REVIEW** | Review plan for architecture, simplicity, testability | Principal Engineer |
| **3. BUILD** | Implement changes according to approved plan | - |
| **4. CODE REVIEW** | Review code for quality, SOLID principles, security | Principal Engineer |
| **5. REFACTOR** | Fix issues found in code review (if needed) | - |
| **6. TEST** | Create test plan, write tests, run test suite | QA Engineer |
| **7. COMMIT** | Create conventional commit (local only) | - |
| **8. SIGNAL** | Write completion status for orchestrator | - |

## Expert Personas

### Principal Engineer

Reviews plans and code with 15+ years of experience. Enforces:

- **Simplicity** - Is this the simplest approach?
- **Readability** - Will this be maintainable?
- **Modularity** - Are concerns properly separated?
- **Testability** - Can this be tested effectively?

Will **NOT** tolerate:
- Over-engineering for hypothetical futures
- Poor separation of concerns
- God classes, deep nesting, magic numbers
- Untested business logic

### Senior QA Engineer

Handles testing with 12+ years of experience. Ensures:

- **Tests fail meaningfully** - Clear failure conditions
- **Tests pass only when correct** - No false positives
- **Comprehensive coverage** - Happy paths, errors, edge cases

Creates test plans before writing tests, follows the test pyramid.

## Project Structure

```
josh-workflow/
├── workflow.sh                          # Orchestrator script
├── BACKLOG.md                           # Your task backlog
├── README.md                            # This file
└── .claude/
    ├── settings.json                    # Permissions allowlist
    ├── skills/
    │   ├── josh-workflow/
    │   │   └── SKILL.md                 # Main workflow (8 phases)
    │   ├── principal-engineer/
    │   │   └── SKILL.md                 # PE persona
    │   └── qa-engineer/
    │       └── SKILL.md                 # QA persona
    └── rules/
        └── coding-principles.md         # Standards & anti-patterns
```

## Customization

### Add Your Own Coding Rules

Edit `.claude/rules/coding-principles.md` and add rules under "Custom Rules":

```markdown
## Custom Rules

### API Design
- All endpoints must return consistent error format
- Use plural nouns for resource collections

### Database
- All queries must use parameterized statements
- No N+1 query patterns
```

### Extend Permissions

Edit `.claude/settings.json` to allow additional commands:

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run:*)",
      "Bash(your-command:*)"
    ]
  }
}
```

### Modify the Workflow

Edit `.claude/skills/josh-workflow/SKILL.md` to change phases or behavior.

## Safety Features

- **Allowlist permissions**: Only pre-approved commands run without prompts
- **No auto-push**: Commits stay local until you push manually
- **Blocked tasks**: Tasks that can't complete are marked, not retried forever
- **Context isolation**: Each task runs in a fresh Claude session

## Backlog Format

Tasks use markdown checklist format:

```markdown
- [ ] Pending task
- [x] Completed task
- [!] Blocked task (reason)
```

Write clear, actionable descriptions:
- **Good**: `Implement user login with email/password authentication`
- **Bad**: `Add login` (too vague)

## Requirements

- Claude Code CLI installed and authenticated
- `jq` for JSON parsing (`brew install jq`)

## Output Files (gitignored)

During execution, the workflow creates temporary files:

| File | Purpose |
|------|---------|
| `.claude/current-plan.md` | Implementation plan |
| `.claude/plan-review.md` | Principal Engineer's plan review |
| `.claude/code-review.md` | Principal Engineer's code review |
| `.claude/current-test-plan.md` | QA Engineer's test plan |
| `.claude/test-report.md` | Test execution results |
| `.claude/workflow-status.json` | Completion signal for orchestrator |

## License

MIT
