# BuildCrew

An autonomous AI development pipeline for Claude Code with expert personas for planning, design, review, and testing.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

BuildCrew provides two modes for AI-assisted software development:

1. **Builder Mode** (`/build`) - Start a new project from scratch with expert guidance
2. **Workflow Mode** (`buildcrew run`) - Execute backlog tasks autonomously

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
│  buildcrew run                                                       │
│  └── For each task in BACKLOG.md:                                   │
│      Plan → Review → Build → Review → Test → Commit                 │
└─────────────────────────────────────────────────────────────────────┘
```

## Installation

### Quick Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/joshuacarroll/buildcrew/main/install.sh | bash
```

### Homebrew (macOS/Linux)

```bash
brew tap joshuacarroll/tap
brew install buildcrew
```

### Manual Installation

```bash
git clone https://github.com/joshuacarroll/buildcrew.git
cd buildcrew
./install.sh
```

## Quick Start

### 1. Initialize in Your Project

```bash
cd your-project
buildcrew init
```

This creates:
- `.claude/skills/` - AI workflow skills
- `.claude/commands/` - Slash commands (like `/build`)
- `.claude/rules/` - Coding principles
- `BACKLOG.md` - Task backlog template
- `.claude/settings.json` - Permissions configuration

### 2. Start a New Project (Builder Mode)

In Claude Code, run:
```
/build
```

This launches an interactive session with expert personas:
1. **Product Manager** asks about your vision, users, and goals
2. **UX Designer** (optional) helps define visual style and user flows
3. **Backlog Generator** creates `BACKLOG.md` from your plan

### 3. Execute the Workflow

```bash
buildcrew run              # Process all tasks
buildcrew run --single     # Process just one task
buildcrew run --dry-run    # Preview without executing
```

---

## The Workflow Pipeline

BuildCrew processes each task through an 8-phase pipeline with quality gates:

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

---

## Expert Personas

### Product Manager (Builder Mode)

A Senior PM with 12+ years experience who:
- Asks probing questions to understand the real problem
- **Pushes back** on over-complication
- Values simple, elegant solutions
- Creates phased implementation plans

### UX Designer (Builder Mode)

A Senior Designer with 10+ years experience who:
- Follows **7 Design Principles**: Hierarchy, Progressive Disclosure, Consistency, Contrast, Accessibility, Proximity, Alignment
- Favors easily-grokable UI over novelty
- Thinks through user flows before placing elements
- Creates comprehensive design specs

### Principal Engineer (Workflow Mode)

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

### Senior QA Engineer (Workflow Mode)

Handles testing with 12+ years of experience. Ensures:
- **Tests fail meaningfully** - Clear failure conditions
- **Tests pass only when correct** - No false positives
- **Comprehensive coverage** - Happy paths, errors, edge cases

---

## CLI Commands

```bash
buildcrew              # Show help
buildcrew init         # Initialize in current project
buildcrew run          # Run workflow on BACKLOG.md
buildcrew update       # Check for and install updates
buildcrew version      # Show version
buildcrew uninstall    # Remove buildcrew from system
```

### Run Options

```bash
buildcrew run              # Process all pending tasks
buildcrew run --single     # Process one task and exit
buildcrew run --dry-run    # Preview without executing
```

---

## Backlog Format

Tasks use markdown checklist format:

```markdown
## High Priority
- [ ] Implement user authentication with JWT
- [ ] Add dark mode toggle to settings page

## Medium Priority
- [ ] Refactor API error handling
```

### Task States

```markdown
- [ ] Pending task
- [x] Completed task
- [!] Blocked task (reason)
```

Write clear, actionable descriptions:
- **Good**: `Implement user login with email/password authentication`
- **Bad**: `Add login` (too vague)

---

## Project Structure

After `buildcrew init`, your project will have:

```
your-project/
├── .claude/
│   ├── skills/                      # AI workflow skills
│   │   ├── builder/
│   │   ├── product-manager/
│   │   ├── ux-designer/
│   │   ├── josh-workflow/
│   │   ├── principal-engineer/
│   │   └── qa-engineer/
│   ├── commands/
│   │   └── build.md                 # /build slash command
│   ├── rules/
│   │   └── coding-principles.md     # Coding standards
│   └── settings.json                # Permissions
├── BACKLOG.md                       # Task backlog
├── PROJECT_[name].md                # Project plan (from /build)
└── DESIGN_[name].md                 # Design spec (from /build)
```

---

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

---

## Safety Features

- **Allowlist permissions**: Only pre-approved commands run without prompts
- **No auto-push**: Commits stay local until you push manually
- **Blocked tasks**: Tasks that can't complete are marked, not retried forever
- **Context isolation**: Each task runs in a fresh Claude session

---

## Updating

BuildCrew checks for updates automatically on each run. To update:

```bash
buildcrew update
```

---

## Requirements

- **Claude Code CLI** installed and authenticated
- **jq** for JSON parsing (`brew install jq`)

---

## Uninstalling

```bash
buildcrew uninstall
```

This removes BuildCrew from your system. Project files (`.claude/`, `BACKLOG.md`, etc.) are NOT removed.

---

## License

MIT

---

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## Support

- **Issues**: [GitHub Issues](https://github.com/joshuacarroll/buildcrew/issues)
- **Documentation**: [GitHub Wiki](https://github.com/joshuacarroll/buildcrew/wiki)
