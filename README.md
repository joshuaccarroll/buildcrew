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

BuildCrew processes each task through a **9-phase pipeline** with quality gates:

```
┌─────────┐   ┌─────────────┐   ┌─────────┐   ┌─────────────┐
│ 1.PLAN  │──▶│2.PLAN REVIEW│──▶│ 3.BUILD │──▶│4.CODE REVIEW│
└─────────┘   │ (Principal) │   │(Feature │   │ (Principal) │
              └─────────────┘   │Engineer)│   └─────────────┘
                                └─────────┘          │
┌──────────┐   ┌──────────┐   ┌────────────┐   ┌─────────────┐
│ 9.SIGNAL │◀──│ 8.COMMIT │◀──│ 7.VERIFY   │◀──│ 6.TEST      │
└──────────┘   └──────────┘   │(BLOCKING)  │   │(QA Engineer)│
                              │- Tests     │   └─────────────┘
                              │- Code Rev  │         ▲
                              │- Security  │   ┌─────────────┐
                              └────────────┘   │ 5.REFACTOR  │
                                               │ (if needed) │
                                               └─────────────┘
```

### The 9 Phases

| Phase | Description | Persona |
|-------|-------------|---------|
| **1. PLAN** | Analyze task, explore codebase, create implementation plan | - |
| **2. PLAN REVIEW** | Review plan for architecture, simplicity, testability | Principal Engineer |
| **3. BUILD** | Implement changes with focus on user value | Feature Engineer |
| **4. CODE REVIEW** | Review code for quality, SOLID principles, security | Principal Engineer |
| **5. REFACTOR** | Fix issues found in code review (if needed) | - |
| **6. TEST** | Create test plan, write tests, run test suite | QA Engineer |
| **7. VERIFY** | **Blocking gate**: All tests, reviews, and security checks must pass | Security Engineer |
| **8. COMMIT** | Create conventional commit (local only) | - |
| **9. SIGNAL** | Write completion status for orchestrator | - |

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

### Feature Engineer (Workflow Mode)

Builds features with 8+ years at high-velocity startups. Focuses on:
- **Ship Value to Users** - Features in production matter most
- **Pragmatic Quality** - Good enough today beats perfect never
- **Respect the Architecture** - Works with the codebase, not against it
- **User Delight** - Every interaction is an opportunity

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

### Security Engineer (Workflow Mode)

Performs security audits with 10+ years in application security. Checks:
- **OWASP Top 10** - Injection, XSS, broken auth, etc.
- **Secrets Detection** - API keys, passwords, tokens
- **Input Validation** - All user inputs validated
- **Dependency Audit** - No vulnerable packages

Will **BLOCK** deployment if:
- Critical or high vulnerabilities found
- Hardcoded secrets detected
- Missing input validation on user data

---

## CLI Commands

```bash
buildcrew              # Show help
buildcrew init         # Initialize in current project
buildcrew run          # Run workflow on BACKLOG.md
buildcrew plugins      # Show recommended plugins for your project
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
│   │   ├── builder/                 # Greenfield project builder
│   │   ├── product-manager/         # Product discovery
│   │   ├── ux-designer/             # Design discovery
│   │   ├── buildcrew/               # Main workflow orchestration
│   │   ├── feature-engineer/        # Pragmatic feature building
│   │   ├── principal-engineer/      # Plan & code review
│   │   ├── qa-engineer/             # Testing
│   │   └── security-engineer/       # Security audits
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

## Plugin Recommendations

BuildCrew detects your project type and recommends useful plugins:

```bash
buildcrew plugins
```

**Recommended plugins include:**

| Plugin | Type | When Recommended |
|--------|------|------------------|
| `frontend-design` | skill | Frontend frameworks detected |
| `playwright-mcp` | mcp | Frontend/E2E testing |
| `github-mcp` | mcp | Git repository detected |
| `typescript-lsp` | lsp | TypeScript project |
| `python-lsp` | lsp | Python project |

Plugins are recommended:
- During `buildcrew init`
- On first `buildcrew run` (one-time tip)
- Anytime via `buildcrew plugins`

---

## The Verify Stage

The **VERIFY** stage is a **blocking gate** that ensures all quality checks pass before commit:

### What Gets Verified

1. **Test Suite** - All tests must pass
2. **Code Review** - Must be APPROVED by Principal Engineer
3. **Security Audit** - No critical/high vulnerabilities
4. **Architecture** - No breaking changes

### Blocking Behavior

If any check fails:
- The task returns to the appropriate phase for fixes
- Maximum 3 attempts before marking task as BLOCKED
- All fixes must be verified before commit

### Security Audit Details

The Security Engineer checks for:
- OWASP Top 10 vulnerabilities
- Hardcoded secrets (API keys, passwords)
- Input validation gaps
- Dependency vulnerabilities (`npm audit`, etc.)

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
