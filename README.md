# Josh Workflow

An autonomous development pipeline for Claude Code with expert personas for planning, design, review, and testing.

## Overview

Josh Workflow provides two modes:

1. **Builder Mode** (`/build`) - Start a new project from scratch with expert guidance
2. **Workflow Mode** (`./workflow.sh`) - Execute backlog tasks autonomously

```
┌─────────────────────────────────────────────────────────────────────┐
│  /build                                                              │
│  ├── Product Manager → PROJECT_[name].md                            │
│  ├── UX Designer → DESIGN_[name].md (optional)                      │
│  └── Generate → BACKLOG.md                                          │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  ./workflow.sh                                                       │
│  └── For each task in BACKLOG.md:                                   │
│      Plan → Review → Build → Review → Test → Commit                 │
└─────────────────────────────────────────────────────────────────────┘
```

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

### Option A: Start a New Project (Builder Mode)

Use `/build` to create a new project from scratch:

```
/build
```

This launches an interactive session with expert personas:

1. **Product Manager** asks about your vision, users, and goals
2. **UX Designer** (optional) helps define visual style and user flows
3. **Backlog Generator** creates `BACKLOG.md` from your plan

### Option B: Execute an Existing Backlog

If you already have tasks, add them to `BACKLOG.md`:

```markdown
## High Priority
- [ ] Implement user authentication with JWT
- [ ] Add dark mode toggle to settings page

## Medium Priority
- [ ] Refactor API error handling
```

Then run the workflow:

```bash
./workflow.sh              # Process all tasks
./workflow.sh --single     # Process just one task
./workflow.sh --dry-run    # Preview without executing
```

---

## Builder Mode (`/build`)

For greenfield projects, the builder guides you through comprehensive planning before any code is written.

### The Builder Flow

```
/build
   │
   ▼
┌─────────────────────────────────────────┐
│  PRODUCT MANAGER                         │
│  "What are you trying to build?"        │
│  "What problem does this solve?"        │
│  "Who are the users?"                   │
│  → Creates PROJECT_[name].md            │
└─────────────────────────────────────────┘
   │
   ▼
┌─────────────────────────────────────────┐
│  UX DESIGNER (if UI needed)             │
│  "What's the visual style?"             │
│  "Walk me through the user flows"       │
│  → Creates DESIGN_[name].md             │
└─────────────────────────────────────────┘
   │
   ▼
┌─────────────────────────────────────────┐
│  BACKLOG GENERATOR                       │
│  Converts phases → BACKLOG.md           │
│  Ready for ./workflow.sh                │
└─────────────────────────────────────────┘
```

### Product Manager Persona

A Senior PM with 12+ years experience who:
- Asks probing questions to understand the real problem
- **Pushes back** on over-complication
- Values simple, elegant solutions
- Creates phased implementation plans

### UX Designer Persona

A Senior Designer with 10+ years experience who:
- Follows **7 Design Principles**: Hierarchy, Progressive Disclosure, Consistency, Contrast, Accessibility, Proximity, Alignment
- Favors easily-grokable UI over novelty
- Thinks through user flows before placing elements
- Creates comprehensive design specs

### Output Files

| File | Contents |
|------|----------|
| `PROJECT_[name].md` | Vision, users, success metrics, phased tasks |
| `DESIGN_[name].md` | Colors, typography, components, wireframes |
| `BACKLOG.md` | Tasks extracted from project, ready to execute |

---

## Workflow Mode (`./workflow.sh`)

Processes backlog tasks autonomously through an 8-phase cycle with quality gates.

### The 8 Phases

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
├── workflow.sh                          # Workflow orchestrator
├── BACKLOG.md                           # Task backlog
├── PROJECT_[name].md                    # Project plan (from /build)
├── DESIGN_[name].md                     # Design spec (from /build)
└── .claude/
    ├── settings.json                    # Permissions allowlist
    ├── commands/
    │   └── build.md                     # /build slash command
    ├── skills/
    │   ├── builder/
    │   │   └── SKILL.md                 # Builder orchestrator
    │   ├── product-manager/
    │   │   └── SKILL.md                 # PM persona
    │   ├── ux-designer/
    │   │   └── SKILL.md                 # Designer persona
    │   ├── josh-workflow/
    │   │   └── SKILL.md                 # Workflow (8 phases)
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
