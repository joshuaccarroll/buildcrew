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

---

## Quick Start

### Install (once, globally)

```bash
curl -fsSL https://raw.githubusercontent.com/joshuaccarroll/buildcrew/main/install.sh | bash
```

### Use in any project

```bash
cd your-project
buildcrew init           # Link to BuildCrew
```

In Claude Code:
```
/build                   # Start a new project with expert guidance
/buildcrew product-manager   # Invoke a persona ad-hoc
```

Run the workflow:
```bash
buildcrew run            # Process your backlog autonomously
```

That's it. Install once, use everywhere.

---

## The Expert Personas

### Product Manager
*"Users tell you what they want. Your job is to understand what they need."*

- Challenges scope and finds the real problem
- Pushes back on over-complication
- Creates phased implementation plans
- **Invoked via**: `/build` or `/buildcrew product-manager`

### UX Designer
*"Good design is invisible. Users shouldn't have to think."*

- Applies 7 core design principles
- Creates comprehensive design specs
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
┌──────────────────────────────────────────────────────────────────┐
│                         BuildCrew Pipeline                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│   PLAN ──► PLAN REVIEW ──► BUILD ──► CODE REVIEW ──► TEST        │
│              (Principal)      (Feature)   (Principal)    (QA)     │
│                                                                   │
│                           ┌─────────────┐                         │
│   COMMIT ◄── SECURITY ◄──┤   VERIFY    │◄── REFACTOR (if needed) │
│              (blocks!)    │  (blocking) │                         │
│                           └─────────────┘                         │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

**Key features:**
- **Quality gates** at every phase
- **Automatic iteration** when reviews find issues
- **Blocking security** - no commit until vulnerabilities are fixed
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

### Phase 1: BUILD
agent: feature-engineer

### Phase 2: TEST
agent: qa-engineer

### Phase 3: COMMIT
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

### Linting & Formatting
- Run `npm run lint` before committing
- All TypeScript files must pass strict mode
- Use Prettier with project config

### Naming Conventions
- React components: PascalCase (UserProfile.tsx)
- Utilities: camelCase (formatDate.ts)
- Constants: SCREAMING_SNAKE_CASE
- Database tables: snake_case

### API Design
- All endpoints return { data, error, meta }
- Use plural nouns: /users, /products
- Version all APIs: /v1/users

### Operational Rules
- API calls must use exponential backoff
- Batch updates to prevent thundering herd
- Rate limit external API calls to 10/sec

### Database
- No N+1 query patterns
- Index all foreign keys
- Use transactions for multi-step operations
```

---

## CLI Commands

```bash
buildcrew              # Show help
buildcrew init         # Link project to BuildCrew
buildcrew run          # Run workflow on BACKLOG.md
buildcrew run --single # Process one task and stop
buildcrew run --dry-run # Preview without executing
buildcrew plugins      # Show recommended plugins
buildcrew update       # Update BuildCrew
buildcrew uninstall    # Remove BuildCrew
```

---

## Ad-hoc Persona Invocation

Use personas outside the workflow for specific tasks:

```
/buildcrew security-engineer    # Security audit on current code
/buildcrew product-manager      # Discovery for a new feature
/buildcrew principal-engineer   # Review a pull request
/buildcrew qa-engineer          # Create a test plan
/buildcrew ux-designer          # Design spec for a component
```

---

## How It Works

### Global Installation
BuildCrew installs once to `~/.buildcrew/` with all personas, rules, and workflows.

### Project Linking
Running `buildcrew init` creates a lightweight link:
```
your-project/
├── .claude/
│   ├── .buildcrew-link    # Points to ~/.buildcrew
│   └── settings.json      # Permissions
├── .buildcrew/            # Your customizations
│   ├── rules/             # Project-specific rules
│   └── workflow.md        # Custom workflow (optional)
└── BACKLOG.md             # Your task list
```

### Rule Hierarchy
Rules merge in order (later overrides earlier):
1. `~/.buildcrew/rules/core-principles.md`
2. `~/.buildcrew/rules/{persona}-rules.md`
3. `.buildcrew/rules/project-rules.md`
4. `.buildcrew/rules/{persona}-rules.md`

---

## Safety Features

- **Allowlist permissions** - Only pre-approved commands run without prompts
- **No auto-push** - Commits stay local until you push
- **Blocking gates** - Security issues must be fixed before commit
- **Attempt limits** - Tasks that can't complete are marked blocked, not retried forever
- **Context isolation** - Each task runs in a fresh Claude session

---

## Requirements

- **Claude Code CLI** installed and authenticated
- **jq** for JSON parsing (`brew install jq`)

---

## Installation Options

### Quick Install (Recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/joshuaccarroll/buildcrew/main/install.sh | bash
```

### Homebrew
```bash
brew tap joshuaccarroll/tap
brew install buildcrew
```

### Manual
```bash
git clone https://github.com/joshuaccarroll/buildcrew.git
cd buildcrew && ./install.sh
```

---

## Why BuildCrew?

| Without BuildCrew | With BuildCrew |
|-------------------|----------------|
| AI writes code fast, you review later | Expert personas review in real-time |
| Security issues slip through | Security blocks deployment |
| Tests for coverage, not correctness | Tests that catch real bugs |
| Over-engineered for hypothetical futures | Pragmatic code for today's needs |
| Features that miss the point | Problems solved at the root |

**BuildCrew is your AI development team with built-in code review, security audit, and quality gates.**

---

## License

MIT

---

## Links

- **Repository**: [github.com/joshuaccarroll/buildcrew](https://github.com/joshuaccarroll/buildcrew)
- **Issues**: [GitHub Issues](https://github.com/joshuaccarroll/buildcrew/issues)
- **Claude Code**: [claude.ai/code](https://claude.ai/code)
